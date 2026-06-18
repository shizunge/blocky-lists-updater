# shellcheck shell=sh

# Defining variables and functions here will affect all specfiles.
# Change shell options inside a function may cause different behavior,
# so it is better to set them here.
# set -eu

# This callback function will be invoked only once before loading specfiles.
spec_helper_precheck() {
  # Available functions: info, warn, error, abort, setenv, unsetenv
  # Available variables: VERSION, SHELL_TYPE, SHELL_VERSION
  : minimum_version "0.28.1"
}

# This callback function will be invoked after a specfile has been loaded.
spec_helper_loaded() {
  :
}

# This callback function will be invoked after core modules has been loaded.
spec_helper_configure() {
  # Available functions: import, before_each, after_each, before_all, after_all
  : import 'support/custom_matcher'
}

unique_id() {
  # Try to generate a unique id.
  # To reduce the possibility that tests run in parallel on the same machine affect each other.
  local PID="$$"
  local TIME_STR=
  TIME_STR=$(date +%s)
  TIME_STR=$((TIME_STR % 10000))
  local RANDOM_STR=
  # repository name must be lowercase
  RANDOM_STR=$(head /dev/urandom | LANG=C tr -dc 'a-z0-9' | head -c 8)
  echo "${PID}-${TIME_STR}-${RANDOM_STR}"
}


pull_image_if_not_exist() {
  local IMAGE="${1}"
  if docker image inspect "${IMAGE}" 1>/dev/null 2>/dev/null; then
    return 0
  fi
  docker pull "${IMAGE}" 1>/dev/null
}

display_output() {
  echo "${display_output:-""}"
}

_expect_multiple_messages() {
  TEXT="${1}"
  MESSAGE="${2}"
  local GREEN='\033[0;32m'
  local NO_COLOR='\033[0m'
  if ! ACTUAL_MSG=$(echo "${TEXT}" | grep -Po "${MESSAGE}"); then
    _handle_failure "Failed to find expected message \"${MESSAGE}\"."
    return 1
  fi
  local COUNT=
  COUNT=$(echo "${TEXT}" | grep -Poc "${MESSAGE}");
  if [ "${COUNT}" -le 1 ]; then
    _handle_failure "Failed to find multiple expected messages \"${MESSAGE}\" COUNT=${COUNT}."
    return 1
  fi
  echo -e "${GREEN}EXPECTED${NO_COLOR} found ${COUNT} messages: ${ACTUAL_MSG}"
}

_expect_message() {
  TEXT="${1}"
  MESSAGE="${2}"
  local GREEN='\033[0;32m'
  local NO_COLOR='\033[0m'
  if ! ACTUAL_MSG=$(echo -e "${TEXT}" | grep -Po "${MESSAGE}"); then
    _handle_failure "Failed to find expected message \"${MESSAGE}\"."
    return 1
  fi
  echo -e "${GREEN}EXPECTED${NO_COLOR} found message: ${ACTUAL_MSG}"
}

_expect_no_message() {
  TEXT="${1}"
  MESSAGE="${2}"
  local GREEN='\033[0;32m'
  local NO_COLOR='\033[0m'
  if ACTUAL_MSG=$(echo -e "${TEXT}" | grep -Po "${MESSAGE}"); then
    _handle_failure "The following message should not present: \"${ACTUAL_MSG}\""
    return 1
  fi
  echo -e "${GREEN}EXPECTED${NO_COLOR} found no message matches: ${MESSAGE}"
}

spec_expect_message() {
  _expect_message "${spec_expect_message:-""}" "${1}"
}

spec_expect_multiple_messages() {
  _expect_multiple_messages "${spec_expect_multiple_messages:-""}" "${1}"
}

spec_expect_no_message() {
  _expect_no_message "${spec_expect_no_message:-""}" "${1}"
}
