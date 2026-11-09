#!/usr/bin/env bash
# Step 4 — List OpenCV cameras and save a test image of each to outputs/captured_images.
# Put the indices you want into CAM1_DEVICE (front/top) and CAM2_DEVICE (wrist) in .env.
# Stop the camera server first: a camera can only be opened by one process.
source "$(dirname "$0")/lib.sh"
cd "$PROJECT_ROOT"
run lerobot-find-cameras opencv
