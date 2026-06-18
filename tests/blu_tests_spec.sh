#!/bin/bash spellspec
# Copyright (C) 2026 Shizun Ge
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

UINQUE_ID="$(unique_id)"
export SERVICE_NAME_APPRISE="blu-test-${UINQUE_ID}-apprise"
export SERVICE_NAME_MAILPIT="blu-test-${UINQUE_ID}-mailpit"
export SERVICE_NAME_FILE="blu-test-${UINQUE_ID}-file"
export SERVICE_NAME_BLOCKY="blu-test-${UINQUE_ID}-blocky"
export SERVICE_NAME_BLU="blu-test-${UINQUE_ID}-blu"
# APPRISE_PORT is hard coded in the Apprise container.
export APPRISE_PORT=8000
export SMTP_PORT=1025
export EMAIL_API_PORT=8025
# BLOCKY_PORT DNS_PORT is defined in blocky-config.yml.
export DNS_PORT=8053
export BLOCKY_PORT=4000
export BLU_WEB_PORT=8080
export FILE_PORT=8081

_build_blocky_lists_updater() {
  local IMAGE="${1}"
  echo "Building blocky-lists-updater image"
  docker build --quiet --label blu.test=true --tag "${IMAGE}" .
}

_start_apprise() {
  local IMAGE="ghcr.io/caronc/apprise"
  pull_image_if_not_exist "${IMAGE}"
  docker stop "${SERVICE_NAME_APPRISE}" 1>/dev/null 2>/dev/null
  docker container remove "${SERVICE_NAME_APPRISE}" 1>/dev/null 2>/dev/null
  docker run -d --restart=on-failure:10 --name="${SERVICE_NAME_APPRISE}" --network=host \
    --label blu.test=true \
    -e "APPRISE_STATELESS_URLS=mailto://localhost:${SMTP_PORT}?user=userid&pass=password" \
    "${IMAGE}"
}

_start_mailpit() {
  local IMAGE="ghcr.io/axllent/mailpit"
  pull_image_if_not_exist "${IMAGE}"
  docker stop "${SERVICE_NAME_MAILPIT}" 1>/dev/null 2>/dev/null
  docker container remove "${SERVICE_NAME_MAILPIT}" 1>/dev/null 2>/dev/null
  docker run -d --restart=on-failure:10 --name="${SERVICE_NAME_MAILPIT}" --network=host \
    --label blu.test=true \
    "${IMAGE}" \
    --smtp "localhost:${SMTP_PORT}" --listen "localhost:${EMAIL_API_PORT}" \
    --smtp-auth-accept-any --smtp-auth-allow-insecure
}

_start_file_server() {
  local WEB_DIR="${1}"
  local IMAGE="ghcr.io/static-web-server/static-web-server"
  pull_image_if_not_exist "${IMAGE}"
  # Start a simple file server to serve the source and watch lists.
  # The lists-updater will download lists from this server.
  # The server will be automatically stopped when the container is removed.
  docker run -d --restart=on-failure:10 --name="${SERVICE_NAME_FILE}" --network=host \
    --label blu.test=true \
    --volume "${WEB_DIR}:/web:ro" \
    "${IMAGE}" \
    --port="${FILE_PORT}" --root="/web" --log-level=info --compression=false
}

_start_blocky_lists_updater() {
  local IMAGE="${1}"
  local SOURCES_DIR="${2}"
  local WATCH_DIR="${3}"
  docker stop "${SERVICE_NAME_BLU}" 1>/dev/null 2>/dev/null
  docker container remove "${SERVICE_NAME_BLU}" 1>/dev/null 2>/dev/null
  docker run -d --restart=on-failure:10 --name="${SERVICE_NAME_BLU}" --network=host \
    --label blu.test=true \
    -e "BLU_LOG_LEVEL=DEBUG" \
    -e "BLU_BLOCKY_URL=http://localhost:${BLOCKY_PORT}" \
    -e "BLU_DESTINATION_FOLDER=/web/downloaded" \
    -e "BLU_INITIAL_DELAY_SECONDS=5" \
    -e "BLU_INTERVAL_SECONDS=${BLU_INTERVAL_SECONDS}" \
    -e "BLU_NOTIFICATION_APPRISE_URL=http://localhost:${APPRISE_PORT}/notify" \
    -e "BLU_POST_DOWNLOAD_CMD=echo post-download" \
    -e "BLU_POST_MERGING_CMD=echo post-merging" \
    -e "BLU_SOURCES_FOLDER=/sources" \
    -e "BLU_WATCH_FOLDER=/web/watch" \
    -e "BLU_WEB_FOLDER=/web" \
    -e "BLU_WEB_PORT=${BLU_WEB_PORT}" \
    --volume "${SOURCES_DIR}:/sources:ro" \
    --volume "${WATCH_DIR}:/web/watch:ro" \
    "${IMAGE}"
}

_start_blocky() {
  local IMAGE="ghcr.io/0xerr0r/blocky"
  pull_image_if_not_exist "${IMAGE}"
  docker stop "${SERVICE_NAME_BLOCKY}" 1>/dev/null 2>/dev/null
  docker container remove "${SERVICE_NAME_BLOCKY}" 1>/dev/null 2>/dev/null
  docker run -d --restart=on-failure:10 --name="${SERVICE_NAME_BLOCKY}" --network=host \
    --label blu.test=true \
    --cap-add=NET_BIND_SERVICE \
    --volume "$(pwd)/tests/blocky-config.yml:/app/config.yml:ro" \
    "${IMAGE}"
}

_print_and_cleanup_emails() {
  local API_URL="localhost:${EMAIL_API_PORT}/api/v1"
  echo -e "\nPrint emails:"
  curl --silent "${API_URL}/messages" 2>&1
  # Delete all messages
  curl --silent -X "DELETE" "${API_URL}/messages" 2>&1
  echo ""
}

_print_dut_logs() {
  echo -e "\nPrint Blocky-lists-updater log:"
  docker logs "${SERVICE_NAME_BLU}"
}

_stop_dut() {
  docker container stop "${SERVICE_NAME_BLU}"
  docker container remove "${SERVICE_NAME_BLU}"
}

_print_containers_logs() {
  echo -e "\nPrint Apprise log:"
  docker logs "${SERVICE_NAME_APPRISE}"
  echo -e "\nPrint Mailpit log:"
  docker logs "${SERVICE_NAME_MAILPIT}"
  echo -e "\nPrint File server log:"
  docker logs "${SERVICE_NAME_FILE}"
  echo -e "\nPrint Blocky log:"
  docker logs "${SERVICE_NAME_BLOCKY}"
  echo ""
}

_stop_containers() {
  docker container stop "${SERVICE_NAME_APPRISE}"
  docker container remove "${SERVICE_NAME_APPRISE}"
  docker container stop "${SERVICE_NAME_MAILPIT}"
  docker container remove "${SERVICE_NAME_MAILPIT}"
  docker container stop "${SERVICE_NAME_FILE}"
  docker container remove "${SERVICE_NAME_FILE}"
  docker container stop "${SERVICE_NAME_BLOCKY}"
  docker container remove "${SERVICE_NAME_BLOCKY}"
}

_wait_for_dns_change() {
  local OLD_IP="${1}"
  local DOMAIN="${2:-google.com}"
  local MAX_TIMEOUT="${3:-60}"
  local TIMEOUT=0
  local IP="${OLD_IP}"
  IP=$(dig +short @localhost -p "${DNS_PORT}" "${DOMAIN}")
  while [ "${IP}" = "${OLD_IP}" ]; do
    sleep 1
    IP=$(dig +short @localhost -p "${DNS_PORT}" "${DOMAIN}")
    TIMEOUT=$((TIMEOUT + 1))
    if [ "${TIMEOUT}" -ge "${MAX_TIMEOUT}" ]; then
      echo "${OLD_IP}"
      return 1
    fi
  done
  echo "${IP}"
}

teardown() {
  _stop_dut >/dev/null 2>&1
  _stop_containers >/dev/null 2>&1
}

Describe 'blu_test'
  Describe "test_trigger_and_notify_apprise"
    test_trigger_and_notify_apprise() {
      local RETURN_VALUE=0
      local BLU_IMAGE="blu_dut"
      local DIR WEB_DIR SOURCES_DIR WATCH_DIR
      DIR=$(mktemp -d) || return 1
      WEB_DIR=$(mkdir "${DIR}/web" && echo "${DIR}/web") || return 1
      SOURCES_DIR=$(mkdir "${DIR}/sources" && echo "${DIR}/sources") || return 1
      WATCH_DIR=$(mkdir "${DIR}/watch" && echo "${DIR}/watch") || return 1
      local LIST_FILE_NAME="list.txt"
      local LIST_FILE="${WEB_DIR}/${LIST_FILE_NAME}"
      local SOURCES_FILE="${SOURCES_DIR}/sources.txt"
      local WATCH_FILE="${WATCH_DIR}/watch.txt"
      touch "${LIST_FILE}" "${SOURCES_FILE}" "${WATCH_FILE}"
      echo "LIST_FILE=${LIST_FILE}"
      echo "SOURCES_FILE=${SOURCES_FILE}"
      echo "WATCH_FILE=${WATCH_FILE}"
      echo "google.com" > "${LIST_FILE}"
      _build_blocky_lists_updater "${BLU_IMAGE}" 2>&1
      _start_apprise 2>&1
      _start_mailpit 2>&1
      _start_file_server "${WEB_DIR}" 2>&1
      export BLU_INTERVAL_SECONDS=86400
      _start_blocky_lists_updater "${BLU_IMAGE}" "${SOURCES_DIR}" "${WATCH_DIR}" 2>&1
      _start_blocky 2>&1
      sleep 10
      # Update the file list.
      local DOMAIN="google.com"
      local IP="0.0.0.0"
      echo ""
      echo "At beginning, Blocky should resolve ${DOMAIN}."
      if ! IP=$(_wait_for_dns_change "${IP}" "${DOMAIN}"); then
        echo "${DOMAIN} is not resolved initially."
        return 1
      fi
      echo "${DOMAIN} is resolved to ${IP}."
      echo "Updating source lists."
      echo "localhost:${FILE_PORT}/${LIST_FILE_NAME}" > "${SOURCES_FILE}"
      echo "Now Blocky should block ${DOMAIN}."
      if ! IP=$(_wait_for_dns_change "${IP}" "${DOMAIN}"); then
        echo "${DOMAIN} is still resolved. Want ${DOMAIN} to be blocked."
        return 1
      fi
      echo "${DOMAIN} is resolved to ${IP}."
      echo "Updating watch file. Watch file is in the allowed list."
      echo "google.com" > "${WATCH_FILE}"
      echo "Now Blocky should resolve ${DOMAIN} again."
      if ! IP=$(_wait_for_dns_change "${IP}" "${DOMAIN}"); then
        echo "${DOMAIN} is not resolved. Want ${DOMAIN} to be resolved."
        return 1
      fi
      echo "${DOMAIN} is resolved to ${IP}."
      # Check domains blocked correctly.
      # Update the domain list.
      # Check domains blocked correctly.
      _print_dut_logs 2>&1
      _print_and_cleanup_emails 2>&1
      # _print_containers_logs 1>&2
      rm -r "${DIR}"
      return "${RETURN_VALUE}"
    }
    AfterEach "teardown"
    It 'run_test'
      When run test_trigger_and_notify_apprise
      The status should be success
      The stdout should satisfy display_output
      The stdout should satisfy spec_expect_message    "Found changes in /sources. Requesting lists downloading."
      The stdout should satisfy spec_expect_message    "post-download .*sources.txt-current.txt"
      The stdout should satisfy spec_expect_message    "post-merging /web/downloaded/sources.txt"
      The stdout should satisfy spec_expect_message    "Sending a request to blocky to refresh lists"
      The stdout should satisfy spec_expect_message    "Downloading done. Requesting lists refreshing"
      The stdout should satisfy spec_expect_message    "Found changes in /web/watch. Requesting lists refreshing."
      The stdout should satisfy spec_expect_message    "Sent notification via Apprise"
      The stdout should satisfy spec_expect_no_message "Invalid JSON Payload provided"
      The stdout should satisfy spec_expect_message    "Subject\":\"Blocky lists refresh succeeded"
      The stdout should satisfy spec_expect_message    "Snippet\":\"HTTP/1.1 200 OK"
      The stderr should satisfy display_output
    End
  End
End # Describe 'blu_test'
