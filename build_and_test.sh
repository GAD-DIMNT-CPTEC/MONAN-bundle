#!/usr/bin/env bash
###############################################################################
# build_and_test.sh
#
# Generic MONAN-bundle build and test driver.
#
# The script is intentionally site-agnostic. Machine-specific values such as
# hostname policy, scheduler, partition and shared Spack-Stack path must be kept
# in config/sites/<site>.env.
###############################################################################

set -Eeuo pipefail

usage() {
  cat <<'EOF'
USAGE
  ./build_and_test.sh [options]

Options
  --site SITE       Site configuration to load from config/sites/<SITE>.env.
                    Default: ${MONAN_SITE:-jaci}
  -v VERSION        mpas-bundle release tag/branch represented by
                    cmake_versions/CMakeLists_<VERSION>.txt. Default: 3.0.0
  -m MODE           local or slurm. Default: site DEFAULT_MODE
  -p ON|OFF         MPAS double precision flag. Default: ON
  --no-cmake        Skip CMake configuration step
  -h, --help        Show this help and exit

Examples
  ./build_and_test.sh --site jaci -v 3.0.2 -m local
  ./build_and_test.sh --site jaci -v 3.0.2 -m slurm -p ON

Notes
  The Spack-Stack environment is expected to be shared by the group/site.
  Do not hard-code personal Spack installations in this script.
EOF
  exit 1
}

log() { printf '[%s] [INFO] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] [ERROR] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }
trap 'log "Unexpected error at line $LINENO"; exit 2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Defaults that do not depend on the site.
SITE="${MONAN_SITE:-jaci}"
VERSION="3.0.0"
MODE=""
PRECISION="ON"
RUN_CMAKE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:?Missing value for --site}"; shift 2 ;;
    -v|--version) VERSION="${2:?Missing value for -v/--version}"; shift 2 ;;
    -m|--mode) MODE="${2:?Missing value for -m/--mode}"; shift 2 ;;
    -p|--precision) PRECISION="${2:?Missing value for -p/--precision}"; shift 2 ;;
    --no-cmake) RUN_CMAKE=false; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done
set --

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/site_config.sh"
load_site_config "$SITE"
validate_site_config

MODE="${MODE:-$DEFAULT_MODE}"
case "$MODE" in
  local|slurm) : ;;
  *) die "Invalid mode: $MODE. Use local or slurm." ;;
esac

case "$PRECISION" in
  ON|OFF) : ;;
  *) die "Invalid precision: $PRECISION. Use ON or OFF." ;;
esac

CMAKE_FILE="$SCRIPT_DIR/cmake_versions/CMakeLists_${VERSION}.txt"
[[ -f "$CMAKE_FILE" ]] || die "CMakeLists for version '$VERSION' not found: $CMAKE_FILE. Run sync_cmakelists.sh first."

JOBSTAMP="$(date +'%Y%m%dT%H%M%S')"
SNAPSHOT_DATE="$(date +'%Y-%m-%d')"
BASE_DIR="$BUILD_ROOT/mpas-bundle-${VERSION}"
BUILD_DIR="$BASE_DIR/build"
LOG_DIR="$BUILD_DIR/logs/$SNAPSHOT_DATE"

mkdir -p "$BASE_DIR" "$BUILD_DIR" "$LOG_DIR"
cp "$CMAKE_FILE" "$BASE_DIR/CMakeLists.txt"

log "Site              : $SITE_ID"
log "Scheduler         : $SCHEDULER"
log "Mode              : $MODE"
log "Shared Spack root : $SPACK_STACK_ROOT"
log "Build directory   : $BUILD_DIR"

activate_spack_stack

if [[ "$RUN_CMAKE" == true ]]; then
  log "Running CMake configuration"
  (
    cd "$BUILD_DIR"
    cmake .. \
      -DMPAS_DOUBLE_PRECISION="$PRECISION" \
      -DMPAS_BUNDLE_NOREMOTE="$MPAS_BUNDLE_NOREMOTE" \
      -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
      -DCMAKE_VERBOSE_MAKEFILE="$CMAKE_VERBOSE_MAKEFILE" \
      2>&1 | tee "$LOG_DIR/cmake_${JOBSTAMP}.log"
  )
else
  log "Skipping CMake configuration step (--no-cmake used)"
fi

log "Dispatching build/tests"
bash "$SCRIPT_DIR/lib/submit_jobs.sh" \
  -s "$SCRIPT_DIR" \
  -b "$BUILD_DIR" \
  -e "$SPACK_STACK_ROOT" \
  -a "$SPACK_ACTIVATE_SCRIPT" \
  -c "$COMPILER_LABEL" \
  -p "$PRECISION" \
  -m "$MODE"

log "Workflow finished/submitted. Logs: $LOG_DIR"
