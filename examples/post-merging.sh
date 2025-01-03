#!/bin/sh

# The first argument will be the path to the merged file.
myfunc() {
  echo "Post merging command called. ${1}";

  local TMP=$(mktemp);
  # Deduplicate: https://github.com/shizunge/blocky-lists-updater/issues/33
  awk '$0 in seen {next} {seen[$0]; print}' "${1}" > "${TMP}";
  mv "${TMP}" "${1}";

  return 0;
}

myfunc "${@}"
