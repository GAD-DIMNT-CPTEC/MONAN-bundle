#!/usr/bin/env bash
###############################################################################
# lib/build_local.sh
#
# Lightweight local compilation helper for MONAN-bundle/MPAS-bundle.
###############################################################################

set -Eeuo pipefail

log() { printf '[%s] [INFO] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] [ERROR] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }
trap 'log "Unexpected error at line $LINENO"; exit 2' ERR

BUILD_DIR="${1:?BUILD_DIR missing}"
SPACK_DIR="${2:?SPACK_DIR missing}"
SPACK_ACTIVATE_SCRIPT="${3:?SPACK_ACTIVATE_SCRIPT missing}"
COMPILER="${4:-gnu}"
PRECISION="${5:-ON}"
set --

[[ -d "$BUILD_DIR" ]] || die "BUILD_DIR not found: $BUILD_DIR"
[[ -d "$SPACK_DIR" ]] || die "SPACK_DIR not found: $SPACK_DIR"
[[ -f "$SPACK_ACTIVATE_SCRIPT" ]] || die "SPACK_ACTIVATE_SCRIPT not found: $SPACK_ACTIVATE_SCRIPT"

log "Local build started"
log "Compiler label : $COMPILER"
log "Precision      : $PRECISION"
log "Build dir      : $BUILD_DIR"
log "Spack root     : $SPACK_DIR"

# shellcheck disable=SC1090
source "$SPACK_ACTIVATE_SCRIPT"

TOTAL_CPUS=$(nproc)
MAKE_J=$(( TOTAL_CPUS / 10 ))
[[ "$MAKE_J" -lt 1 ]] && MAKE_J=1
log "Limiting local build to $MAKE_J thread(s) out of $TOTAL_CPUS CPUs"

cd "$BUILD_DIR"
log "Running make -j$MAKE_J with low CPU/I/O priority"
nice -n 19 ionice -c3 make -j"$MAKE_J"

log "Compilation completed successfully"
