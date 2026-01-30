#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Core tools
apt-get install -y \
  ca-certificates \
  curl \
  wget \
  git \
  git-lfs \
  openssh-client \
  unzip \
  zip \
  tmux \
  nano \
  less \
  jq

# Build essentials
apt-get install -y \
  build-essential \
  pkg-config

# Python base (Ubuntu 24.04 typically provides Python 3.12)
apt-get install -y \
  python3 \
  python3-pip \
  python3-venv

# Useful CLI search tools (fd is packaged as `fd-find` on Ubuntu)
apt-get install -y \
  ripgrep \
  fd-find

