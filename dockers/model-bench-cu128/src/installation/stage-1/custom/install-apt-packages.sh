#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Core tools
apt-get install -y \
  nano \
  micro \
  mc \
  tmux \
  curl \
  wget \
  git \
  git-lfs \
  unzip

# Python base (Ubuntu 24.04 typically provides Python 3.12)
apt-get install -y \
  python3 \
  python3-pip \
  python3-venv

# GUI / OpenCV runtime deps for cv2.imshow()
apt-get install -y \
  libglib2.0-0 \
  libsm6 \
  libxext6 \
  libxrender1 \
  x11-apps \
  xauth \
  libopencv-dev \
  qimgv

# libGL package name varies across releases (keep compatibility)
if ! apt-get install -y libgl1-mesa-glx; then
  apt-get install -y libgl1
fi

