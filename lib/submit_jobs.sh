#!/usr/bin/env bash
###############################################################################
# lib/submit_jobs.sh
#
# Unified launcher for MONAN-bundle build and test workflows.
# Scheduler-specific defaults are read from the active site configuration via
# environment variables exported by build_and_test.sh.
###############################################################################

set -Eeuo pipefail

usage() {
  cat <<'EOF'
USAGE
  submit_jobs.sh -s <SCRIPT_DIR> -b <BUILD_DIR> -e <SPACK_DIR> -a <ACTIVATE_SCRIPT> [options]

Required
  -s SCRIPT_DIR       Repository/script root
  -b BUILD_DIR        CMake build directory
  -e SPACK_DIR        Shared Spack-Stack root
  -a ACTIVATE_SCRIPT  Spack-Stack activation script

Optional
  -c COMPILER         Toolchain label. Default: gnu
  -p ON|OFF           Precision flag. Default: ON
  -m MODE             local or slurm. Default: slurm
  -h                  Show help
EOF
  exit 1
}

log() { printf '[%s] [INFO] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] [ERROR] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }
trap 'log "Unexpected error at line $LINENO"; exit 2' ERR

COMPILER="${COMPILER_LABEL:-gnu}"
PRECISION="ON"
MODE="slurm"

while getopts ":s:b:e:a:c:p:m:h" opt; do
  case "$opt" in
    s) SCRIPT_DIR="$OPTARG" ;;
    b) BUILD_DIR="$OPTARG" ;;
    e) SPACK_DIR="$OPTARG" ;;
    a) SPACK_ACTIVATE_SCRIPT="$OPTARG" ;;
    c) COMPILER="$OPTARG" ;;
    p) PRECISION="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    h|*) usage ;;
  esac
done
set --

[[ -z "${SCRIPT_DIR:-}" || -z "${BUILD_DIR:-}" || -z "${SPACK_DIR:-}" || -z "${SPACK_ACTIVATE_SCRIPT:-}" ]] && usage
[[ -d "$SCRIPT_DIR" ]] || die "SCRIPT_DIR not found: $SCRIPT_DIR"
[[ -d "$BUILD_DIR" ]] || die "BUILD_DIR not found: $BUILD_DIR"
[[ -d "$SPACK_DIR" ]] || die "SPACK_DIR not found: $SPACK_DIR"
[[ -f "$SPACK_ACTIVATE_SCRIPT" ]] || die "SPACK_ACTIVATE_SCRIPT not found: $SPACK_ACTIVATE_SCRIPT"

case "$MODE" in
  local|slurm) : ;;
  *) die "Invalid mode: $MODE. Use local or slurm." ;;
esac

TODAY="$(date +%F)"
LOG_DIR="$BUILD_DIR/logs/$TODAY"
mkdir -p "$LOG_DIR"

if [[ "$MODE" == "local" ]]; then
  [[ -x "$SCRIPT_DIR/lib/build_local.sh" ]] || die "build_local.sh not executable."
  log "Running local build"
  "$SCRIPT_DIR/lib/build_local.sh" "$BUILD_DIR" "$SPACK_DIR" "$SPACK_ACTIVATE_SCRIPT" "$COMPILER" "$PRECISION"
  log "Running local ctest"
  (
    cd "$BUILD_DIR"
    ctest --output-on-failure 2>&1 | tee "$LOG_DIR/ctest_local.log"
  )
  log "Local ctest log: $LOG_DIR/ctest_local.log"
  exit 0
fi

command -v sbatch >/dev/null 2>&1 || die "sbatch not found; cannot use slurm mode."
[[ -d "$SCRIPT_DIR/jobs" ]] || die "jobs/ directory missing in $SCRIPT_DIR"

SBATCH_COMMON=(
  --partition="${SLURM_PARTITION:-PESQ1}"
)

log "Submitting SLURM build job"
BUILD_SBATCH_ARGS=(
  --parsable
  --job-name="${SLURM_BUILD_JOB_NAME:-monan_build}"
  --nodes="${SLURM_BUILD_NODES:-1}"
  --time="${SLURM_BUILD_TIME:-02:00:00}"
  --output="$LOG_DIR/build_%j.out"
  --error="$LOG_DIR/build_%j.err"
)

if [[ "${SLURM_BUILD_EXCLUSIVE:-0}" == "1" ]]; then
  BUILD_SBATCH_ARGS+=(--exclusive)
fi

BUILD_JOB_ID=$(sbatch "${SBATCH_COMMON[@]}" "${BUILD_SBATCH_ARGS[@]}" \
  "$SCRIPT_DIR/jobs/build_job.slurm" \
  "$BUILD_DIR" "$SPACK_DIR" "$SPACK_ACTIVATE_SCRIPT" "$COMPILER" "$PRECISION")

[[ -n "$BUILD_JOB_ID" ]] || die "sbatch returned an empty build job id."
log "Build job id: $BUILD_JOB_ID"

if command -v sacct >/dev/null 2>&1; then
  sleep 3
  STATE=$(sacct -j "$BUILD_JOB_ID" --format=State%20 --noheader | head -n1 | awk '{print $1}')
  if [[ "$STATE" == FAILED* || "$STATE" == CANCELLED* ]]; then
    die "Build job already $STATE"
  fi
else
  log "sacct not found; skipping immediate job-state check."
fi

log "Submitting SLURM ctest job after successful build"
CTEST_JOB_ID=$(sbatch "${SBATCH_COMMON[@]}" \
  --dependency="afterok:$BUILD_JOB_ID" \
  --job-name="${SLURM_CTEST_JOB_NAME:-monan_ctest}" \
  --nodes="${SLURM_CTEST_NODES:-1}" \
  --ntasks="${SLURM_CTEST_NTASKS:-32}" \
  --time="${SLURM_CTEST_TIME:-01:00:00}" \
  --output="$LOG_DIR/ctest_%j.out" \
  --error="$LOG_DIR/ctest_%j.err" \
  "$SCRIPT_DIR/jobs/ctest_job.slurm" \
  "$BUILD_DIR" "$SPACK_DIR" "$SPACK_ACTIVATE_SCRIPT")

[[ -n "$CTEST_JOB_ID" ]] || die "Failed to submit ctest job."
log "CTest job id: $CTEST_JOB_ID; dependency: afterok:$BUILD_JOB_ID"
log "Track with: squeue -j $BUILD_JOB_ID,$CTEST_JOB_ID"
