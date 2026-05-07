#!/usr/bin/env bash
# shellcheck shell=bash
###############################################################################
# lib/site_config.sh
#
# Shared helpers for loading site-specific MONAN-bundle configuration.
#
# Design principle:
#   - scripts are generic;
#   - machine-specific values live in config/sites/<site>.env;
#   - one institutional/group Spack-Stack is used per site/group.
###############################################################################

site_log() { printf '[%s] [INFO] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
site_die() { printf '[%s] [ERROR] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

resolve_repo_root() {
  local source_dir
  source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${source_dir}/.." && pwd
}

load_site_config() {
  local site_id="${1:-}"

  [[ -n "$site_id" ]] || site_die "Missing site id. Use --site <site> or set MONAN_SITE."

  REPO_ROOT="${REPO_ROOT:-$(resolve_repo_root)}"
  SCRIPT_DIR="$REPO_ROOT"

  local site_file="$REPO_ROOT/config/sites/${site_id}.env"
  [[ -f "$site_file" ]] || site_die "Site configuration not found: $site_file"

  # shellcheck disable=SC1090
  source "$site_file"

  SITE_ID="${SITE_ID:-$site_id}"
  SCHEDULER="${SCHEDULER:-slurm}"
  DEFAULT_MODE="${DEFAULT_MODE:-local}"
  COMPILER_LABEL="${COMPILER_LABEL:-gnu}"
  BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/builds}"
  CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
  MPAS_BUNDLE_NOREMOTE="${MPAS_BUNDLE_NOREMOTE:-ON}"
  CMAKE_VERBOSE_MAKEFILE="${CMAKE_VERBOSE_MAKEFILE:-ON}"

  [[ -n "${SPACK_STACK_ROOT:-}" ]] || site_die "SPACK_STACK_ROOT is not defined in $site_file"
  SPACK_ACTIVATE_SCRIPT="${SPACK_ACTIVATE_SCRIPT:-${SPACK_STACK_ROOT}/start_spack_bundle.sh}"

  export REPO_ROOT SCRIPT_DIR SITE_ID SCHEDULER DEFAULT_MODE COMPILER_LABEL BUILD_ROOT
  export SPACK_STACK_ROOT SPACK_ACTIVATE_SCRIPT CMAKE_BUILD_TYPE MPAS_BUNDLE_NOREMOTE CMAKE_VERBOSE_MAKEFILE
}

validate_site_config() {
  [[ -d "$SPACK_STACK_ROOT" ]] || site_die "SPACK_STACK_ROOT not found: $SPACK_STACK_ROOT"
  [[ -f "$SPACK_ACTIVATE_SCRIPT" ]] || site_die "Spack activation script not found: $SPACK_ACTIVATE_SCRIPT"

  if [[ "${HOST_CHECK_ENABLED:-0}" == "1" ]]; then
    local host_fqdn host_short
    host_fqdn="$(hostname -f 2>/dev/null || hostname)"
    host_short="$(hostname)"
    if [[ ! "$host_fqdn" =~ ${SITE_HOST_REGEX:-.*} && ! "$host_short" =~ ${SITE_HOST_REGEX:-.*} ]]; then
      site_die "This site config is not valid for this host. site=$SITE_ID host=$host_fqdn regex=${SITE_HOST_REGEX:-unset}"
    fi
  fi

  case "$SCHEDULER" in
    slurm) command -v sbatch >/dev/null 2>&1 || site_log "sbatch not found now; local mode can still be used." ;;
    none) : ;;
    *) site_die "Unsupported scheduler: $SCHEDULER" ;;
  esac
}

activate_spack_stack() {
  site_log "Activating shared Spack-Stack: $SPACK_ACTIVATE_SCRIPT"
  # shellcheck disable=SC1090
  source "$SPACK_ACTIVATE_SCRIPT"
}
