#!/bin/sh

# The first argument will be the path to the downloaded file.
myfunc() {
  echo "Post download command called. ${1}";

  # strip leading whitespace
  sed -i -E 's/^[ \t]*//' "${1}";
  # fix non-unix newlines
  sed -i -E 's/\r$//' "${1}";

  # Comments:
  # fix "!comments" -> "# !comments"
  sed -i -E 's/^(!.*)$/# \1/' "${1}";
  # fix "//comments" -> "# //comments"
  sed -i -E 's/^(\/\/.*)$/# \1/' "${1}";
  # fix "=" -> "# =" 
  sed -i -E 's/^=$/# =/' "${1}";

  # fix "0.0.0.0abc.com" -> "abc.com"
  sed -i -E 's/^0\.0\.0\.0([^ ].*)$/\1/' "${1}";
  # fix "0 abc.com" -> "abc.com"
  sed -i -E 's/^0 (.*)$/\1/' "${1}";
  
  # Wild cards:
  # fix ".abc.com" -> "*.abc.com"
  sed -i -E 's/^\.(.*)$/*.\1/' "${1}";
  # fix "||abc.com^" -> "*.abc.com"
  sed -i -E 's/^\|\|(.*)\^$/*.\1/' "${1}";

  return 0;
}

myfunc "${@}"
