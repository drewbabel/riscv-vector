#!/bin/bash
set -e

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

info_print()    { echo -e "${BLUE}$1${NC}"; }
error_print()   { echo -e "${RED}ERROR: $1${NC}" >&2; }
success_print() { echo -e "${GREEN}$1${NC}"; }

cd "$(cd "$(dirname "$0")" && pwd)"

OSS_TOOLS="iverilog yosys verilator sby"
OSS_HINT="Install the OSS CAD Suite from https://github.com/YosysHQ/oss-cad-suite-build and put its bin on PATH"

check_tool() {
    local tool="$1"
    local hint="$2"
    if ! command -v "$tool" &> /dev/null; then
        error_print "$tool not found"
        error_print "$hint"
        return 1
    fi
    info_print "Found $tool"
}

check_requirements() {
    local missing=0
    for tool in $OSS_TOOLS; do
        check_tool "$tool" "$OSS_HINT" || missing=1
    done
    check_tool sv2v "Install with: brew install sv2v" || missing=1
    check_tool riscv64-elf-gcc "Install with: brew tap riscv-software-src/riscv && brew install riscv-tools" || missing=1
    check_tool verible-verilog-format "Install with: brew install verible" || missing=1
    check_tool python3 "Install python 3.10 or newer" || missing=1
    return $missing
}

info_print "Checking requirements"
check_requirements || exit 1

info_print "Installing git hooks"
git config core.hooksPath .githooks
chmod +x .githooks/*

if [ -f .vscode/settings.json ]; then
    info_print "Editor settings live in .vscode and .editorconfig"
    info_print "Accept the extension recommendations when VS Code prompts"
fi

success_print "riscv-vector setup complete"
