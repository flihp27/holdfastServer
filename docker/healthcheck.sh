#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${HOLDFAST_LOG_FILE:-/data/logs/outputlog_server.txt}"

pgrep -f "Holdfast NaW" >/dev/null

[ -f "${LOG_FILE}" ]

if grep -Eq "Unable to initialize Steam|No Map Rotations are specified|Server directory not found after update|Missing config file|Expected executable not found" "${LOG_FILE}"; then
  exit 1
fi

grep -Eq "Loading Round ID:|Finished loading map" "${LOG_FILE}"
