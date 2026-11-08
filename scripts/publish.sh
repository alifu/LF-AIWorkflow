#!/usr/bin/env bash
# Publishes a release: pushes HEAD to origin/main, tags v<version>, creates the GitHub release
# with the zip from scripts/build-release.sh and, with --update-tap, updates the Homebrew cask.
#   Usage: scripts/publish.sh [--dry-run] [--yes] [--update-tap] [version]
#   Default version: MARKETING_VERSION from the project.
# Never force-pushes. --dry-run runs the read-only checks and the build, then prints every
# write command instead of running it. Without --update-tap, the tap steps are printed for manual use.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Every git/gh call below must act on this repo, whatever the caller's working directory was.
cd "${ROOT}"
PROJECT="${ROOT}/LF-AIWorkflow.xcodeproj"
SCHEME="LF-AIWorkflow"
RELEASE_DIR="${ROOT}/build/release"
CASK_TEMPLATE="${ROOT}/homebrew/lf-aiworkflow.rb"
REMOTE="origin"
MAIN_BRANCH="main"
TAP_REPO="alifu/homebrew-tap"
TAP_CASK="Casks/lf-aiworkflow.rb"
VERSION_PATTERN='^[0-9A-Za-z][0-9A-Za-z._-]*$'
SHA_PATTERN='^[0-9a-f]{64}$'
CONFIRM_TTY="/dev/tty"

DRY_RUN=0
ASSUME_YES=0
UPDATE_TAP=0
VERSION=""
ZIP=""
SHA256=""
NOTES_FILE=""
TAP_DIR=""
# Last completed write step: nothing | main | tag | tag-push | release
LAST_DONE="nothing"

# Prints the error to stderr and exits 1.
# Complexity: O(message) time, O(1) space
die() {
    echo "FAILED: $*" >&2
    exit 1
}

# Prints a human label for LAST_DONE, used in the failure message.
# Complexity: O(1) time, O(1) space
step_label() {
    case "${LAST_DONE}" in
        main) echo "pushed ${MAIN_BRANCH}" ;;
        tag) echo "created tag v${VERSION}" ;;
        tag-push) echo "pushed tag v${VERSION}" ;;
        release) echo "GitHub release v${VERSION}" ;;
        *) echo "nothing" ;;
    esac
}

# Prints the exact commands that finish a publish stopped after LAST_DONE. Nothing is run here.
# Complexity: O(1) time, O(1) space
print_recovery() {
    local commit
    commit="$(git rev-parse HEAD 2>/dev/null || echo "<commit>")"
    echo "==> finish by hand (state: $(step_label))"
    if [[ "${LAST_DONE}" == "main" ]]; then
        echo "    git tag -a v${VERSION} -m \"LF-AIWorkflow ${VERSION}\" ${commit}"
    fi
    if [[ "${LAST_DONE}" == "main" || "${LAST_DONE}" == "tag" ]]; then
        echo "    git push ${REMOTE} refs/tags/v${VERSION}"
    fi
    if [[ "${LAST_DONE}" != "release" ]]; then
        echo "    gh release create v${VERSION} ${ZIP} --verify-tag --title \"LF-AIWorkflow ${VERSION}\" --notes-file ${NOTES_FILE}"
    fi
    print_manual_tap_steps
}

# Removes temp files and, on a failure after a remote write, prints the recovery commands.
# Release notes are kept in that case because the recovery commands reference them.
# Complexity: O(1) time, O(1) space
cleanup() {
    local status=$?
    [[ -z "${TAP_DIR}" ]] || rm -rf "${TAP_DIR}"
    if [[ "${status}" -ne 0 && "${LAST_DONE}" != "nothing" && "${DRY_RUN}" != "1" ]]; then
        echo "Stopped (exit ${status}). Last completed step: $(step_label). Nothing was rolled back." >&2
        print_recovery >&2
        echo "Release notes kept for the commands above: ${NOTES_FILE}" >&2
    else
        [[ -z "${NOTES_FILE}" ]] || rm -f "${NOTES_FILE}"
    fi
    exit "${status}"
}
trap cleanup EXIT

# Sets the flags and the optional version from the command line.
# Complexity: O(args) time, O(1) space
parse_args() {
    local arg
    for arg in "$@"; do
        case "${arg}" in
            --dry-run) DRY_RUN=1 ;;
            --yes) ASSUME_YES=1 ;;
            --update-tap) UPDATE_TAP=1 ;;
            -h | --help)
                echo "Usage: scripts/publish.sh [--dry-run] [--yes] [--update-tap] [version]"
                exit 0
                ;;
            -*) die "unknown option '${arg}'" ;;
            *)
                [[ -z "${VERSION}" ]] || die "more than one version given"
                VERSION="${arg}"
                ;;
        esac
    done
}

# Prints MARKETING_VERSION for the Release configuration.
# Complexity: O(build settings) time, O(settings) space
read_marketing_version() {
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release -showBuildSettings \
        | awk -F' = ' '/^ *MARKETING_VERSION = / { print $2; exit }'
}

# Runs a write command, or prints it instead when DRY_RUN=1. Every git/gh write goes through here.
# Complexity: O(command) time, O(1) space
run() {
    if [[ "${DRY_RUN}" == "1" ]]; then
        local line
        printf -v line '%q ' "$@"
        echo "[dry-run] ${line% }"
        return 0
    fi
    "$@"
}

# Fails unless gh is logged in.
# Complexity: O(1) time, O(1) space
check_gh_auth() {
    gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
    echo "ok: gh is logged in"
}

# Fails unless the working tree is clean (untracked files included). Only a warning under --dry-run.
# Complexity: O(changed files) time, O(changed files) space
check_clean_tree() {
    local changes
    changes="$(git status --porcelain)"
    if [[ -z "${changes}" ]]; then
        echo "ok: working tree is clean"
        return 0
    fi
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo "WARNING (dry-run only): working tree is not clean; a real publish would stop here:"
        echo "${changes}"
        return 0
    fi
    die "working tree is not clean; commit or stash first:"$'\n'"${changes}"
}

# Fails unless HEAD contains origin/main, so the push is a fast-forward and main is never rewritten.
# Complexity: O(history) time, O(1) space
check_fast_forward() {
    git merge-base --is-ancestor "${REMOTE}/${MAIN_BRANCH}" HEAD \
        || die "HEAD is not a fast-forward of ${REMOTE}/${MAIN_BRANCH}; merge or rebase onto it first (main is never rewritten)"
    echo "ok: HEAD contains ${REMOTE}/${MAIN_BRANCH}"
}

# Fails if tag v<version> exists locally or on the remote.
# Complexity: O(refs) time, O(refs) space
check_tag_free() {
    local tag="v${VERSION}" remote_tag
    if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
        die "tag ${tag} already exists locally"
    fi
    remote_tag="$(git ls-remote --tags "${REMOTE}" "refs/tags/${tag}")"
    [[ -z "${remote_tag}" ]] || die "tag ${tag} already exists on ${REMOTE}"
    echo "ok: tag ${tag} is free locally and on ${REMOTE}"
}

# Fails unless the cask template has exactly one version line and one sha256 line to substitute.
# Complexity: O(template lines) time, O(1) space
check_cask_template() {
    local versions sha_lines
    versions="$(grep -c '^  version "' "${CASK_TEMPLATE}" || true)"
    sha_lines="$(grep -c '^  sha256 "' "${CASK_TEMPLATE}" || true)"
    [[ "${versions}" == "1" && "${sha_lines}" == "1" ]] \
        || die "${CASK_TEMPLATE} needs exactly one version line and one sha256 line"
    echo "ok: cask template has one version and one sha256 line"
}

# Builds the Release zip with scripts/build-release.sh and reads its sha256 here.
# Complexity: O(app size) time, O(zip size) space
build_release() {
    "${ROOT}/scripts/build-release.sh" "${VERSION}"
    ZIP="${RELEASE_DIR}/LF-AIWorkflow-${VERSION}.zip"
    [[ -f "${ZIP}" ]] || die "zip not found after build: ${ZIP}"
    SHA256="$(shasum -a 256 "${ZIP}" | awk '{ print $1 }')"
    [[ "${SHA256}" =~ ${SHA_PATTERN} ]] || die "could not read a sha256 from ${ZIP}"
}

# Writes the GitHub release notes to a temp file (NOTES_FILE).
# Complexity: O(1) time, O(1) space
write_notes() {
    NOTES_FILE="$(mktemp)"
    cat >"${NOTES_FILE}" <<EOF
## Install

\`\`\`bash
brew tap alifu/tap
brew install --cask alifu/tap/lf-aiworkflow
\`\`\`

SHA-256 of \`LF-AIWorkflow-${VERSION}.zip\`:

\`${SHA256}\`

The app is ad-hoc signed and not notarized. The cask removes the quarantine flag on install.
If you download the zip in a browser instead, macOS quarantines the app; run this once:

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/LF-AIWorkflow.app
\`\`\`
EOF
}

# Prints what the publish will do. Nothing is written here.
# Complexity: O(commits to push) time, O(commits) space
print_plan() {
    local commits tap_line
    commits="$(git log --oneline "${REMOTE}/${MAIN_BRANCH}..HEAD")"
    if [[ "${UPDATE_TAP}" == "1" ]]; then
        tap_line="update ${TAP_REPO} ${TAP_CASK} (--update-tap)"
    else
        tap_line="manual (printed after the release)"
    fi
    echo "==> publish plan"
    echo "    commit:  $(git rev-parse HEAD)"
    echo "    version: ${VERSION} (tag v${VERSION})"
    echo "    zip:     ${ZIP}"
    echo "    sha256:  ${SHA256}"
    echo "    push:    ${REMOTE}/${MAIN_BRANCH} <- HEAD, commits:"
    if [[ -n "${commits}" ]]; then
        echo "${commits}" | sed 's/^/             /'
    else
        echo "             (none: ${MAIN_BRANCH} already at HEAD)"
    fi
    echo "    release: v${VERSION} with the zip, notes from ${NOTES_FILE}"
    echo "    tap:     ${tap_line}"
}

# Asks for confirmation unless --yes or --dry-run. The answer is read from /dev/tty, never stdin.
# Default is No: anything but "y" aborts. Aborts when /dev/tty is unavailable.
# Complexity: O(1) time, O(1) space
confirm_publish() {
    if [[ "${DRY_RUN}" == "1" || "${ASSUME_YES}" == "1" ]]; then
        return 0
    fi
    { : <"${CONFIRM_TTY}"; } 2>/dev/null \
        || die "no terminal at ${CONFIRM_TTY} to confirm on; rerun with --yes to publish without a prompt"
    local answer=""
    read -r -p "Publish? [y/N] " answer <"${CONFIRM_TTY}" || answer=""
    if [[ "${answer}" != "y" ]]; then
        echo "Aborted; nothing was published."
        exit 1
    fi
}

# Creates the GitHub release for the tag, with the zip attached.
# Complexity: O(zip size) time, O(1) space in this script
create_release() {
    run gh release create "v${VERSION}" "${ZIP}" --verify-tag \
        --title "LF-AIWorkflow ${VERSION}" --notes-file "${NOTES_FILE}"
    LAST_DONE="release"
}

# Prints the cask from the template with the real version and sha256 into the file given as $1.
# Complexity: O(template lines) time, O(template lines) space
render_cask() {
    local target="$1"
    awk -v version="${VERSION}" -v sha="${SHA256}" '
        /^  version "/ { print "  version \"" version "\""; next }
        /^  sha256 "/ { print "  sha256 \"" sha "\""; next }
        { print }
    ' "${CASK_TEMPLATE}" >"${target}"
    grep -Fxq "  sha256 \"${SHA256}\"" "${target}" || die "rendered cask has no sha256 line for ${SHA256}"
}

# Clones the tap, writes the cask, and commits and pushes it to the tap's default branch.
# If the cask is already identical, skips the commit and push. Under --dry-run the clone,
# commit and push are printed, not run. A failure here leaves the release out; the caller prints the manual steps.
# Complexity: O(template lines) time, O(1) space in this script
update_tap() {
    local repo branch="<default-branch>"
    TAP_DIR="$(mktemp -d)"
    repo="${TAP_DIR}/homebrew-tap"
    run gh repo clone "${TAP_REPO}" "${repo}"
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo "[dry-run] write ${TAP_CASK} from ${CASK_TEMPLATE} (version ${VERSION}, sha256 ${SHA256})"
    else
        branch="$(git -C "${repo}" symbolic-ref --short HEAD)"
        mkdir -p "$(dirname "${repo}/${TAP_CASK}")"
        render_cask "${repo}/${TAP_CASK}"
    fi
    run git -C "${repo}" add "${TAP_CASK}"
    if [[ "${DRY_RUN}" != "1" ]] && git -C "${repo}" diff --cached --quiet; then
        echo "==> tap already has ${TAP_CASK} at version ${VERSION}; no commit or push needed"
        return 0
    fi
    run git -C "${repo}" commit -m "lf-aiworkflow ${VERSION}"
    run git -C "${repo}" push origin "HEAD:refs/heads/${branch}"
}

# Prints the tap steps for a manual update (used when --update-tap is not given, or after a tap failure).
# Complexity: O(1) time, O(1) space
print_manual_tap_steps() {
    cat <<EOF
==> tap not updated. Manual steps:
    gh repo clone ${TAP_REPO} <dir>
    in <dir>/${TAP_CASK}, set: version "${VERSION}" and sha256 "${SHA256}"
    git -C <dir> commit -am "lf-aiworkflow ${VERSION}" && git -C <dir> push
EOF
}

main() {
    parse_args "$@"
    if [[ -z "${VERSION}" ]]; then
        VERSION="$(read_marketing_version)"
    fi
    [[ "${VERSION}" =~ ${VERSION_PATTERN} ]] \
        || die "invalid version '${VERSION}' (allowed: letters, digits, '.', '_', '-')"

    echo "==> preflight for ${VERSION}$([[ "${DRY_RUN}" == "1" ]] && echo " (dry-run)")"
    check_gh_auth
    check_clean_tree
    git fetch "${REMOTE}"
    check_fast_forward
    check_tag_free
    check_cask_template

    echo "==> build"
    build_release
    write_notes
    print_plan
    confirm_publish

    echo "==> publish"
    run git push "${REMOTE}" "HEAD:refs/heads/${MAIN_BRANCH}"
    LAST_DONE="main"
    run git tag -a "v${VERSION}" -m "LF-AIWorkflow ${VERSION}" HEAD
    LAST_DONE="tag"
    run git push "${REMOTE}" "refs/tags/v${VERSION}"
    LAST_DONE="tag-push"
    create_release
    if [[ "${UPDATE_TAP}" == "1" ]]; then
        update_tap
    else
        print_manual_tap_steps
    fi

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo "==> dry-run: nothing was pushed, tagged, released or updated"
    else
        echo "==> published v${VERSION}"
    fi
}

main "$@"
