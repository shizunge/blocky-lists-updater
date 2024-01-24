#!/bin/sh
# Copyright (C) 2023-2024 Shizun Ge
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

_rm_check() {
  if [ -z "${1}" ]; then return 1; fi
  test -e "${1}" && log DEBUG "Removing ${1}" && rm -r "${1}"
}

_file_size() {
  du -h "${1}" | cut -f1
}

_fix_list() {
  # fix "0.0.0.0abc.com" -> "0.0.0.0 abc.com"
  sed -i 's/^0\.0\.0\.0\([^ ].*\)/0.0.0.0 \1/' "${1}"
  # fix "0 abc.com" -> "0.0.0.0 abc.com"
  sed -i 's/^0 \(.*\)/0.0.0.0 \1/' "${1}"
  # fix "||abc.com^" -> "0.0.0.0 abc.com"
  sed -i 's/^||\(.*\)^$/0.0.0.0 \1/' "${1}"
  # fix "!comments" -> "# !comments"
  sed -i 's/^\(!.*\)$/# \1/' "${1}"
}

_download_from_single_source_file() {
  local SOURCE_FILE="${1}"
  local DESTINATION_FOLDER="${2}"
  local POST_DOWNLOAD_CMD="${3}"
  [ -z "${SOURCE_FILE}" ] && log ERROR "SOURCE_FILE is empty." && return 1
  [ -z "${DESTINATION_FOLDER}" ] && log ERROR "DESTINATION_FOLDER is empty." && return 1
  local DESTINATION_FILE=
  DESTINATION_FILE=$(basename "${SOURCE_FILE}")
  local RETRY_MAX=5
  local RETRY_WAIT_SECOND=10
  log INFO "=============================="
  log INFO "=== Downloading lists based on $(basename "${SOURCE_FILE}")."
  log INFO "=============================="
  local TEMP_DIR=
  TEMP_DIR=$(mktemp -d)
  log DEBUG "TEMP_DIR=${TEMP_DIR}"
  mkdir -p "${TEMP_DIR}"
  local ACCUMULATOR_FILE="${TEMP_DIR}/${DESTINATION_FILE}-merged.txt"
  local ACCUMULATED_ERRORS=0
  _rm_check "${ACCUMULATOR_FILE}"
  touch "${ACCUMULATOR_FILE}"
  # pipeline causes subshell
  # ( cat "${SOURCE_FILE}"; echo; ) | while read -r S; do
  while read -r SOURCE_LINE; do
    # trim whitespace
    SOURCE_LINE=$(echo "${SOURCE_LINE}" | xargs)
    if [ -z "${SOURCE_LINE}" ]; then
      continue
    fi
    if [ "${SOURCE_LINE:0:1}" = "#" ]; then
      log DEBUG "Skip comment: ${SOURCE_LINE}"
      continue
    fi
    if ! busybox wget -q --spider "${SOURCE_LINE}" 2>/dev/null; then
      # SC2129: Consider using { cmd1; cmd2; } >> file instead of individual redirects.
      # shellcheck disable=SC2129
      echo "####################" >> "${ACCUMULATOR_FILE}"
      echo "### Failed to fetch source \"${SOURCE_LINE}\"" >> "${ACCUMULATOR_FILE}"
      echo "" >> "${ACCUMULATOR_FILE}"
      log ERROR "Failed to fetch source \"${SOURCE_LINE}\"."
      ACCUMULATED_ERRORS=$((ACCUMULATED_ERRORS + 1))
      continue
    fi
    log INFO "Downloading ${SOURCE_LINE}"
    echo "####################" >> "${ACCUMULATOR_FILE}"
    echo "### Downloaded from ${SOURCE_LINE}" >> "${ACCUMULATOR_FILE}"
    local CURRENT_FILE="${TEMP_DIR}/${DESTINATION_FILE}-current.txt"
    local RETRIES=0
    local CURRENT_ERROR=0
    _rm_check "${CURRENT_FILE}"
    while ! busybox wget -q -O "${CURRENT_FILE}" "${SOURCE_LINE}"; do
      CURRENT_ERROR=$?
      _rm_check "${CURRENT_FILE}"
      if [ ${RETRIES} -ge ${RETRY_MAX} ]; then
        break;
      fi
      RETRIES=$((RETRIES + 1))
      sleep ${RETRY_WAIT_SECOND}
    done
    if [ ${CURRENT_ERROR} -ne 0 ]; then
      echo "### Donwloading ${SOURCE_LINE} has an error." >> "${ACCUMULATOR_FILE}"
      log ERROR "Failed to download ${SOURCE_LINE}."
      ACCUMULATED_ERRORS=$((ACCUMULATED_ERRORS + 1))
      continue
    fi
    _fix_list "${CURRENT_FILE}"
    eval_cmd "post-download" "${POST_DOWNLOAD_CMD} ${CURRENT_FILE}"
    log DEBUG "Merging ${CURRENT_FILE} to ${ACCUMULATOR_FILE}"
    # SC2129: Consider using { cmd1; cmd2; } >> file instead of individual redirects.
    # shellcheck disable=SC2129
    echo "" >> "${ACCUMULATOR_FILE}"
    cat "${CURRENT_FILE}" >> "${ACCUMULATOR_FILE}"
    echo "" >> "${ACCUMULATOR_FILE}"
    log INFO "Downloaded  ${SOURCE_LINE}. Size is $(_file_size "${CURRENT_FILE}")."
    _rm_check "${CURRENT_FILE}"
  done < <(cat "${SOURCE_FILE}"; echo;)
  log DEBUG "Moving ${ACCUMULATOR_FILE} to ${DESTINATION_FILE}"
  local DST_PATH=
  DST_PATH="${DESTINATION_FOLDER}/${DESTINATION_FILE}"
  mv "${ACCUMULATOR_FILE}" "${DST_PATH}"
  _rm_check "${TEMP_DIR}"
  log INFO "=============================="
  log INFO "=== Download done for ${DESTINATION_FILE}. Size is $(_file_size "${DST_PATH}")."
  return ${ACCUMULATED_ERRORS}
}

download_lists() {
  local SOURCES_FOLDER="${1}"
  local DESTINATION_FOLDER="${2}"
  local POST_DOWNLOAD_CMD="${3}"
  if [ -z "${SOURCES_FOLDER}" ]; then
    log ERROR "SOURCES_FOLDER is empty."
    return 1
  fi
  if [ -z "${DESTINATION_FOLDER}" ]; then
    DESTINATION_FOLDER="$(pwd)"
  fi
  SOURCES_FOLDER="$(readlink -f "${SOURCES_FOLDER}")"
  DESTINATION_FOLDER="$(readlink -f "${DESTINATION_FOLDER}")"
  log DEBUG "SOURCES_FOLDER=${SOURCES_FOLDER}"
  log DEBUG "DESTINATION_FOLDER=${DESTINATION_FOLDER}"
  if [ "${DESTINATION_FOLDER}" = "${SOURCES_FOLDER}" ]; then
    log ERROR "Source folder must be different from destination. SRC=${SOURCES_FOLDER}. DST=${DESTINATION_FOLDER}"
    return 1
  fi
  local START_TIME=
  START_TIME=$(date +%s)
  log INFO "##############################"
  log INFO "### Read lists from ${SOURCES_FOLDER}"
  log INFO "##############################"
  local SOURCE_FILE_LIST=
  local ACCUMULATED_ERRORS=0
  SOURCE_FILE_LIST=$(find "${SOURCES_FOLDER}" -type f | sort)
  for SOURCE_FILE in ${SOURCE_FILE_LIST}; do
    _download_from_single_source_file "${SOURCE_FILE}" "${DESTINATION_FOLDER}" "${POST_DOWNLOAD_CMD}"
    ACCUMULATED_ERRORS=$((ACCUMULATED_ERRORS + $?))
  done
  local DIR_SIZE=
  local TIME_ELAPSED=
  DIR_SIZE=$(du -h -d 0 "${DESTINATION_FOLDER}" | cut -f1)
  TIME_ELAPSED=$(time_elapsed_since "${START_TIME}")
  log INFO "##############################"
  log INFO "### Download done. Total size is ${DIR_SIZE}. Use ${TIME_ELAPSED}. ${ACCUMULATED_ERRORS} errors."
  log INFO "##############################"
}

# Usage ./this_script.sh <location_to_read_source_lists> [destination_folder]
# This script will download the contents of the lists to the destination folder.
# If no destination, then it saves results to the currernt folder.
if [ -n "${*}" ]; then
  download_lists "${@}"
fi

