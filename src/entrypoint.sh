#!/bin/sh
# Copyright (C) 2024 Shizun Ge
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

load_libraries() {
  local LOCAL_LOG_LEVEL="${BLU_LOG_LEVEL:-""}"
  local LIB_DIR=
  if [ -n "${BLU_LIB_DIR:-""}" ]; then
    LIB_DIR="${BLU_LIB_DIR}"
  elif [ -n "${BASH_SOURCE:-""}" ]; then
    # SC3054 (warning): In POSIX sh, array references are undefined.
    # shellcheck disable=SC3054
    LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" || return 1; pwd -P )"
  elif [ -r "./src/entrypoint.sh" ]; then
    LIB_DIR="./src"
  elif [ -r "./entrypoint.sh" ]; then
    LIB_DIR="."
  fi
  # log function is not available before loading the library.
  if ! echo "${LOCAL_LOG_LEVEL}" | grep -q -i "NONE"; then
    echo "Loading libraries from ${LIB_DIR}"
  fi
  . ${LIB_DIR}/lib-common.sh
  . ${LIB_DIR}/dns-lists-downloader.sh
}

init_requests() {
  local NOTIFY_BASE=
  NOTIFY_BASE=$(mktemp -d)
  STATIC_VAR_REQUEST_REFRESH_FILE="${NOTIFY_BASE}/request-refresh"
  STATIC_VAR_REQUEST_DOWNLOAD_FILE="${NOTIFY_BASE}/request-download"
  date +%s > "${STATIC_VAR_REQUEST_REFRESH_FILE}"
  date +%s > "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}"
  export STATIC_VAR_REQUEST_REFRESH_FILE STATIC_VAR_REQUEST_DOWNLOAD_FILE
}

start_web_server() {
  local WEB_FOLDER="${1}"
  local WEB_PORT="${2:-8080}"
  [ -z "${WEB_FOLDER}" ] && log INFO "Skip running web server. WEB_FOLDER is empty." && return 1
  log INFO "Start static-web-server that serves ${WEB_FOLDER}"
  static-web-server --port="${WEB_PORT}" --root="${WEB_FOLDER}" --log-level=warn --compression=false
}

_notify_via_apprise() {
  local APPRISE_URL="${1}"
  local TYPE="${2}"
  local TITLE="${3}"
  local BODY="${4}"
  [ -z "${APPRISE_URL}" ] && log INFO "Skip notifying via apprise. APPRISE_URL is empty." && return 1
  # info, success, warning, failure
  if [ "${TYPE}" != "info" ] && [ "${TYPE}" != "success" ] && [ "${TYPE}" != "warning" ] && [ "${TYPE}" != "failure" ]; then
    TYPE="info"
  fi
  [ -z "${BODY}" ] && BODY="${TITLE}"
  curl -X POST -H "Content-Type: application/json" --data "{\"title\": \"${TITLE}\", \"body\": \"${BODY}\", \"type\": \"${TYPE}\"}" "${APPRISE_URL}"
}

_post_blocky_lists_refresh() {
  local BLOCKY_URL="${1}"
  local APPRISE_URL="${2}"
  [ -z "${BLOCKY_URL}" ] && log INFO "Skip sending a request to blocky. BLOCKY_URL is empty." && return 1
  local API="/api/lists/refresh"
  local START_TIME=
  local TIME_ELAPSED=
  local LOG=
  local NOTIFICATION_TYPE="info"
  local NOTIFICATION_TITLE=
  log INFO "Sending a request to blocky to refresh lists."
  START_TIME=$(date +%s)
  if LOG=$(curl -X POST --show-error --silent --head "${BLOCKY_URL}${API}" 2>&1); then
    echo "${LOG}" | log_lines INFO
    NOTIFICATION_TYPE="success"
    NOTIFICATION_TITLE="Blocky lists refresh succeeded"
  else
    echo "${LOG}" | log_lines ERROR
    NOTIFICATION_TYPE="failure"
    NOTIFICATION_TITLE="Error during blocky lists refresh"
  fi
  TIME_ELAPSED=$(time_elapsed_since "${START_TIME}")
  log INFO "Refreshing lists done. Use ${TIME_ELAPSED}."
  _notify_via_apprise "${APPRISE_URL}" "${NOTIFICATION_TYPE}" "${NOTIFICATION_TITLE}" "${LOG}"
}

start_refresh_service() {
  export LOG_SCOPE="refresh_service"
  local BLOCKY_URL="${1}"
  local APPRISE_URL="${2}"
  [ -z "${STATIC_VAR_REQUEST_REFRESH_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_REFRESH_FILE is empty" && return 1
  [ -z "${BLOCKY_URL}" ] && log INFO "Skip refresh service BLOCKY_URL is empty." && return 1
  local LAST_FILE_TIME=
  local CURRENT_FILE_TIME=
  while true; do
    log DEBUG "Waiting for the next refresh request."
    inotifywait -e modify -e move -e create -e delete "${STATIC_VAR_REQUEST_REFRESH_FILE}" 2>&1 | log_lines DEBUG
    LAST_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_REFRESH_FILE}")
    _post_blocky_lists_refresh "${BLOCKY_URL}" "${APPRISE_URL}"
    CURRENT_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_REFRESH_FILE}")
    log DEBUG "LAST_FILE_TIME=${LAST_FILE_TIME}"
    log DEBUG "CURRENT_FILE_TIME=${CURRENT_FILE_TIME}"
    if [ "${CURRENT_FILE_TIME}" -gt "${LAST_FILE_TIME}" ]; then
      # During refreshing, the source or watched files changed again.
      log DEBUG "Receive another request during refreshing lists."
      sleep 2 && _request_refresh &
    fi
  done
}

_request_refresh() {
  [ -z "${STATIC_VAR_REQUEST_REFRESH_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_REFRESH_FILE is empty" && return 1
  date +%s > "${STATIC_VAR_REQUEST_REFRESH_FILE}"
}

start_download_service() {
  export LOG_SCOPE="download_service"
  local SOURCES_FOLDER="${1}"
  local DESTINATION_FOLDER="${2}"
  local POST_DOWNLOAD_CMD="${3}"
  [ -z "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_DOWNLOAD_FILE is empty" && return 1
  [ -z "${SOURCES_FOLDER}" ] && log INFO "Skip download service. SOURCES_FOLDER is empty." && return 1
  local LAST_FILE_TIME=
  local CURRENT_FILE_TIME=
  while true; do
    log DEBUG "Waiting for the next download request."
    inotifywait -e modify -e move -e create -e delete "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" 2>&1 | log_lines DEBUG
    LAST_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}")
    download_lists "${SOURCES_FOLDER}" "${DESTINATION_FOLDER}" "${POST_DOWNLOAD_CMD}"
    log INFO "Downloading done. Requesting lists refreshing."
    _request_refresh
    CURRENT_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}")
    log DEBUG "LAST_FILE_TIME=${LAST_FILE_TIME}"
    log DEBUG "CURRENT_FILE_TIME=${CURRENT_FILE_TIME}"
    if [ "${CURRENT_FILE_TIME}" -gt "${LAST_FILE_TIME}" ]; then
      # During downloading, the source files changed again.
      log DEBUG "Receive another download request during downloading."
      sleep 2 && _request_download &
    fi
  done
}

_request_download() {
  [ -z "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_DOWNLOAD_FILE is empty" && return 1
  date +%s > "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}"
}

start_watching_files() {
  export LOG_SCOPE="watch_files"
  local WATCH_FOLDER="${1}"
  [ -z "${WATCH_FOLDER}" ] && log INFO "Skip watching files. WATCH_FOLDER is empty." && return 1
  log INFO "Start watching changes in ${WATCH_FOLDER}."
  while true; do
    log DEBUG "Waiting for changes in ${WATCH_FOLDER}."
    inotifywait -e modify -e move -e create -e delete "${WATCH_FOLDER}" 2>&1 | log_lines DEBUG
    log INFO "Found changes in ${WATCH_FOLDER}. Requesting lists refreshing."
    _request_refresh
  done
}

start_watching_sources() {
  export LOG_SCOPE="watch_sources"
  local SOURCES_FOLDER="${1}"
  local INTERVAL_SECONDS="${2:-0}"
  local INITIAL_DELAY_SECONDS="${3:-0}"
  [ -z "${SOURCES_FOLDER}" ] && log INFO "Skip watching sources. SOURCES_FOLDER is empty." && return 1
  local NEXT_RUN_TARGET_TIME TIMEOUT_ARG TIMEOUT_SEC
  local LOG=
  if [ "${INITIAL_DELAY_SECONDS}" -gt 0 ]; then
    log INFO "Wait ${INITIAL_DELAY_SECONDS} seconds before the first download."
    sleep "${INITIAL_DELAY_SECONDS}"
  fi
  log INFO "Request the first download."
  NEXT_RUN_TARGET_TIME=$(($(date +%s) + INTERVAL_SECONDS))
  _request_download
  log INFO "Start watching changes in ${SOURCES_FOLDER}."
  while true; do
    TIMEOUT_ARG=""
    TIMEOUT_SEC=""
    if [ "${INTERVAL_SECONDS}" -gt 0 ]; then
      log INFO "Scheduling next download at $(busybox date -d "@${NEXT_RUN_TARGET_TIME}" -Iseconds)."
      TIMEOUT_ARG="--timeout"
      TIMEOUT_SEC=$(( NEXT_RUN_TARGET_TIME - $(date +%s) ))
    fi
    if LOG=$(inotifywait -q -e modify -e move -e create -e delete "${TIMEOUT_ARG}" "${TIMEOUT_SEC}" "${SOURCES_FOLDER}" 2>&1); then
      # 0 - An event you asked to watch for was received.
      echo "${LOG}" | log_lines DEBUG
      log INFO "Found changes in ${SOURCES_FOLDER}. Requesting lists downloading."
    else
      # 1 - An event you did not ask to watch for was received (usually delete_self or unmount), or some error occurred.
      # 2 - The --timeout option was given and no events occurred in the specified interval of time.
      echo "${LOG}" | log_lines DEBUG
      log INFO "Running scheduled download."
    fi
    NEXT_RUN_TARGET_TIME=$(($(date +%s) + INTERVAL_SECONDS))
    _request_download
  done
}

main() {
  LOG_LEVEL="${BLU_LOG_LEVEL:-${LOG_LEVEL}}"
  NODE_NAME="${BLU_NODE_NAME:-${NODE_NAME}}"
  export LOG_LEVEL NODE_NAME
  local BLOCKY_URL DESTINATION_FOLDER INITIAL_DELAY_SECONDS INTERVAL_SECONDS APPRISE_URL
  local SOURCES_FOLDER POST_DOWNLOAD_CMD WATCH_FOLDER WEB_FOLDER WEB_PORT
  BLOCKY_URL=$(read_env "BLU_BLOCKY_URL" "")
  DESTINATION_FOLDER=$(read_env "BLU_DESTINATION_FOLDER" "/web/downloaded")
  INITIAL_DELAY_SECONDS=$(read_env "BLU_INITIAL_DELAY_SECONDS" 0)
  INTERVAL_SECONDS=$(read_env "BLU_INTERVAL_SECONDS" 86400)
  APPRISE_URL=$(read_env "BLU_NOTIFICATION_APPRISE_URL" "")
  SOURCES_FOLDER=$(read_env "BLU_SOURCES_FOLDER" "/sources")
  POST_DOWNLOAD_CMD=$(read_env "BLU_POST_DOWNLOAD_CMD" "")
  WATCH_FOLDER=$(read_env "BLU_WATCH_FOLDER" "/web/watch")
  WEB_FOLDER=$(read_env "BLU_WEB_FOLDER" "/web")
  WEB_PORT=$(read_env "BLU_WEB_PORT" 8080)
  if ! is_number "${INITIAL_DELAY_SECONDS}"; then
    log ERROR "BLU_INITIAL_DELAY_SECONDS must be a number. Got \"${BLU_INITIAL_DELAY_SECONDS:-""}\"."
    return 1;
  fi
  if ! is_number "${INTERVAL_SECONDS}"; then
    log ERROR "BLU_INTERVAL_SECONDS must be a number. Got \"${BLU_INTERVAL_SECONDS:-""}\"."
    return 1;
  fi
  log DEBUG "BLOCKY_URL=${BLOCKY_URL}"
  log DEBUG "DESTINATION_FOLDER=${DESTINATION_FOLDER}"
  log DEBUG "INITIAL_DELAY_SECONDS=${INITIAL_DELAY_SECONDS}"
  log DEBUG "INTERVAL_SECONDS=${INTERVAL_SECONDS}"
  log DEBUG "APPRISE_URL=${APPRISE_URL}"
  log DEBUG "SOURCES_FOLDER=${SOURCES_FOLDER}"
  log DEBUG "POST_DOWNLOAD_CMD=${POST_DOWNLOAD_CMD}"
  log DEBUG "WATCH_FOLDER=${WATCH_FOLDER}"
  log DEBUG "WEB_FOLDER=${WEB_FOLDER}"
  log DEBUG "WEB_PORT=${WEB_PORT}"

  init_requests
  start_web_server "${WEB_FOLDER}" "${WEB_PORT}" &
  sleep 1
  start_refresh_service "${BLOCKY_URL}" "${APPRISE_URL}" &
  sleep 1
  start_download_service "${SOURCES_FOLDER}" "${DESTINATION_FOLDER}" "${POST_DOWNLOAD_CMD}" &
  sleep 1
  start_watching_files "${WATCH_FOLDER}" &
  sleep 1
  if ! start_watching_sources "${SOURCES_FOLDER}" "${INTERVAL_SECONDS}" "${INITIAL_DELAY_SECONDS}"; then
    while true; do sleep 86400; done
  fi
}

trap "log INFO \"Exit.\"; exit;" HUP INT TERM
load_libraries
main "${@}"
