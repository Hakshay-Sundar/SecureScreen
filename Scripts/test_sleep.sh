#!/bin/bash
# Tests that background processes continue uninterrupted while SecureScreen is locked.
# Run this AFTER SecureScreen.app is running with Accessibility permission.
set -e

LOG="/tmp/securescreen_test_$$.log"
DURATION=30

echo "Starting timestamp logger (PID will log every 1s to $LOG)..."
( while true; do date +%s >> "$LOG"; sleep 1; done ) &
LOGGER_PID=$!

echo "Log running. Lock SecureScreen NOW (⌥⇧L), wait ${DURATION}s, then unlock."
echo "Press ENTER when you have unlocked..."
read -r

kill "$LOGGER_PID" 2>/dev/null
wait "$LOGGER_PID" 2>/dev/null || true

echo "Analysing timestamps in $LOG..."

GAPS=0
PREV=""
while IFS= read -r ts; do
    if [ -n "$PREV" ]; then
        DIFF=$(( ts - PREV ))
        if [ "$DIFF" -gt 2 ]; then
            echo "GAP DETECTED: ${DIFF}s between $PREV and $ts"
            GAPS=$(( GAPS + 1 ))
        fi
    fi
    PREV="$ts"
done < "$LOG"

rm -f "$LOG"

if [ "$GAPS" -eq 0 ]; then
    echo "PASS — no gaps detected. Background tasks ran uninterrupted."
    exit 0
else
    echo "FAIL — $GAPS gap(s) detected. System may have slept."
    exit 1
fi
