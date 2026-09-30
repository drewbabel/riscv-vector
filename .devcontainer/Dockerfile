FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG OSS_CAD_SUITE=2026-07-24
ARG VERIBLE_VERSION=v0.0-4283-ga1b0580b

RUN apt-get update && apt-get install -y --no-install-recommends \
        make python3 \
    && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in amd64) cad_arch=x64 ;; arm64) cad_arch=arm64 ;; esac \
    && url="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_SUITE}/oss-cad-suite-linux-${cad_arch}-$(echo "$OSS_CAD_SUITE" | tr -d -).tgz" \
    && mkdir -p /opt/oss-cad-suite \
    && curl -fsSL "$url" | tar -xz -C /opt/oss-cad-suite --strip-components=1

ENV PATH="/opt/oss-cad-suite/bin:${PATH}"

RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in amd64) verible_arch=x86_64 ;; arm64) verible_arch=arm64 ;; esac \
    && url="https://github.com/chipsalliance/verible/releases/download/${VERIBLE_VERSION}/verible-${VERIBLE_VERSION}-linux-static-${verible_arch}.tar.gz" \
    && curl -fsSL "$url" -o /tmp/verible.tar.gz \
    && tar -xzf /tmp/verible.tar.gz -C /tmp \
    && cp /tmp/verible-*/bin/verible-verilog-format /tmp/verible-*/bin/verible-verilog-ls /usr/local/bin/ \
    && rm -rf /tmp/verible*
