# Base image
FROM nvidia/cuda:12.6.0-cudnn-runtime-ubuntu22.04 AS base

# Set noninteractive mode for apt
ENV DEBIAN_FRONTEND=noninteractive
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ENV PIP_INDEX_URL=${PIP_INDEX_URL}

# Update and install dependencies
RUN apt-get -o Acquire::AllowInsecureRepositories=true update && \
    apt-get install -y --no-install-recommends \
        libxcb-xfixes0 \
        libxcb-shape0 \
        python3 \
        python3-venv \
        python3-pip \
        curl \
        git || true && \
    apt-get install -y --no-install-recommends ffmpeg || true && \
    apt --fix-broken install -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy requirements and install common dependencies
COPY requirements.txt /tmp/

# Install pip + dependencies
RUN python3 -m pip install --upgrade pip && \
    pip install --root-user-action=ignore --no-cache-dir -r /tmp/requirements.txt && \
    pip install --root-user-action=ignore --no-cache-dir funasr modelscope huggingface_hub pywhispercpp torch torchaudio edge-tts azure-cognitiveservices-speech py3-tts

# MeloTTS installation
WORKDIR /opt/MeloTTS
RUN git config --global http.version HTTP/1.1 && \
    git config --global http.postBuffer 524288000 && \
    git clone https://gitclone.com/github.com/myshell-ai/MeloTTS.git /opt/MeloTTS && \
    pip install --root-user-action=ignore --no-cache-dir -e .
RUN python3 - <<PY
import shutil
from pathlib import Path
import unidic
import unidic_lite
src = Path(unidic_lite.__file__).parent / 'dicdir'
dst = Path(unidic.__file__).parent / 'dicdir'
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)
PY
RUN HF_ENDPOINT=https://hf-mirror.com python3 melo/init_downloads.py
# Whisper variant
FROM base AS whisper
ARG INSTALL_ORIGINAL_WHISPER=false
RUN if [ "$INSTALL_WHISPER" = "true" ]; then \
        pip install --root-user-action=ignore --no-cache-dir openai-whisper; \
    fi

# Bark variant
FROM whisper AS bark
ARG INSTALL_BARK=false
RUN if [ "$INSTALL_BARK" = "true" ]; then \
        pip install --root-user-action=ignore --no-cache-dir git+https://github.com/suno-ai/bark.git; \
    fi

# Final image
FROM bark AS final

# Copy application code to the container
COPY . /app

# Set working directory
WORKDIR /app

# Expose port 12393 (the new default port)
EXPOSE 12393

CMD ["python3", "server.py"]
