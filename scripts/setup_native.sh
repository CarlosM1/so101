#!/usr/bin/env bash
# PC setup on macOS (Linux PCs use Docker, README §4.2): same packages as docker/pc.Dockerfile,
# installed in ./.venv. On macOS the default PyPI torch includes Apple MPS support.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v uv >/dev/null; then
  echo "uv not found. Install it with:  curl -LsSf https://astral.sh/uv/install.sh | sh   (or: brew install uv)" >&2
  exit 1
fi
command -v ffmpeg >/dev/null || echo "WARNING: ffmpeg not found (needed for dataset videos). macOS: brew install ffmpeg" >&2
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r requirements/pc.txt
[[ -f .env ]] || { cp .env.example .env; echo "Created .env — edit it now."; }
# torchcodec supports FFmpeg 4–8 only; Homebrew's default ffmpeg may be newer (9+).
# Point the loader at the keg-only ffmpeg@8 (brew install ffmpeg@8). Keep in sync with lib.sh.
if [[ "$(uname)" == "Darwin" ]]; then
  [[ -d /opt/homebrew/opt/ffmpeg@8/lib ]] || echo "WARNING: ffmpeg@8 not found; torchcodec will fail. Run: brew install ffmpeg@8" >&2
  export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/ffmpeg@8/lib"
fi
.venv/bin/lerobot-info
echo
echo "Done. Scripts in scripts/ activate .venv automatically. Next: scripts/00_check.sh"
