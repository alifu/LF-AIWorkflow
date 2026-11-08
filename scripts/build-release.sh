#!/usr/bin/env bash
# Builds the Release app, ad-hoc signs it and packs the Homebrew cask zip (plan T9.1).
#   Usage: scripts/build-release.sh [version]
#   Default version: MARKETING_VERSION from the project.
# Output: build/release/LF-AIWorkflow-<version>.zip, plus its sha256 on stdout.
# No Developer ID and no notarization: the cask removes the quarantine flag on install (TD-002).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT}/LF-AIWorkflow.xcodeproj"
SCHEME="LF-AIWorkflow"
APP_NAME="LF-AIWorkflow.app"
RELEASE_DIR="${ROOT}/build/release"
ARCHIVE_PATH="${RELEASE_DIR}/LF-AIWorkflow.xcarchive"
ARCHIVE_LOG="${RELEASE_DIR}/archive.log"
APP_PATH="${RELEASE_DIR}/${APP_NAME}"
VERSION_PATTERN='^[0-9A-Za-z][0-9A-Za-z._-]*$'

# Prints MARKETING_VERSION for the Release configuration.
# Complexity: O(build settings) time, O(settings) space
read_marketing_version() {
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release -showBuildSettings \
        | awk -F' = ' '/^ *MARKETING_VERSION = / { print $2; exit }'
}

# Archives the Release configuration into ARCHIVE_PATH. On failure, prints the log tail and returns 1.
# Complexity: O(build) time, O(1) space in this script
archive_release() {
    echo "==> archive (log: ${ARCHIVE_LOG})"
    if xcodebuild archive -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
        -destination "generic/platform=macOS" -archivePath "${ARCHIVE_PATH}" >"${ARCHIVE_LOG}" 2>&1; then
        return 0
    fi
    echo "archive FAILED. Last lines of the log:"
    tail -40 "${ARCHIVE_LOG}" || true
    return 1
}

# Copies the .app out of the archive into APP_PATH, replacing any previous copy.
# Complexity: O(app size) time, O(app size) space
extract_app() {
    local source="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}"
    [[ -d "${source}" ]] || { echo "FAILED: ${APP_NAME} not found in archive: ${source}" >&2; return 1; }
    rm -rf "${APP_PATH}"
    ditto "${source}" "${APP_PATH}"
}

# Ad-hoc signs the app with the hardened runtime, keeping the archived entitlements
# (--preserve-metadata=entitlements; without it the re-signed app loses automation.apple-events).
# Complexity: O(app size) time, O(1) space
sign_adhoc() {
    codesign --force --deep --options runtime --preserve-metadata=entitlements -s - "${APP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
}

# Fails unless the signed app carries the Apple Events entitlement and the hardened runtime flag.
# Complexity: O(1) time, O(output) space
assert_signed_app() {
    local entitlements signature
    entitlements="$(codesign -d --entitlements - "${APP_PATH}" 2>&1)"
    signature="$(codesign -d --verbose=2 "${APP_PATH}" 2>&1)"
    if ! grep -q 'com.apple.security.automation.apple-events' <<<"${entitlements}"; then
        echo "FAILED: ${APP_PATH} is missing the com.apple.security.automation.apple-events entitlement (Safari automation would fail)." >&2
        return 1
    fi
    if ! grep -q 'flags=.*runtime' <<<"${signature}"; then
        echo "FAILED: ${APP_PATH} is not signed with the hardened runtime flag." >&2
        return 1
    fi
    echo "entitlements: automation.apple-events present"
    echo "runtime:      hardened runtime flag present"
}

# Zips the app with its top-level folder kept (the layout the cask expects) and prints the zip path and sha256.
# Complexity: O(app size) time, O(zip size) space
package_zip() {
    local zip_path="$1"
    local hash
    rm -f "${zip_path}"
    ditto -c -k --keepParent "${APP_PATH}" "${zip_path}"
    hash="$(shasum -a 256 "${zip_path}" | awk '{ print $1 }')"
    echo "zip:    ${zip_path}"
    echo "sha256: ${hash}"
    echo "cask:   sha256 \"${hash}\""
}

main() {
    local version="${1:-}"
    if [[ -z "${version}" ]]; then
        version="$(read_marketing_version)"
    fi
    if [[ ! "${version}" =~ ${VERSION_PATTERN} ]]; then
        echo "FAILED: invalid version '${version}' (allowed: letters, digits, '.', '_', '-')" >&2
        exit 1
    fi
    echo "==> release version ${version}"

    mkdir -p "${RELEASE_DIR}"
    rm -rf "${ARCHIVE_PATH}"
    archive_release
    extract_app
    echo "==> ad-hoc signing ${APP_PATH}"
    sign_adhoc
    echo "codesign verify: passed"
    assert_signed_app
    package_zip "${RELEASE_DIR}/LF-AIWorkflow-${version}.zip"
}

main "$@"
