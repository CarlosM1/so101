# =============================================================================
# Spark image: training + policy server.  NVIDIA DGX Spark (aarch64, GB10, CUDA 13).
# torch wheels bundle the CUDA user-space libraries; the host only needs the
# NVIDIA driver + NVIDIA Container Toolkit (both preinstalled on DGX OS).
# =============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    IN_DOCKER=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg git ca-certificates build-essential libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.9.5 /uv /uvx /bin/
# uv downloads a standalone CPython 3.12 (LeRobot requires >=3.12).
RUN uv venv /opt/venv --python 3.12

# Layer 1: CUDA 13 torch + matching torchcodec for aarch64 (Blackwell GB10). Cached across rebuilds.
RUN uv pip install --index-url https://download.pytorch.org/whl/cu130 \
        "torch==2.11.*" "torchvision==0.26.*" "torchcodec==0.11.*" \
    && uv pip install "nvidia-npp==13.0.*"
# torchcodec's CUDA build needs NVIDIA NPP (libnppicc.so.13), which torch does not ship;
# the loader must be able to find the pip-installed CUDA 13 libraries.
ENV LD_LIBRARY_PATH=/opt/venv/lib/python3.12/site-packages/nvidia/cu13/lib
# Layer 2: LeRobot (training + SmolVLA + gRPC server). torch already satisfied -> kept.
COPY requirements/spark.txt /tmp/requirements.txt
RUN uv pip install -r /tmp/requirements.txt && lerobot-info

WORKDIR /workspace
CMD ["bash"]
