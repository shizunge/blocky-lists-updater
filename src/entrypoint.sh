#!/bin/bash
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
  local LOCAL_LOG_LEVEL="${BLD_LOG_LEVEL:-""}"
  local LIB_DIR=
  if [ -n "${BLD_LIB_DIR:-""}" ]; then
    LIB_DIR="${BLD_LIB_DIR}"
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
  . ${LIB_DIR}/dns-list-downloader.sh
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
  [ -z "${WEB_FOLDER}" ] && log WARN "Skip running web server due to WEB_FOLDER is empty." && return 1
  log INFO "Start static-web-server that services ${WEB_FOLDER}"
  static-web-server --port="${WEB_PORT}" --root="${WEB_FOLDER}" --log-level=warn --compression=false
}

post_blocky_lists_refresh() {
  local BLOCKY_URL="${1}"
  [ -z "${BLOCKY_URL}" ] && log WARN "Skip sending a request to blocky. BLOCKY_URL is empty." && return 1
  local API="/api/lists/refresh"
  local START_TIME=
  local TIME_ELAPSED=
  local LOG=
  log INFO "Sending a request to blocky to refresh lists."
  START_TIME=$(date +%s)
  if LOG=$(curl -X POST --show-error --silent --head "${BLOCKY_URL}${API}" 2>&1); then
    echo "${LOG}" | log_lines INFO
  else
    echo "${LOG}" | log_lines ERROR
  fi
  TIME_ELAPSED=$(time_elapsed_since "${START_TIME}")
  log INFO "Refreshing lists done. Use ${TIME_ELAPSED}."
}

start_refresh_service() {
  export LOG_SCOPE="refresh_service"
  local BLOCKY_URL="${1}"
  [ -z "${STATIC_VAR_REQUEST_REFRESH_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_REFRESH_FILE is empty" && return 1
  local LAST_FILE_TIME=
  local CURRENT_FILE_TIME=
  while true; do
    log DEBUG "Waiting for the next refresh request."
    inotifywait -e modify -e move -e create -e delete "${STATIC_VAR_REQUEST_REFRESH_FILE}" 2>&1 | log_lines DEBUG
    LAST_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_REFRESH_FILE}")
    post_blocky_lists_refresh "${BLOCKY_URL}"
    CURRENT_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_REFRESH_FILE}")
    log DEBUG "LAST_FILE_TIME=${LAST_FILE_TIME}"
    log DEBUG "CURRENT_FILE_TIME=${CURRENT_FILE_TIME}"
    if [ "${CURRENT_FILE_TIME}" -gt "${LAST_FILE_TIME}" ]; then
      # During refreshing, the source or watched files changed again.
      log DEBUG "Receive another request during refreshing lists."
      sleep 2 && request_refresh &
    fi
  done
}

request_refresh() {
  [ -z "${STATIC_VAR_REQUEST_REFRESH_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_REFRESH_FILE is empty" && return 1
  date +%s > "${STATIC_VAR_REQUEST_REFRESH_FILE}"
}

start_download_service() {
  export LOG_SCOPE="download_service"
  local SOURCES_FOLDER="${1}"
  local DESTINATION_FOLDER="${2}"
  [ -z "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_DOWNLOAD_FILE is empty" && return 1
  local LAST_FILE_TIME=
  local CURRENT_FILE_TIME=
  while true; do
    log DEBUG "Waiting for the next download request."
    inotifywait -e modify -e move -e create -e delete "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" 2>&1 | log_lines DEBUG
    LAST_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}")
    download_lists "${SOURCES_FOLDER}" "${DESTINATION_FOLDER}"
    log INFO "Downloading done. Requesting lists refreshing."
    request_refresh
    CURRENT_FILE_TIME=$(head -1 "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}")
    log DEBUG "LAST_FILE_TIME=${LAST_FILE_TIME}"
    log DEBUG "CURRENT_FILE_TIME=${CURRENT_FILE_TIME}"
    if [ "${CURRENT_FILE_TIME}" -gt "${LAST_FILE_TIME}" ]; then
      # During downloading, the source files changed again.
      log DEBUG "Receive another download request during downloading."
      sleep 2 && request_download &
    fi
  done
}

request_download() {
  [ -z "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}" ] && log ERROR "STATIC_VAR_REQUEST_DOWNLOAD_FILE is empty" && return 1
  date +%s > "${STATIC_VAR_REQUEST_DOWNLOAD_FILE}"
}

start_watching_files() {
  export LOG_SCOPE="watch_files"
  local WATCH_FOLDER="${1}"
  [ -z "${WATCH_FOLDER}" ] && log WARN "Skip watching files. WATCH_FOLDER is empty." && return 1
  log INFO "Start watching changes in ${WATCH_FOLDER}."
  while true; do
    log DEBUG "Waiting for changes in ${WATCH_FOLDER}."
    inotifywait -e modify -e move -e create -e delete "${WATCH_FOLDER}" 2>&1 | log_lines DEBUG
    log INFO "Found changes in ${WATCH_FOLDER}. Requesting lists refreshing."
    request_refresh
  done
}

start_watching_sources() {
  export LOG_SCOPE="watch_sources"
  local SOURCES_FOLDER="${1}"
  local INTERVAL_SECONDS="${2:-0}"
  local INITIAL_DELAY_SECONDS="${3:-0}"
  [ "${INTERVAL_SECONDS}" -le 0 ] && log WARN "Skip watching sources. INTERVAL_SECONDS ${INTERVAL_SECONDS} is equal to or less than 0." && return 1
  local NEXT_RUN_TARGET_TIME=
  local SLEEP_SECONDS=
  local LOG=
  if [ "${INITIAL_DELAY_SECONDS}" -gt 0 ]; then
    log INFO "Wait ${INITIAL_DELAY_SECONDS} seconds before the first download."
    sleep "${INITIAL_DELAY_SECONDS}"
  fi
  log INFO "Request the first download."
  NEXT_RUN_TARGET_TIME=$(($(date +%s) + INTERVAL_SECONDS))
  request_download
  log INFO "Start watching changes in ${SOURCES_FOLDER}."
  while true; do
    log INFO "Scheduling next download at $(busybox date -d "@${NEXT_RUN_TARGET_TIME}" -Iseconds)."
    SLEEP_SECONDS=$((NEXT_RUN_TARGET_TIME - $(date +%s)))
    if LOG=$(inotifywait -q -e modify -e move -e create -e delete --timeout "${SLEEP_SECONDS}" "${SOURCES_FOLDER}" 2>&1); then
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
    request_download
  done
}

main() {
  LOG_LEVEL="${BLD_LOG_LEVEL:-${LOG_LEVEL}}"
  NODE_NAME="${BLD_NODE_NAME:-${NODE_NAME}}"
  export LOG_LEVEL NODE_NAME
  local BLOCKY_URL="${BLD_BLOCKY_URL:-""}" 
  local DESTINATION_FOLDER="${BLD_DESTINATION_FOLDER:-"/web/downloaded"}"
  local INITIAL_DELAY_SECONDS="${BLD_INITIAL_DELAY_SECONDS:-0}"
  local INTERVAL_SECONDS="${BLD_INTERVAL_SECONDS:-86400}"
  local SOURCES_FOLDER="${BLD_SOURCES_FOLDER:-"/web/sources"}"
  local WATCH_FOLDER="${BLD_WATCH_FOLDER:-"/web/watch"}"
  local WEB_FOLDER="${BLD_WEB_FOLDER:-"/web"}"
  local WEB_PORT="${BLD_WEB_PORT:-8080}"
  if ! is_number "${INITIAL_DELAY_SECONDS}"; then
    log ERROR "BLD_INITIAL_DELAY_SECONDS must be a number. Got \"${BLD_INITIAL_DELAY_SECONDS}\"."
    return 1;
  fi
  if ! is_number "${INTERVAL_SECONDS}"; then
    log ERROR "BLD_INTERVAL_SECONDS must be a number. Got \"${BLD_INTERVAL_SECONDS}\"."
    return 1;
  fi
  log DEBUG "BLOCKY_URL=${BLOCKY_URL}"
  log DEBUG "DESTINATION_FOLDER=${DESTINATION_FOLDER}"
  log DEBUG "INITIAL_DELAY_SECONDS=${INITIAL_DELAY_SECONDS}"
  log DEBUG "INTERVAL_SECONDS=${INTERVAL_SECONDS}"
  log DEBUG "SOURCES_FOLDER=${SOURCES_FOLDER}"
  log DEBUG "WATCH_FOLDER=${WATCH_FOLDER}"
  log DEBUG "WEB_FOLDER=${WEB_FOLDER}"
  log DEBUG "WEB_PORT=${WEB_PORT}"

  init_requests
  start_web_server "${WEB_FOLDER}" "${WEB_PORT}" &
  sleep 1
  start_refresh_service "${BLOCKY_URL}" &
  sleep 1
  start_download_service "${SOURCES_FOLDER}" "${DESTINATION_FOLDER}" &
  sleep 1
  start_watching_files "${WATCH_FOLDER}" &
  sleep 1
  if ! start_watching_sources "${SOURCES_FOLDER}" "${INTERVAL_SECONDS}" "${INITIAL_DELAY_SECONDS}"; then
    log INFO "Download once then exit."
    log INFO "Wait ${INITIAL_DELAY_SECONDS} seconds before the first download."
    sleep "${INITIAL_DELAY_SECONDS}"
    download_lists "${SOURCES_FOLDER}" "${DESTINATION_FOLDER}"
    post_blocky_lists_refresh "${BLOCKY_URL}"
  fi
}

trap "log INFO \"Exit.\"; exit;" HUP INT TERM
load_libraries
main "${@}"
