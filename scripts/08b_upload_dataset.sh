#!/usr/bin/env bash
# Push the local dataset to the Hub (only needed if you recorded with PUSH_TO_HUB=false).
source "$(dirname "$0")/lib.sh"
run hf upload "$DATASET_REPO_ID" "$HF_LEROBOT_HOME/$DATASET_REPO_ID" --repo-type dataset
