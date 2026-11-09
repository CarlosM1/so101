"""Launcher for LeRobot's async robot client (used by scripts/11_robot_client.sh).

1. Registers the zmq camera type, which LeRobot 0.6.1's robot_client forgets to import.
2. With DEBUG_QUEUE=1, logs every action-chunk merge so you can see whether new predictions
   replace the queued ones:
     latest=#t           last action already sent to the arm
     queue=a..b          timesteps waiting in the queue before the merge
     chunk=c..d          timesteps in the chunk that just arrived from the Spark
     stale=n             chunk actions skipped because their time has already passed
     blended=n           timesteps present in both: 0.3*old + 0.7*new (weighted_average)
     dropped=n           old queued actions not covered by the new chunk (thrown away)
     max_jump=x          largest joint difference (degrees) between old and new plan
                         on the blended timesteps, with the joint name
3. Uploads observations in a background thread (disable with ASYNC_SEND=0).
   Stock LeRobot uploads each ~1.8 MB observation (two raw 640x480 images) INSIDE the 30 Hz
   control loop and waits for it: on Wi-Fi that froze the arm for 60-100 ms per upload (the
   stutter). Now the loop only hands the observation over and keeps executing actions. If an
   upload is still in flight, a newer observation replaces the waiting one (only the freshest
   matters); a pending "must_go" flag is carried over so the server never misses a forced one.
   Then it runs the client like `python -m lerobot.async_inference.robot_client` would.
"""

import os
import threading

import lerobot.cameras.zmq  # noqa: F401  (registers the "zmq" camera type)

if os.environ.get("ASYNC_SEND", "1") != "0":
    from lerobot.async_inference import robot_client as rc

    blocking_send = rc.RobotClient.send_observation

    def background_send(self, obs):
        if not hasattr(self, "_send_cv"):
            self._send_cv = threading.Condition()
            self._send_pending = None

            def sender():
                while True:
                    with self._send_cv:
                        while self._send_pending is None:
                            self._send_cv.wait()
                        item, self._send_pending = self._send_pending, None
                    if not self.running:
                        return
                    try:
                        blocking_send(self, item)
                    except Exception as e:  # never kill the sender thread
                        self.logger.error(f"Background observation send failed: {e}")

            threading.Thread(target=sender, name="obs-sender", daemon=True).start()

        with self._send_cv:
            if self._send_pending is not None and self._send_pending.must_go:
                obs.must_go = True  # don't lose a forced observation we're replacing
            self._send_pending = obs
            self._send_cv.notify()
        return True

    rc.RobotClient.send_observation = background_send

if os.environ.get("DEBUG_QUEUE") == "1":
    import logging

    from lerobot.async_inference import robot_client as rc  # noqa: F811

    log = logging.getLogger("queue-debug")
    original = rc.RobotClient._aggregate_action_queues

    def logged(self, incoming_actions, aggregate_fn=None):
        with self.action_queue_lock:
            old = {a.get_timestep(): a.get_action() for a in list(self.action_queue.queue)}
        with self.latest_action_lock:
            latest = self.latest_action
        fresh = [a for a in incoming_actions if a.get_timestep() > latest]
        new_steps = {a.get_timestep() for a in fresh}
        overlap = [a for a in fresh if a.get_timestep() in old]

        jump, joint = 0.0, "-"
        names = list(self.robot.action_features)
        for a in overlap:
            diff = (a.get_action().float() - old[a.get_timestep()].float()).abs()
            if float(diff.max()) > jump:
                jump, joint = float(diff.max()), names[int(diff.argmax())]

        steps = [a.get_timestep() for a in incoming_actions]
        log.info(
            f"latest=#{latest} | queue={min(old) if old else '-'}..{max(old) if old else '-'} | "
            f"chunk={steps[0]}..{steps[-1]} | stale={len(incoming_actions) - len(fresh)} | "
            f"blended={len(overlap)} | dropped={len(set(old) - new_steps)} | "
            f"max_jump={jump:.1f} ({joint})"
        )
        return original(self, incoming_actions, aggregate_fn)

    rc.RobotClient._aggregate_action_queues = logged

# Run the client from the module we patched above. (runpy.run_module would execute a fresh,
# UNPATCHED copy of robot_client as __main__, silently ignoring the patches.)
from lerobot.async_inference import robot_client as rc  # noqa: E402,F811

rc.register_third_party_plugins()
rc.async_client()  # parses sys.argv, exactly like `python -m lerobot.async_inference.robot_client`
