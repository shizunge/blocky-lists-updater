#!/bin/sh

deduplicate() {
  # Deduplicate: https://github.com/shizunge/blocky-lists-updater/issues/33
  local TMP=;
  TMP="$(mktemp)";
  awk '$0 in seen {next} {seen[$0]; print}' "${1}" > "${TMP}";
  local OLD_CNT NEW_CNT DIFF;
  OLD_CNT=$(wc -l < "${1}");
  NEW_CNT=$(wc -l < "${TMP}");
  DIFF=$(( OLD_CNT - NEW_CNT ));
  mv "${TMP}" "${1}" || return $?;
  echo "Deduplicated ${DIFF} lines in ${1}.";
}

# The first argument will be the path to the merged file.
myfunc() {
  echo "Post merging command called. ${1}";

  deduplicate "${1}" || return $?;

  return 0;
}

myfunc "${@}"
