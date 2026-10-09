#!/bin/bash
#
# SkillsPack installer.
#
#   curl -fsSL https://raw.githubusercontent.com/InsaneArts/SkillsPack/main/install.sh | bash
#
# Downloads the latest notarized release from GitHub, checks that Apple's notary service
# accepted it, copies SkillsPack.app into /Applications and launches it. Nothing is downloaded
# from anywhere but github.com/InsaneArts/SkillsPack, and nothing needs sudo.
#
#   --version 0.2.0   install that release instead of the latest
#   --no-launch       install without opening the app
#   --uninstall       remove the app (its data in ~/Library/Application Support/SkillsPack stays)

set -euo pipefail

REPO="InsaneArts/SkillsPack"
APP_NAME="SkillsPack"
BUNDLE_ID="dev.tgomareli.skillspack"
VERSION=""
LAUNCH=true
UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version=*) VERSION="${1#*=}"; shift ;;
    --no-launch) LAUNCH=false; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h|--help) awk 'NR >= 3 && /^#/ { sub(/^# ?/, ""); print } NR >= 3 && !/^#/ { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# /Applications when this user may write there, which an administrator can; ~/Applications
# otherwise. Either way no sudo.
if [[ -n "${SKILLSPACK_APP_DIR:-}" ]]; then APP_DIR="$SKILLSPACK_APP_DIR"   # for testing the installer
elif [[ -w /Applications ]]; then APP_DIR=/Applications
else APP_DIR="$HOME/Applications"; fi
DEST="$APP_DIR/$APP_NAME.app"

quit_app() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
  sleep 0.5
}

if $UNINSTALL; then
  say "Removing $APP_NAME"
  quit_app
  for dir in /Applications "$HOME/Applications"; do
    [[ -d "$dir/$APP_NAME.app" ]] && rm -rf "$dir/$APP_NAME.app" && echo "  removed $dir/$APP_NAME.app"
  done
  echo "  kept ~/Library/Application Support/SkillsPack (sources, backups); delete it for a clean slate"
  echo "  your agents' skills and settings were not touched"
  exit 0
fi

[[ "$(uname -s)" == "Darwin" ]] || fail "SkillsPack runs on macOS only"
[[ "$(uname -m)" == "arm64" ]] || fail "SkillsPack ships for Apple Silicon only"
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( OS_MAJOR >= 14 )) || fail "macOS 14 or newer is required (this Mac runs $(sw_vers -productVersion))"

if [[ -n "$VERSION" ]]; then
  URL="https://github.com/$REPO/releases/download/v${VERSION#v}/$APP_NAME.dmg"
else
  URL="https://github.com/$REPO/releases/latest/download/$APP_NAME.dmg"
fi

TMP="$(mktemp -d -t skillspack-install)"
MOUNT="$TMP/mnt"
cleanup() {
  [[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

say "Downloading $APP_NAME ${VERSION:-(latest)}"
curl -fL --progress-bar -o "$TMP/$APP_NAME.dmg" "$URL" || fail "download failed: $URL"

# The DMG is signed with the developer's Developer ID and notarized by Apple; Gatekeeper's own
# assessment is the check. A build that fails it is not installed.
if ! spctl -a -t open --context context:primary-signature "$TMP/$APP_NAME.dmg" >/dev/null 2>&1; then
  fail "Apple's notarization check rejected the download. Not installing. Please report this at https://github.com/$REPO/issues"
fi
echo "  notarization verified"

say "Installing to $APP_DIR"
mkdir -p "$MOUNT"
hdiutil attach "$TMP/$APP_NAME.dmg" -nobrowse -readonly -quiet -mountpoint "$MOUNT" || fail "could not mount the disk image"
[[ -d "$MOUNT/$APP_NAME.app" ]] || fail "the disk image holds no $APP_NAME.app"

if [[ -z "${SKILLSPACK_APP_DIR:-}" ]] && pgrep -x "$APP_NAME" >/dev/null 2>&1; then quit_app; fi
mkdir -p "$APP_DIR"
rm -rf "$DEST"
# ditto keeps the bundle's symlinks and signatures intact; cp -R can break the Sparkle framework.
ditto "$MOUNT/$APP_NAME.app" "$DEST"
hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
rmdir "$MOUNT" 2>/dev/null || true
echo "  $DEST"

if $LAUNCH; then
  say "Launching"
  open "$DEST"
  echo "  SkillsPack lives in the menu bar: look for the box icon."
fi
say "Done"
