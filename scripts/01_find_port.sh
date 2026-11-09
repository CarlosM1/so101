#!/usr/bin/env bash
# Step 1 — Which USB serial port is which arm? Run once per arm: it asks you to unplug the USB cable.
source "$(dirname "$0")/lib.sh"
run lerobot-find-port
