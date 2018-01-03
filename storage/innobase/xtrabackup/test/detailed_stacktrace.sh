#!/bin/bash

# Reads stdin and attempts to locate and enhance stactrace generated by certain
# executable using the addr2linei (with -e path_to_binary address) or similar tool.
# addr2line is launched for each line with a stack trace, and 
# that could cause a significant slowdown.

# Arguments:
#    $1 - stacktrace address extraction re, must contain 2 extractions groups:
#        \1 is used to extract path to binary
#        \2 is used to extract address
#    $2 - addr2line arguments;
#    $3 [optional] - path to the addr2line or similar tool;

# Default is tailored towards what backtrace_symbols_fd() produces
# on Ubuntu for each stack frame:
# path_to_binary(mangled_name+hex_offset)[hex_address]
readonly address_re=${1:-'^(/[a-zA-Z\/0-9\._-]+).*\[(0x\w+)\]'}
readonly tool_arguments=${2:-'-fpiC'}
readonly tool=${3:-`which addr2line`}

while read line
do
  if [[ "${line}" =~ ${address_re} ]]; then
    binary="${BASH_REMATCH[1]}"
    addr="${BASH_REMATCH[2]}"

    result="$(${tool} $tool_arguments -e $binary $addr)"
    if [[ ! "$result" =~ ".*\?\?.*" ]]; then
      echo "$line ($result)"
      continue
    fi
  fi
  echo "$line"
done < /dev/stdin
