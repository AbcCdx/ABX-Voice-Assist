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
allow_signing_migration="${ABX_VOICE_ASSIST_ALLOW_SIGNING_MIGRATION:-0}"
if [[ "$identity" == "-" ]]; then
    printf 'ABX Voice Assist: ad-hoc local installation is disabled because it resets macOS permissions.\n' >&2
    exit 1
fi
valid_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -z "$identity" && -d "$APP_PATH" ]]; then
    installed_identity="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
        | sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' \
        | head -n 1)"
    if [[ -n "$installed_identity" && "$valid_identities" == *\"$installed_identity\"* ]]; then
        identity="$installed_identity"
    fi
fi
if [[ -z "$identity" ]]; then
    identity="$(printf '%s\n' "$valid_identities" \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi
if [[ -z "$identity" ]]; then
    printf 'ABX Voice Assist: no Apple Development signing identity was found.\n' >&2
    printf 'Set ABX_VOICE_ASSIST_SIGN_IDENTITY explicitly; ad-hoc local installs are disabled because they reset macOS permissions.\n' >&2
    exit 1
fi

certificate_subject="$(security find-certificate -c "$identity" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null || true)"
team_identifier="$(printf '%s\n' "$certificate_subject" \
    | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
[[ "$team_identifier" =~ ^[A-Z0-9]{10}$ ]] || {
    printf 'ABX Voice Assist: could not determine the Apple Development Team ID.\n' >&2
    exit 1
}
sign_requirement="=designated => identifier \"com.abc.abxvoiceassist\" and anchor apple generic and certificate leaf[subject.OU] = \"$team_identifier\""

SIGN_IDENTITY="$identity" SIGN_REQUIREMENT="$sign_requirement" \
    "$ROOT_DIR/scripts/build-app.sh" "$STAGED_APP"

codesign --verify --deep --strict "$STAGED_APP"
identifier="$(codesign -d --verbose=4 "$STAGED_APP" 2>&1 \
    | sed -n 's/^Identifier=//p')"
[[ "$identifier" == "com.abc.abxvoiceassist" ]] || {
    printf 'ABX Voice Assist: unexpected bundle identifier: %s\n' "$identifier" >&2
    exit 1
}
staged_team_identifier="$(codesign -d --verbose=4 "$STAGED_APP" 2>&1 \
    | sed -n 's/^TeamIdentifier=//p')"
[[ "$staged_team_identifier" == "$team_identifier" ]] || {
    printf 'ABX Voice Assist: staged Team ID does not match the signing certificate.\n' >&2
    exit 1
}
if [[ -d "$APP_PATH" ]]; then
    installed_requirement="$(codesign -d -r- "$APP_PATH" 2>&1 | tail -n 1)"
    staged_requirement="$(codesign -d -r- "$STAGED_APP" 2>&1 | tail -n 1)"
    installed_signature="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
        | sed -n 's/^Signature=//p' \
        | head -n 1)"
    migration_is_allowed=false
    if [[ "$allow_signing_migration" == "1" && "$installed_signature" == "adhoc" ]]; then
        migration_is_allowed=true
    fi
    [[ "$installed_requirement" == "$staged_requirement" || "$migration_is_allowed" == true ]] || {
        printf 'ABX Voice Assist: refusing to change the installed signing identity because that would reset macOS permissions.\n' >&2
        exit 1
    }
    if [[ "$migration_is_allowed" == true && "$installed_requirement" != "$staged_requirement" ]]; then
        printf 'ABX Voice Assist: performing the one-time migration from ad-hoc to Apple Development signing.\n'
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

# Catch expired or otherwise unusable identities after the final replacement,
# not only while the staged bundle still exists.
codesign --verify --deep --strict "$APP_PATH"

printf 'ABX Voice Assist: installed one signed app at %s and restarted the background agent.\n' "$APP_PATH"
