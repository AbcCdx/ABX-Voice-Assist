#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/Applications/ABX Voice Assist.app"
AGENT_LABEL="com.abc.abxvoiceassist.agent"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abxvoiceassist-local-install.XXXXXX")"
STAGED_APP="$WORK_DIR/ABX Voice Assist.app"
INCOMING="/Applications/.ABX-Voice-Assist.incoming.$$"
BACKUP="/Applications/.ABX-Voice-Assist.previous.$$"

cleanup() {
    rm -rf "$WORK_DIR" "$INCOMING"
}
trap cleanup EXIT

identity="${ABX_VOICE_ASSIST_SIGN_IDENTITY:-}"
if [[ -z "$identity" && -d "$APP_PATH" ]]; then
    identity="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
        | sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' \
        | head -n 1)"
fi
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi
if [[ -z "$identity" ]]; then
    printf 'ABX Voice Assist: no Apple Development signing identity was found.\n' >&2
    printf 'Set ABX_VOICE_ASSIST_SIGN_IDENTITY explicitly; ad-hoc local installs are disabled because they reset macOS permissions.\n' >&2
    exit 1
fi

SIGN_IDENTITY="$identity" "$ROOT_DIR/scripts/build-app.sh" "$STAGED_APP"

codesign --verify --deep --strict "$STAGED_APP"
identifier="$(codesign -d --verbose=4 "$STAGED_APP" 2>&1 \
    | sed -n 's/^Identifier=//p')"
[[ "$identifier" == "com.abc.abxvoiceassist" ]] || {
    printf 'ABX Voice Assist: unexpected bundle identifier: %s\n' "$identifier" >&2
    exit 1
}
if [[ -d "$APP_PATH" ]]; then
    installed_requirement="$(codesign -d -r- "$APP_PATH" 2>&1 | tail -n 1)"
    staged_requirement="$(codesign -d -r- "$STAGED_APP" 2>&1 | tail -n 1)"
    [[ "$installed_requirement" == "$staged_requirement" || "$identity" == "-" ]] || {
        printf 'ABX Voice Assist: refusing to change the installed signing identity because that would reset macOS permissions.\n' >&2
        exit 1
    }
    if [[ "$identity" == "-" && "$installed_requirement" != "$staged_requirement" ]]; then
        printf 'ABX Voice Assist: replacing the installed app with the explicitly requested ad-hoc signature.\n'
    fi
fi

uid="$(id -u)"

ditto "$STAGED_APP" "$INCOMING"
codesign --verify --deep --strict "$INCOMING"

if [[ -e "$APP_PATH" ]]; then
    mv "$APP_PATH" "$BACKUP"
fi
if ! mv "$INCOMING" "$APP_PATH"; then
    if [[ -e "$BACKUP" ]]; then
        mv "$BACKUP" "$APP_PATH"
    fi
    exit 1
fi
rm -rf "$BACKUP"

agent_plist="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
if [[ -f "$agent_plist" ]]; then
    pkill -f '/Applications/ABX Voice Assist.app/Contents/MacOS/ABXVoiceAssist' >/dev/null 2>&1 || true
    if ! launchctl print "gui/$uid/$AGENT_LABEL" >/dev/null 2>&1; then
        launchctl bootstrap "gui/$uid" "$agent_plist" >/dev/null 2>&1 || true
    fi
    launchctl kickstart -k "gui/$uid/$AGENT_LABEL" >/dev/null 2>&1 || true
fi

printf 'ABX Voice Assist: installed one signed app at %s and restarted the background agent.\n' "$APP_PATH"
