#!/bin/sh

# This script is called after a lists refresh request has been sent to blocky.
myfunc() {
  echo "Post refresh command called."

  # Example: Send a cache flush request to blocky.
  # curl --silent --show-error -X POST http://blocky:4000/api/cache/flush

  return 0
}

myfunc "${@}"
