#!/usr/bin/env bash
set -euo pipefail

STEAM_APP_ID="${STEAM_APP_ID:-1424230}"
STEAMCMDDIR="${STEAMCMDDIR:-/opt/steamcmd}"
HOLDFAST_INSTALL_DIR="${HOLDFAST_INSTALL_DIR:-/opt/holdfast/server}"
HOLDFAST_CONFIG_PATH="${HOLDFAST_CONFIG_PATH:-/data/config/serverconfig_custom.txt}"
STEAMCMD_VALIDATE="${STEAMCMD_VALIDATE:-false}"
SERVER_PORT="${SERVER_PORT:-20100}"

log() {
  printf '[holdfast-entrypoint] %s\n' "$*"
}

run_steamcmd_update() {
  local validate_arg=""
  if [ "${STEAMCMD_VALIDATE}" = "true" ]; then
    validate_arg="validate"
  fi

  mkdir -p "${HOLDFAST_INSTALL_DIR}" /data/logs /data/runtime
  log "Updating dedicated server files with SteamCMD (app ${STEAM_APP_ID})"
  "${STEAMCMDDIR}/steamcmd.sh" \
    +force_install_dir "${HOLDFAST_INSTALL_DIR}" \
    +login anonymous \
    +app_update "${STEAM_APP_ID}" ${validate_arg} \
    +quit
}

start_server() {
  if [ ! -f "${HOLDFAST_CONFIG_PATH}" ]; then
    log "Missing config file: ${HOLDFAST_CONFIG_PATH}"
    exit 1
  fi

  if [ ! -d "${HOLDFAST_INSTALL_DIR}" ]; then
    log "Server directory not found after update: ${HOLDFAST_INSTALL_DIR}"
    exit 1
  fi

  cd "${HOLDFAST_INSTALL_DIR}"
  if [ ! -x "./Holdfast NaW" ]; then
    log "Expected executable not found: ${HOLDFAST_INSTALL_DIR}/Holdfast NaW"
    find "${HOLDFAST_INSTALL_DIR}" -maxdepth 2 -type f | sed 's/^/[holdfast-entrypoint] found file: /'
    exit 1
  fi

  mkdir -p /data/logs/archive
  log "Starting Holdfast dedicated server"
  exec ./Holdfast\ NaW \
    -startserver \
    -batchmode \
    -nographics \
    -screen-width 640 \
    -screen-height 480 \
    -screen-quality Fastest \
    -framerate "${FRAMERATE:-120}" \
    --serverheadless \
    -serverConfigFilePath "${HOLDFAST_CONFIG_PATH}" \
    -logFile "/data/logs/outputlog_server.txt" \
    -logArchivesDirectory "/data/logs/archive/" \
    -p "${SERVER_PORT}"
}

main() {
  local mode="${1:-serve}"

  case "${mode}" in
    serve)
      run_steamcmd_update
      start_server
      ;;
    update-only)
      run_steamcmd_update
      ;;
    *)
      exec "$@"
      ;;
  esac
}

main "$@"
