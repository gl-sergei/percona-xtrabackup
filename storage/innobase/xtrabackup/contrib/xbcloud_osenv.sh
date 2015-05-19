#!/bin/bash

# A script to apply the standard OpenStack OS_xxx environment variables to
# the xbcloud command line.
#
# Copyright Percona LLC and/or its affiliates, 2015.  All Rights Reserved.
#

# xbcloud options extracted from OS_xxx variables
#
XBCLOUD_OS_ENV=

# Add OS_xxx env vars to xbcloud options
#
# params: OpenStack OS_xxx environment variable, xbcloud parameter
#
add_os_env_opt() {
  if [ ! "$1" == "" ]; then
    XBCLOUD_OS_ENV="${XBCLOUD_OS_ENV} --$2=$1"
  fi
}

# Direct conversion of OS_xxx variables to xbcloud options
#
add_os_env_opt "${OS_USERNAME:-}" 'swift-user'
add_os_env_opt "${OS_PASSWORD:-}" 'swift-password'
add_os_env_opt "${OS_TENANT_NAME:-}" 'swift-tenant'
add_os_env_opt "${OS_TENANT_ID:-}" 'swift-tenant-id'
add_os_env_opt "${OS_REGION_NAME:-}" 'swift-region'
add_os_env_opt "${OS_CACERT:-}" 'cacert'

# split OS_AUTH_URL if found
#
if [ ! "${OS_AUTH_URL:-}" == "" ]; then
  OAU_BASE=$(echo "${OS_AUTH_URL}" | sed -rn 's/\/v([0-9\.]+)\/*/\//p')
  OAU_VER=$(echo "${OS_AUTH_URL}" | sed -rn 's/^.*\/v([0-9\.]+)\/*$/\1/p')
  add_os_env_opt "${OAU_BASE:-}" 'swift-url'
  add_os_env_opt "${OAU_VER:-}" 'swift-auth-version'
fi

# find the xbcloud binary
#
XBCLOUD_BIN="$(dirname "$0")/xbcloud"
#
# if it's not where this script is located
# then search path
#
if [ ! -e "${XBCLOUD_BIN}" ]; then
  XBCLOUD_BIN=
  hash xbcloud 2>/dev/null || {
    XBCLOUD_BIN='xbcloud'
  }
fi
if [ "${XBCLOUD_BIN}" == "" ]; then
  >&2 echo "ERROR: Could not find xbcloud binary."
  exit 1
fi

# make sure the storage mode is swift, if
# it's unspecified and we have OS_xxx values
# then set the storage mode to swift
if [ ! "${XBCLOUD_OS_ENV}" == "" ]; then
  for WARG in "$@"
  do
    case "${WARG}" in
      --storage*)
        STORAGE_MODE=$(echo "$1" | sed -e 's^[^=]*=//g')
        break
    esac
  done
  # if storage mode not specified then specify Swift
  if [ "${STORAGE_MODE}" == "" ]; then
    XBCLOUD_OS_ENV="--storage=Swift ${XBCLOUD_OS_ENV}"
  # if not swift then don't set the OS_xxx variables
  elif [ ! "${STORAGE_MODE:-}" == "Swift" ]; then
    XBCLOUD_OS_ENV=
  fi
fi

# do it
# shellcheck disable=SC2086,SC2048
${XBCLOUD_BIN} $* ${XBCLOUD_OS_ENV}

