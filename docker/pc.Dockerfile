# =============================================================================
# PC image: arms + cameras + recording + robot client.  LINUX HOSTS ONLY.
# (Docker Desktop on macOS cannot pass USB serial ports or cameras into a
#  container. On a Mac, run the same scripts natively: scripts/setup_native.sh)
# No policy runs here: the GPU work happens on the Spark.
# =============================================================================
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    IN_DOCKER=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

# ffmpeg     -> video encode/decode for datasets
# v4l-utils  -> `v4l2-ctl --list-devices` to inspect cameras
# build-essential + linux-libc-dev -> builds `evdev` (pynput's Linux keyboard backend)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg v4l-utils git ca-certificates build-essential linux-libc-dev libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /uvx /bin/
RUN uv venv /opt/venv --python /usr/local/bin/python3.12

# Layer 1: torch + torchcodec, installed together from ONE PyTorch index so they match.
#   x86_64 -> CPU wheels (small; no GPU work happens on the PC).
#   arm64  -> CUDA 13 wheels: PyTorch publishes no CPU torchcodec for Linux aarch64, and PyPI's
#             is a CUDA build that fails to load next to CPU torch. CUDA torch runs fine on CPU.
ARG TARGETARCH
#   The CUDA torchcodec also needs NVIDIA NPP (libnppicc.so.13), which torch does not ship.
RUN if [ "$TARGETARCH" = "arm64" ]; then IDX=cu130; else IDX=cpu; fi \
    && uv pip install --index-url "https://download.pytorch.org/whl/$IDX" \
        "torch==2.11.*" "torchvision==0.26.*" "torchcodec==0.11.*" \
    && if [ "$TARGETARCH" = "arm64" ]; then uv pip install "nvidia-npp==13.0.*"; fi
# Where the pip-installed CUDA 13 libraries live (harmless when absent on x86_64).
ENV LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib
# Layer 2: LeRobot + extras. torch is already satisfied, so uv keeps the CPU build.
COPY requirements/pc.txt /tmp/requirements.txt
RUN uv pip install -r /tmp/requirements.txt && lerobot-info

WORKDIR /workspace
CMD ["bash"]
