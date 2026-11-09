#!/usr/bin/env bash
# Step 11 (PC) — Stream observations to the Spark, execute the action chunks it sends back.
# The leader arm is NOT used. Keep a hand near the follower's power switch the first times.
source "$(dirname "$0")/lib.sh"
# robot_client.py = `python -m lerobot.async_inference.robot_client` + the zmq camera type
# (LeRobot 0.6.1's client doesn't register it). DEBUG_QUEUE=1 logs every action-queue merge:
#   DEBUG_QUEUE=1 scripts/11_robot_client.sh
run python "$PROJECT_ROOT/scripts/robot_client.py" \
  --server_address="${SPARK_HOST}:${POLICY_SERVER_PORT}" \
  --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" --robot.use_degrees="$USE_DEGREES" \
  --robot.cameras="$(cameras_arg)" \
  --task="$TASK" \
  --policy_type="$POLICY_TYPE" \
  --pretrained_name_or_path="$POLICY_PATH" \
  --policy_device="$POLICY_DEVICE" \
  --actions_per_chunk="$ACTIONS_PER_CHUNK" \
  --chunk_size_threshold="$CHUNK_SIZE_THRESHOLD" \
  --aggregate_fn_name="${AGGREGATE_FN:-weighted_average}" \
  --fps="$CAMERA_FPS"
