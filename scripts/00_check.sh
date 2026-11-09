#!/usr/bin/env bash
# Sanity check: config, LeRobot version, torch device. Run on the PC and on the Spark.
source "$(dirname "$0")/lib.sh"
echo "PROJECT_ROOT     = $PROJECT_ROOT"
echo "HF_LEROBOT_HOME  = $HF_LEROBOT_HOME"
echo "DATASET_REPO_ID  = $DATASET_REPO_ID"
echo "cameras          = $(cameras_arg)"
python - <<'PY'
import torch, lerobot
print("lerobot", lerobot.__version__, "| torch", torch.__version__)
if torch.cuda.is_available():
    print("CUDA:", torch.cuda.get_device_name(0), "capability", torch.cuda.get_device_capability(0))
    x = torch.randn(2048, 2048, device="cuda"); torch.cuda.synchronize(); print("GPU matmul ok, norm =", float((x @ x).norm()))
elif torch.backends.mps.is_available():
    print("Apple MPS available")
else:
    print("CPU only")
PY
