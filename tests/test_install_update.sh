#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
TEST_BIN="${TEST_TMP}/bin"
LOG_FILE="${TEST_TMP}/docker.log"
STATE_FILE="${TEST_TMP}/scenario.env"

cleanup() {
  rm -rf "${TEST_TMP}"
}
trap cleanup EXIT

mkdir -p "${TEST_BIN}"

cat > "${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${TEST_DOCKER_LOG}"
STATE_FILE="${TEST_SCENARIO_FILE}"

read_state() {
  if [ -f "${STATE_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${STATE_FILE}"
  fi
}

write_state() {
  cat > "${STATE_FILE}" <<STATE
CONTAINER_EXISTS=${CONTAINER_EXISTS}
CURRENT_IMAGE_ID=${CURRENT_IMAGE_ID}
BUILT_IMAGE_ID=${BUILT_IMAGE_ID}
STATE
}

read_state
printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "${1:-}" = "ps" ]; then
  if [ "${CONTAINER_EXISTS:-false}" = "true" ]; then
    if [ "${2:-}" = "-a" ]; then
      printf 'holdfast-server\n'
    fi
  fi
  exit 0
fi

if [ "${1:-}" = "inspect" ]; then
  printf '%s\n' "${CURRENT_IMAGE_ID:-sha256:old}"
  exit 0
fi

if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
  printf '%s\n' "${BUILT_IMAGE_ID:-sha256:new}"
  exit 0
fi

if [ "${1:-}" = "compose" ]; then
  shift
  while [ "${1:-}" = "-f" ]; do
    shift 2
  done

  case "${1:-}" in
    build)
      BUILT_IMAGE_ID="${BUILT_IMAGE_ID:-sha256:new}"
      write_state
      ;;
    up)
      CONTAINER_EXISTS=true
      CURRENT_IMAGE_ID="${BUILT_IMAGE_ID:-sha256:new}"
      write_state
      ;;
    stop|start|run)
      write_state
      ;;
  esac
  exit 0
fi

exit 0
EOF

cat > "${TEST_BIN}/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1111111111111111111111111111111111111111111111111111111111111111  mocked\n'
EOF

cat > "${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-s" ]; then
  printf 'Linux\n'
else
  printf 'x86_64\n'
fi
EOF

chmod +x "${TEST_BIN}/docker" "${TEST_BIN}/shasum" "${TEST_BIN}/uname"

run_install_script() {
  (
    export PATH="${TEST_BIN}:${PATH}"
    export TEST_DOCKER_LOG="${LOG_FILE}"
    export TEST_SCENARIO_FILE="${STATE_FILE}"
    export OSTYPE=linux-gnu
    cd "${ROOT_DIR}"
    bash scripts/install-update.sh >/dev/null
  )
}

assert_log_contains() {
  local expected="$1"
  if ! grep -Fq "${expected}" "${LOG_FILE}"; then
    printf 'Expected log to contain: %s\n' "${expected}" >&2
    printf 'Actual log:\n' >&2
    cat "${LOG_FILE}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "${expected}" "${file}"; then
    printf 'Expected %s to contain: %s\n' "${file}" "${expected}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

prepare_env() {
  cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
}

test_first_install_creates_container() {
  : > "${LOG_FILE}"
  prepare_env
  rm -rf "${ROOT_DIR}/state"
  cat > "${STATE_FILE}" <<EOF
CONTAINER_EXISTS=false
CURRENT_IMAGE_ID=sha256:old
BUILT_IMAGE_ID=sha256:new
EOF
  run_install_script
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml build holdfast"
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml up -d holdfast"
  assert_file_contains "${ROOT_DIR}/state/config/serverconfig_custom.txt" "server_name [NA] Quebec Regiment Local"
  assert_file_contains "${ROOT_DIR}/state/config/serverconfig_custom.txt" "!map_rotation start"
  assert_file_contains "${ROOT_DIR}/state/config/serverconfig_custom.txt" "map_name Westmillbrook"
}

test_update_restarts_without_recreate_when_hash_and_image_match() {
  : > "${LOG_FILE}"
  prepare_env
  mkdir -p "${ROOT_DIR}/state"
  printf '1111111111111111111111111111111111111111111111111111111111111111\n' > "${ROOT_DIR}/state/deploy-config.sha256"
  cat > "${STATE_FILE}" <<EOF
CONTAINER_EXISTS=true
CURRENT_IMAGE_ID=sha256:new
BUILT_IMAGE_ID=sha256:new
EOF
  run_install_script
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml stop holdfast"
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml run --rm --no-deps holdfast update-only"
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml start holdfast"
}

test_update_recreates_when_image_changes() {
  : > "${LOG_FILE}"
  prepare_env
  mkdir -p "${ROOT_DIR}/state"
  printf '1111111111111111111111111111111111111111111111111111111111111111\n' > "${ROOT_DIR}/state/deploy-config.sha256"
  cat > "${STATE_FILE}" <<EOF
CONTAINER_EXISTS=true
CURRENT_IMAGE_ID=sha256:old
BUILT_IMAGE_ID=sha256:new
EOF
  run_install_script
  assert_log_contains "compose -f ${ROOT_DIR}/compose.yaml up -d holdfast"
}

main() {
  test_first_install_creates_container
  test_update_restarts_without_recreate_when_hash_and_image_match
  test_update_recreates_when_image_changes
  printf 'All tests passed\n'
}

main "$@"
