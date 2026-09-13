#!/bin/bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
PROJECT_PATH="${PROJECT_ROOT}/AITutorMac/AITutorMac.xcodeproj"

debug_settings="$(
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme AITutorMac \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings
)"
release_settings="$(
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme AITutorMac \
    -configuration Release \
    -destination 'platform=macOS' \
    -showBuildSettings
)"

setting_value() {
  local settings="$1"
  local key="$2"
  printf '%s\n' "${settings}" | awk -F ' = ' -v key="${key}" \
    '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

assert_setting() {
  local settings="$1"
  local configuration="$2"
  local key="$3"
  local expected="$4"
  local actual
  actual="$(setting_value "${settings}" "${key}")"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "${configuration} ${key}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

assert_setting "${debug_settings}" Debug PRODUCT_BUNDLE_IDENTIFIER \
  com.baihuaai.AITutorMac.debug
assert_setting "${debug_settings}" Debug AITUTOR_APP_DISPLAY_NAME \
  'AITutorMac Debug'
assert_setting "${debug_settings}" Debug AITUTOR_APP_BUNDLE_NAME \
  'AITutorMac Debug'
assert_setting "${release_settings}" Release PRODUCT_BUNDLE_IDENTIFIER \
  com.baihuaai.AITutorMac
assert_setting "${release_settings}" Release AITUTOR_APP_DISPLAY_NAME \
  '花花老师'
assert_setting "${release_settings}" Release AITUTOR_APP_BUNDLE_NAME '花花老师'
assert_setting "${debug_settings}" Debug PRODUCT_NAME AITutorMac
assert_setting "${debug_settings}" Debug EXECUTABLE_NAME AITutorMac
assert_setting "${debug_settings}" Debug PRODUCT_MODULE_NAME AITutorMac
assert_setting "${release_settings}" Release PRODUCT_NAME '花花老师'
assert_setting "${release_settings}" Release EXECUTABLE_NAME AITutorMac
assert_setting "${release_settings}" Release PRODUCT_MODULE_NAME AITutorMac
assert_setting "${debug_settings}" Debug ASSETCATALOG_COMPILER_APPICON_NAME AppIcon
assert_setting "${release_settings}" Release ASSETCATALOG_COMPILER_APPICON_NAME AppIcon

for settings_and_name in debug release; do
  if [[ "${settings_and_name}" == debug ]]; then
    selected_settings="${debug_settings}"
    configuration=Debug
  else
    selected_settings="${release_settings}"
    configuration=Release
  fi

  assert_setting "${selected_settings}" "${configuration}" CODE_SIGN_ENTITLEMENTS \
    AITutorMac/AITutorMac.entitlements
  assert_setting "${selected_settings}" "${configuration}" CODE_SIGN_IDENTITY -
  assert_setting "${selected_settings}" "${configuration}" CODE_SIGN_STYLE Automatic
  assert_setting "${selected_settings}" "${configuration}" DEVELOPMENT_TEAM ''
done

echo "App identity configuration is valid."
