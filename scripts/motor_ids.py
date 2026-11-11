"""Inspect and repair SO101 motor IDs on an ASSEMBLED arm, without the one-motor-at-a-time setup.

  scan:    python scripts/motor_ids.py scan   <port>
  rename:  python scripts/motor_ids.py rename <port> <old_id> <new_id>

A healthy arm scans as [1, 2, 3, 4, 5, 6]. IDs that look missing usually mean two or more
motors now share one ID (e.g. after running 02_setup_motors.sh with the whole arm connected): they
answer at the same time, the replies collide, and none of them is seen.

`rename` only acts when <old_id> answers cleanly (exactly one motor has it) and <new_id> is free, so it
can never create a duplicate. To free motors that share an ID, disconnect ONE cable in the chain so only
one of them stays on the bus, rename it, reconnect, and move to the next cable (see README §5).
"""

import sys

from lerobot.motors import Motor, MotorNormMode
from lerobot.motors.feetech import FeetechMotorsBus

BAUDRATE = 1_000_000  # the SO101 default
MODEL = "sts3215"


def scan(port: str) -> list[int]:
    # Ping each ID at 1 Mbaud. (LeRobot's scan_port tries 11 baud rates with a broadcast ping; on macOS
    # it returned nothing at all, and one shared ID corrupts the whole broadcast reply.) An ID that
    # several motors share doesn't answer cleanly, so it's reported as missing.
    bus = FeetechMotorsBus(port, {})
    bus._connect(handshake=False)
    bus.set_baudrate(BAUDRATE)
    ids = [i for i in range(1, 11) if bus.ping(i, num_retry=2) is not None]
    bus.port_handler.closePort()
    missing = [i for i in range(1, 7) if i not in ids]
    print(f"answering at {BAUDRATE} baud: {ids}" + (f"   missing: {missing}" if missing else "   (all 6 OK)"))
    return ids


def rename(port: str, old: int, new: int) -> None:
    ids = scan(port)
    if old not in ids:
        sys.exit(f"Refusing: ID {old} doesn't answer at {BAUDRATE} baud (absent, or shared by several motors).")
    if new in ids:
        sys.exit(f"Refusing: ID {new} is already used by another motor on this bus.")
    bus = FeetechMotorsBus(port, {"motor": Motor(new, MODEL, MotorNormMode.RANGE_M100_100)})
    bus.setup_motor("motor", initial_baudrate=BAUDRATE, initial_id=old)  # writes ID, keeps 1 Mbaud
    bus.port_handler.closePort()
    print(f"Renamed motor {old} -> {new}. Bus now:")
    scan(port)


if __name__ == "__main__":
    match sys.argv[1:]:
        case ["scan", port]:
            scan(port)
        case ["rename", port, old, new]:
            rename(port, int(old), int(new))
        case _:
            sys.exit(__doc__)
