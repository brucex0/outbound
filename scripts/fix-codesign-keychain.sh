#!/usr/bin/env bash

set -euo pipefail

readonly OUTBOUND_LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

cleanup() {
  unset OUTBOUND_KEYCHAIN_PASSWORD
}
trap cleanup EXIT INT TERM

read -r -s -p "Mac login password: " OUTBOUND_KEYCHAIN_PASSWORD
printf '\n'

security unlock-keychain \
  -p "${OUTBOUND_KEYCHAIN_PASSWORD}" \
  "${OUTBOUND_LOGIN_KEYCHAIN}"

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "${OUTBOUND_KEYCHAIN_PASSWORD}" \
  "${OUTBOUND_LOGIN_KEYCHAIN}"

printf 'Updated codesign access for the login keychain.\n'
