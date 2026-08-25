#!/bin/bash

set -euo pipefail

APP_PATH="/Applications/ABX Voice Assist.app"
AGENT_LABEL="com.abc.abxvoiceassist.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

/bin/launchctl bootout "gui/$UID/$AGENT_LABEL" >/dev/null 2>&1 || true
/usr/bin/pkill -x ABXVoiceAssist >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"

if [[ -w /Applications ]]; then
    rm -rf "$APP_PATH"
else
    sudo rm -rf "$APP_PATH"
fi

printf 'ABX Voice Assist удалён. История и локальная модель сохранены.\n'
