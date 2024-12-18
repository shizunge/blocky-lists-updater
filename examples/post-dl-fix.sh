#!/bin/sh

myfunc() {
  # fix "0.0.0.0abc.com" -> "0.0.0.0 abc.com"
  sed -i 's/^0\.0\.0\.0\([^ ].*\)/0.0.0.0 \1/' "${1}";
  # fix "0 abc.com" -> "0.0.0.0 abc.com"
  sed -i 's/^0 \(.*\)/0.0.0.0 \1/' "${1}";
  # fix "||abc.com^" -> "0.0.0.0 abc.com"
  sed -i 's/^||\(.*\)^$/0.0.0.0 \1/' "${1}";
  # fix "!comments" -> "# !comments"
  sed -i 's/^\(!.*\)$/# \1/' "${1}";
}

myfunc "${@}"
