#!/bin/bash

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info_print()    { echo -e "${BLUE}$1${NC}"; }
error_print()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
warn_print()    { echo -e "${YELLOW}WARNING: $1${NC}"; }
success_print() { echo -e "${GREEN}$1${NC}"; }

cd "$(cd "$(dirname "$0")" && pwd)" || exit 1

VERIBLE_HINT="brew install verible, or take a release binary from https://github.com/chipsalliance/verible/releases"
REQUIRED_HINT_iverilog="Install the OSS CAD Suite from https://github.com/YosysHQ/oss-cad-suite-build and put its bin on PATH"

check_tool() {
    local tool="$1"
    local hint="$2"
    if ! command -v "$tool" > /dev/null 2>&1; then
        error_print "$tool not found"
        error_print "$hint"
        return 1
    fi
    info_print "Found $tool"
}

check_required() {
    local missing=0
    check_tool iverilog "$REQUIRED_HINT_iverilog" || missing=1
    check_tool vvp "$REQUIRED_HINT_iverilog" || missing=1
    check_tool verilator "$REQUIRED_HINT_iverilog" || missing=1
    check_tool verible-verilog-format "$VERIBLE_HINT" || missing=1
    check_tool verible-verilog-ls "$VERIBLE_HINT" || missing=1
    return $missing
}

report_optional() {
    local absent=""
    for tool in surfer yosys sby sv2v riscv64-elf-gcc python3; do
        command -v "$tool" > /dev/null 2>&1 || absent="$absent $tool"
    done
    if [ -n "$absent" ]; then
        info_print "Not installed, needed only for waveforms, synthesis, formal and program builds:$absent"
    fi
}

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error_print "Not a git repository"
    error_print "Run this from inside your clone of riscv-vector"
    exit 1
fi

info_print "Installing git hooks"
git config core.hooksPath .githooks || exit 1
chmod +x .githooks/* 2>/dev/null

info_print "Editor settings live in .vscode and .editorconfig"
info_print "Accept the extension recommendations when VS Code prompts"

info_print "Checking build tools"
report_optional
if check_required; then
    success_print "riscv-vector setup complete"
else
    warn_print "Git hooks and editor settings are installed"
    warn_print "Install the tools listed above before building"
    exit 1
fi
