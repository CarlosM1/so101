#!/usr/bin/env bash
# Step 9 (SPARK) — Train a policy on the recorded dataset (pulled from the Hub automatically).
#   usage: scripts/09_train.sh            start
#          scripts/09_train.sh --resume   continue from the last checkpoint
#          scripts/09_train.sh --dataset.image_transforms.enable=true   extra lerobot-train options are passed on
source "$(dirname "$0")/lib.sh"
OUT="$PROJECT_ROOT/outputs/train/$POLICY_NAME"
if [[ "${1:-}" == "--resume" ]]; then
  run lerobot-train --config_path="$OUT/checkpoints/last/pretrained_model/train_config.json" --resume=true
  exit
fi
COMMON=(
  --dataset.repo_id="$DATASET_REPO_ID"
  --output_dir="$OUT" --job_name="$POLICY_NAME"
  --policy.device=cuda
  --policy.repo_id="$HF_USER/$POLICY_NAME" --policy.push_to_hub=true   # explicit: a --policy.path config may say false
  --steps="$TRAIN_STEPS" --batch_size="$BATCH_SIZE"
  --save_freq=5000
  "$@"
)
case "$POLICY_TYPE" in
  smolvla) run lerobot-train --policy.path=lerobot/smolvla_base "${COMMON[@]}" ;;  # fine-tune the VLA
  act)
    if [[ -n "${BASE_POLICY:-}" ]]; then
      # Fine-tune: start from BASE_POLICY's weights; normalisation stats come from YOUR dataset.
      run lerobot-train --policy.path="$BASE_POLICY" "${COMMON[@]}"
    else
      run lerobot-train --policy.type=act "${COMMON[@]}"                          # train from scratch
    fi ;;
  *) echo "POLICY_TYPE must be act or smolvla" >&2; exit 2 ;;
esac
