# shellcheck shell=bash
# Shared helpers, sourced by every script. Works natively (macOS/Linux) and in Docker.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
  echo "ERROR: $PROJECT_ROOT/.env not found. Run: cp .env.example .env  (then edit it)" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source "$PROJECT_ROOT/.env"
set +a

# Containers have no screen for the rerun viewer and no speech synthesiser.
if [[ -n "${IN_DOCKER:-}" ]]; then
  DISPLAY_DATA="${DOCKER_DISPLAY_DATA:-false}"
fi

# Use the project venv when running natively (no-op inside Docker, which has /opt/venv on PATH).
if [[ -z "${IN_DOCKER:-}" && -f "$PROJECT_ROOT/.venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.venv/bin/activate"
fi

# Relative storage paths are relative to the project root (-> /workspace/... in containers).
abspath() { [[ "$1" = /* ]] && echo "$1" || echo "$PROJECT_ROOT/$1"; }
export HF_HOME="$(abspath "${HF_HOME:-data/huggingface}")"
export HF_LEROBOT_HOME="$(abspath "${HF_LEROBOT_HOME:-data/huggingface/lerobot}")"
# An empty HF_TOKEN would hide a token saved by `hf auth login`, so drop it.
if [[ -z "${HF_TOKEN:-}" ]]; then unset HF_TOKEN; fi
mkdir -p "$HF_LEROBOT_HOME"

DATASET_REPO_ID="${HF_USER}/${DATASET_NAME}"
export DATASET_REPO_ID

# macOS: torchcodec supports FFmpeg 4–8 only, and Homebrew's default ffmpeg is 9+.
# Point the loader at the keg-only ffmpeg@8 (brew install ffmpeg@8). Keep in sync with setup_native.sh.
if [[ "$(uname)" == "Darwin" ]]; then
  export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/ffmpeg@8/lib"
fi


# Camera names become the policy's input keys (observation.images.<name>). They must match
# what the policy you run expects. Defaults suit SmolVLA (camera1/camera2).
CAM1_NAME="${CAM1_NAME:-camera1}"
CAM2_NAME="${CAM2_NAME:-camera2}"
export CAM1_NAME CAM2_NAME

# Joint units for the arms: true = degrees (LeRobot 0.6.1 default), false = -100..100 range.
# Must match the units the policy/dataset was recorded with.
USE_DEGREES="${USE_DEGREES:-true}"
export USE_DEGREES

# Build the --robot.cameras value. The SAME names, resolution and fps must be used for
# recording and inference, otherwise the policy sees different input features.
cameras_arg() {
  local w="${CAMERA_WIDTH}" h="${CAMERA_HEIGHT}" f="${CAMERA_FPS}"
  local n1="${CAM1_NAME}" n2="${CAM2_NAME}"
  if [[ "${CAMERA_MODE:-zmq}" == "zmq" ]]; then
    local host="${CAMERA_SERVER_HOST}"
    echo "{ ${n1}: {type: zmq, server_address: ${host}, port: ${CAM1_PORT}, camera_name: ${n1}, width: ${w}, height: ${h}, fps: ${f}}, ${n2}: {type: zmq, server_address: ${host}, port: ${CAM2_PORT}, camera_name: ${n2}, width: ${w}, height: ${h}, fps: ${f}}}"
  else
    echo "{ ${n1}: {type: opencv, index_or_path: ${CAM1_DEVICE}, width: ${w}, height: ${h}, fps: ${f}}, ${n2}: {type: opencv, index_or_path: ${CAM2_DEVICE}, width: ${w}, height: ${h}, fps: ${f}}}"
  fi
}

# Print a command, then run it — so you learn the real LeRobot CLI underneath.
run() {
  printf '\n\033[1;36m$'
  printf ' %q' "$@"
  printf '\033[0m\n\n'
  "$@"
}
