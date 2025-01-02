#!/bin/sh

# The first argument will be the path to the merged file.
myfunc() {
  echo "Post merging command called."
  return 0;
}

myfunc "${@}"
