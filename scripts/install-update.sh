#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
STATE_DIR="${ROOT_DIR}/state"
STATE_HASH_FILE="${STATE_DIR}/deploy-config.sha256"
RENDERED_CONFIG="${STATE_DIR}/config/serverconfig_custom.txt"
RUNTIME_LOG_FILE="${STATE_DIR}/logs/outputlog_server.txt"
TEMPLATE_FILE="${ROOT_DIR}/config/server_config.template.txt"
SERVICE_NAME="holdfast"
HEALTHCHECK_TIMEOUT_SECONDS="${HEALTHCHECK_TIMEOUT_SECONDS:-420}"
HEALTHCHECK_POLL_INTERVAL_SECONDS="${HEALTHCHECK_POLL_INTERVAL_SECONDS:-5}"

log() {
  printf '[install-update] %s\n' "$*"
}

fail() {
  printf '[install-update] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Commande requise absente: $1"
}

generate_secret_b64() {
  openssl rand -base64 24 | tr -d '\n'
}

bootstrap_env_file() {
  if [ -f "${ENV_FILE}" ]; then
    return 0
  fi

  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  tmp_file="${STATE_DIR}/.env.tmp"
  mkdir -p "${STATE_DIR}"
  awk -v cookie="$(generate_secret_b64)" '
    $0 ~ /^SERVER_ADMIN_PASSWORD=change-me-now$/ { print "SERVER_ADMIN_PASSWORD=" cookie; next }
    $0 ~ /^KEYCLOAK_ADMIN_PASSWORD=change-me-now$/ { print "KEYCLOAK_ADMIN_PASSWORD=" cookie; next }
    $0 ~ /^OIDC_COOKIE_SECRET=replace-with-32-byte-base64$/ { print "OIDC_COOKIE_SECRET=" cookie; next }
    { print }
  ' "${ENV_FILE}" > "${tmp_file}"
  mv "${tmp_file}" "${ENV_FILE}"
  log "Fichier .env cree depuis .env.example. Verifiez les secrets et les noms du serveur."
}

load_env() {
  if [ ! -f "${ENV_FILE}" ]; then
    fail "Le fichier .env est absent."
  fi

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|\#*)
        continue
        ;;
      *)
        export "${line}"
        ;;
    esac
  done < "${ENV_FILE}"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_template() {
  local server_password_directive=""

  mkdir -p "${STATE_DIR}" "${STATE_DIR}/config" "${STATE_DIR}/logs/archive" "${STATE_DIR}/holdfast-server"
  cp "${TEMPLATE_FILE}" "${RENDERED_CONFIG}"

  if [ -n "${SERVER_PASSWORD:-}" ]; then
    server_password_directive="server_password ${SERVER_PASSWORD}"
  fi

  for var_name in \
    SERVER_NAME \
    SERVER_PASSWORD \
    SERVER_PASSWORD_DIRECTIVE \
    SERVER_ADMIN_PASSWORD \
    SERVER_DESCRIPTION \
    SERVER_WELCOME_MESSAGE \
    SERVER_INTRO_TITLE \
    SERVER_INTRO_BODY \
    SERVER_REGION \
    NETWORK_BROADCAST_MODE \
    SHOW_SERVERPERFORMANCE_WARNING \
    MAP_ROTATION_START_RANDOMISE \
    POPULATION_LOW_MIN_PLAYERS \
    POPULATION_MEDIUM_MIN_PLAYERS \
    POPULATION_HIGH_MIN_PLAYERS \
    FRIENDLY_FIRE \
    FRIENDLY_FIRE_MELEE_BOUNCE \
    DAMAGE_SPLIT \
    ROUND_TIME_MINUTES \
    ALLOW_MIDROUND_SPAWNING \
    ALLOW_FACTION_SWITCHING \
    ALLOW_SPECTATING \
    MINIMUM_PLAYERS \
    MAXIMUM_PLAYERS \
    FACTION_BALANCING \
    FACTION_BALANCING_DISCREPANCY_AMOUNT \
    WAVE_SPAWN_TIME_SECONDS \
    WAVE_SPAWN_VEHICLE_TIME_SECONDS \
    WAVE_SPAWN_DYNAMIC_TIME_SECONDS \
    SPAWN_IMMUNITY_TIMER \
    SERVER_PORT \
    STEAM_COMMUNICATIONS_PORT \
    STEAM_QUERY_PORT
  do
    if [ "${var_name}" = "SERVER_PASSWORD_DIRECTIVE" ]; then
      value="${server_password_directive}"
    else
      eval "value=\${${var_name}:-}"
    fi
    value="$(escape_sed_replacement "${value}")"
    sed -i.bak "s/{{${var_name}}}/${value}/g" "${RENDERED_CONFIG}"
  done
  rm -f "${RENDERED_CONFIG}.bak"
}

build_compose_files() {
  COMPOSE_FILES="-f ${ROOT_DIR}/compose.yaml"
  if [ "${ENABLE_ADMIN_STACK:-false}" = "true" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${ROOT_DIR}/compose.admin.yaml"
  fi
}

compose_cmd() {
  # shellcheck disable=SC2086
  if docker compose version >/dev/null 2>&1; then
    docker compose ${COMPOSE_FILES} "$@"
    return 0
  fi

  docker-compose ${COMPOSE_FILES} "$@"
}

config_hash() {
  if [ "${ENABLE_ADMIN_STACK:-false}" = "true" ]; then
    shasum \
      "${ROOT_DIR}/compose.yaml" \
      "${ROOT_DIR}/compose.admin.yaml" \
      "${ROOT_DIR}/config/keycloak/realm-export.json" \
      "${ROOT_DIR}/Dockerfile" \
      "${ROOT_DIR}/docker/holdfast-entrypoint.sh" \
      "${ROOT_DIR}/docker/healthcheck.sh" \
      "${ROOT_DIR}/scripts/install-update.sh" \
      "${ROOT_DIR}/config/server_config.template.txt" \
      "${ENV_FILE}" \
      "${RENDERED_CONFIG}" | shasum | awk '{print $1}'
    return 0
  fi

  shasum \
    "${ROOT_DIR}/compose.yaml" \
    "${ROOT_DIR}/Dockerfile" \
    "${ROOT_DIR}/docker/holdfast-entrypoint.sh" \
    "${ROOT_DIR}/docker/healthcheck.sh" \
    "${ROOT_DIR}/scripts/install-update.sh" \
    "${ROOT_DIR}/config/server_config.template.txt" \
    "${ENV_FILE}" \
    "${RENDERED_CONFIG}" | shasum | awk '{print $1}'
}

container_exists() {
  docker ps -a --filter "name=^${COMPOSE_PROJECT_NAME:-holdfast}-server$" --format '{{.Names}}' | grep -q .
}

current_container_id() {
  docker ps -a --filter "name=^${COMPOSE_PROJECT_NAME:-holdfast}-server$" --format '{{.ID}}' | head -n 1
}

current_image_id() {
  local container_id
  container_id="$(current_container_id)"
  if [ -z "${container_id}" ]; then
    return 1
  fi
  docker inspect --format '{{.Image}}' "${container_id}"
}

built_image_id() {
  docker image inspect --format '{{.Id}}' "${HOLDFAST_IMAGE:-holdfast-server-local:latest}"
}

container_name() {
  printf '%s-server\n' "${COMPOSE_PROJECT_NAME:-holdfast}"
}

container_status() {
  docker inspect --format '{{.State.Status}}' "$(container_name)"
}

container_health_status() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$(container_name)"
}

find_runtime_error() {
  if [ ! -f "${RUNTIME_LOG_FILE}" ]; then
    return 1
  fi

  grep -E "Unable to initialize Steam|No Map Rotations are specified|Server directory not found after update|Missing config file|Expected executable not found" "${RUNTIME_LOG_FILE}" | tail -n 1
}

find_runtime_success() {
  if [ ! -f "${RUNTIME_LOG_FILE}" ]; then
    return 1
  fi

  grep -E "Finished loading map|Loading Round ID:" "${RUNTIME_LOG_FILE}" | tail -n 1
}

wait_for_service_health() {
  local deadline status health
  deadline=$(( $(date +%s) + HEALTHCHECK_TIMEOUT_SECONDS ))

  while [ "$(date +%s)" -le "${deadline}" ]; do
    status="$(container_status)"
    health="$(container_health_status)"

    if [ "${status}" != "running" ]; then
      log "Etat conteneur: ${status}"
      return 1
    fi

    if [ "${health}" = "healthy" ]; then
      return 0
    fi

    if [ "${health}" = "unhealthy" ]; then
      return 1
    fi

    sleep "${HEALTHCHECK_POLL_INTERVAL_SECONDS}"
  done

  return 1
}

print_post_deploy_report() {
  local status health success_line error_line
  status="$(container_status)"
  health="$(container_health_status)"
  success_line="$(find_runtime_success || true)"
  error_line="$(find_runtime_error || true)"

  log "Resume de sante:"
  log "  Conteneur: $(container_name)"
  log "  Etat Docker: ${status}"
  log "  Healthcheck: ${health}"

  if [ -n "${success_line}" ]; then
    log "  Signal runtime: ${success_line}"
  fi

  if [ -n "${error_line}" ]; then
    log "  Derniere erreur critique: ${error_line}"
    log "  Logs utiles: docker logs --tail 100 $(container_name)"
    log "  Logs runtime: tail -n 100 ${RUNTIME_LOG_FILE}"
  fi
}

finalize_deploy() {
  if wait_for_service_health; then
    print_post_deploy_report
    return 0
  fi

  print_post_deploy_report
  fail "Le service n'a pas atteint un etat healthy dans le delai imparti."
}

previous_hash() {
  if [ -f "${STATE_HASH_FILE}" ]; then
    cat "${STATE_HASH_FILE}"
  fi
}

write_hash() {
  printf '%s\n' "$1" > "${STATE_HASH_FILE}"
}

run_first_install() {
  log "Premiere installation: build de l'image puis creation du conteneur."
  compose_cmd build "${SERVICE_NAME}"
  compose_cmd up -d "${SERVICE_NAME}"
  finalize_deploy
}

run_update_with_recreate() {
  log "Une recreation est necessaire (image ou configuration modifiee)."
  compose_cmd build "${SERVICE_NAME}"
  compose_cmd up -d "${SERVICE_NAME}"
  finalize_deploy
}

run_update_without_recreate() {
  log "Aucune recreation necessaire. Redemarrage simple pour appliquer l'update SteamCMD."
  compose_cmd stop "${SERVICE_NAME}"
  compose_cmd run --rm --no-deps "${SERVICE_NAME}" update-only
  compose_cmd start "${SERVICE_NAME}"
  finalize_deploy
}

main() {
  require_cmd docker
  require_cmd shasum
  require_cmd openssl

  bootstrap_env_file
  load_env
  render_template
  build_compose_files

  if [ "${ENABLE_ADMIN_STACK:-false}" = "true" ]; then
    log "Façade d'administration activee sur http://${ADMIN_HOSTNAME:-holdfast-admin.local}"
  fi

  if ! container_exists; then
    run_first_install
    write_hash "$(config_hash)"
    exit 0
  fi

  compose_cmd build "${SERVICE_NAME}"

  local_built_image_id="$(built_image_id)"
  local_current_image_id="$(current_image_id || true)"
  local_hash="$(config_hash)"
  local_previous_hash="$(previous_hash)"

  if [ "${local_built_image_id}" != "${local_current_image_id}" ] || [ "${local_hash}" != "${local_previous_hash}" ]; then
    run_update_with_recreate
    write_hash "${local_hash}"
    exit 0
  fi

  run_update_without_recreate
  write_hash "${local_hash}"
}

main "$@"
