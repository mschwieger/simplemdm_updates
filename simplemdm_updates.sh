#!/bin/bash
#
# SimpleMDM Script
# Version: 2.2.0
#
# MIT License
# Copyright (c) 2024 Your Name Here
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# Changelog:
# - 2024-06-11: Initial version
# - 2024-06-12: Healthchecks integration, .env sourcing, and logic improvements
# - 2024-06-12: Internet and API connectivity checks, randomized sleep, and --nosleep
# - 2024-06-12: Email log via Postmark API
# - 2024-06-12: Names and IDs for devices, device groups, assignment groups in output
# - 2024-06-12: "next" message prints without leading dot
# - 2024-06-12: Sleep and healthcheck start moved outside main; timestamps added

SCRIPT_VERSION="2.2.0"

# --- Argument Parsing ---
NOSLEEP=0
for arg in "$@"; do
    case "$arg" in
        --nosleep) NOSLEEP=1 ;;
    esac
done

OUT_LOG=$(mktemp)
cleanup() { rm -f "$OUT_LOG"; }
trap cleanup EXIT

# --- SOURCE .env AT THE TOP (IMMEDIATELY) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    set -o allexport
    source "$SCRIPT_DIR/.env"
    set +o allexport
else
    echo "Warning: .env file not found in $SCRIPT_DIR."
fi

send_log_email() {
    local log_file="$1"
    local subject="${POSTMARK_SUBJECT:-SimpleMDM Script Output}"
    local from="$POSTMARK_FROM"
    local to="$POSTMARK_TO"
    local api_key="$POSTMARK_API_KEY"
    local log_body

    if [[ -z "$api_key" || -z "$from" || -z "$to" ]]; then
        echo "Warning: Postmark API vars not set, cannot email log."
        return
    fi

    log_body=$(<"$log_file")

    curl -sS \
        -X POST "https://api.postmarkapp.com/email" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "X-Postmark-Server-Token: $api_key" \
        -d @- <<EOF
{
    "From": "$from",
    "To": "$to",
    "Subject": "$subject",
    "TextBody": $(printf '%s' "$log_body" | jq -Rs .)
}
EOF
}

get_device_name_and_id() {
    local device_id="$1"
    local device_name
    device_name=$(curl -s "https://a.simplemdm.com/api/v1/devices/$device_id" -u "$API_KEY:" | jq -r '.data.attributes.name // empty')
    if [[ -z "$device_name" ]]; then
        device_name="Unknown Device"
    fi
    echo "$device_name ($device_id)"
}

get_devicegroup_name_and_id() {
    local group_id="$1"
    local group_name
    group_name=$(curl -s "https://a.simplemdm.com/api/v1/device_groups/$group_id" -u "$API_KEY:" | jq -r '.data.attributes.name // empty')
    if [[ -z "$group_name" ]]; then
        group_name="Unknown Device Group"
    fi
    echo "$group_name ($group_id)"
}

get_assignmentgroup_name_and_id() {
    local group_id="$1"
    local group_name
    group_name=$(curl -s "https://a.simplemdm.com/api/v1/assignment_groups/$group_id" -u "$API_KEY:" | jq -r '.data.attributes.name // empty')
    if [[ -z "$group_name" ]]; then
        group_name="Unknown Assignment Group"
    fi
    echo "$group_name ($group_id)"
}

main() {

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Main function execution begins"
    echo "Running SimpleMDM script, version $SCRIPT_VERSION"

    if [[ -z "$API_KEY" ]]; then
        echo "Error: API_KEY not set in .env!"
        exit 1
    fi
    if [[ -z "$HEALTHCHECKS_URL" ]]; then
        echo "Error: HEALTHCHECKS_URL not set in .env!"
        exit 1
    fi

    internet_check() { curl -sSf https://google.com > /dev/null; }

    echo "Checking general internet connectivity..."
    if ! internet_check; then
        echo "Warning: No general internet connection. Will retry in 30 minutes."
        sleep 1800
        echo "Retrying general internet connectivity..."
        if ! internet_check; then
            echo "Error: No general internet connection after retry. Exiting."
            exit 1
        fi
    fi
    echo "General internet connectivity: OK"

    echo "Checking SimpleMDM API connectivity..."
    if ! curl -sSf "https://a.simplemdm.com/api/v1/device_groups/?limit=1" -u "$API_KEY:" > /dev/null; then
        echo "Error: Cannot reach or authenticate with SimpleMDM API. Exiting."
        exit 1
    fi
    echo "SimpleMDM API connectivity: OK"

    get_devicegroups() {
        curl -s "https://a.simplemdm.com/api/v1/device_groups/?limit=100" \
            -u "$API_KEY:" | jq -r '.data[].id'
    }

    get_assignmentgroups() {
        curl -s "https://a.simplemdm.com/api/v1/assignment_groups/?limit=100" \
            -u "$API_KEY:" | jq -r '.data[].id'
    }

    update_device() {
        local device="$1"
        curl -s "https://a.simplemdm.com/api/v1/devices/$device/push_apps" \
            -u "$API_KEY:" -X POST
    }

    refresh_inventory() {
        local device="$1"
        curl -s "https://a.simplemdm.com/api/v1/devices/$device/refresh" \
            -u "$API_KEY:" -X POST
    }

    push_apps() {
        local groupid="$1"
        curl -s "https://a.simplemdm.com/api/v1/assignment_groups/$groupid/push_apps" \
            -u "$API_KEY:" -X POST
    }

    update_apps() {
        local groupid="$1"
        curl -s "https://a.simplemdm.com/api/v1/assignment_groups/$groupid/update_apps" \
            -u "$API_KEY:" -X POST
    }

    echo 'Executing'

    # Assignment groups (names and IDs)
    get_assignmentgroups | while read -r groupid; do
        [[ -z "$groupid" ]] && continue
        group_desc=$(get_assignmentgroup_name_and_id "$groupid")
        echo "Assignment Group: $group_desc"
        DEVICES=$(curl -s "https://a.simplemdm.com/api/v1/assignment_groups/$groupid" \
            -u "$API_KEY:" | jq -r '.data.relationships.devices.data[].id')
        for device in $DEVICES; do
            [[ -z "$device" ]] && continue
            device_desc=$(get_device_name_and_id "$device")
            echo "  Assignment group device: $device_desc"
        done
        push_apps "$groupid"
        echo -n "pushing."
        sleep 3
        update_apps "$groupid"
        echo -n "updating."
        sleep 3
        echo "next"
    done

    # Device groups (names and IDs)
    get_devicegroups | while read -r devicegroup; do
        [[ -z "$devicegroup" ]] && continue
        devicegroup_desc=$(get_devicegroup_name_and_id "$devicegroup")
        echo "Devicegroup: $devicegroup_desc"
        DEVICES=$(curl -s "https://a.simplemdm.com/api/v1/device_groups/$devicegroup" \
            -u "$API_KEY:" | jq -r '.data.relationships[].data[].id')
        for device in $DEVICES; do
            [[ -z "$device" ]] && continue
            device_desc=$(get_device_name_and_id "$device")
            echo -n "Updating $device_desc "
            update_device "$device"
            echo -n "."
            sleep 3
            echo "."
        done
        for device in $DEVICES; do
            [[ -z "$device" ]] && continue
            device_desc=$(get_device_name_and_id "$device")
            echo -n "Refreshing $device_desc "
            refresh_inventory "$device"
            echo -n "."
            sleep 1
            echo "."
        done
        echo "next"
    done

} # End of main()

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script started"

# SLEEP cycle before running main
if [[ "$NOSLEEP" -eq 0 ]]; then
    SLEEP=$(( RANDOM % 14400 ))
    echo "Sleeping for $SLEEP seconds before starting main logic..."
    sleep "$SLEEP"
else
    echo "NOSLEEP mode enabled: skipping sleep cycle."
fi

# Healthchecks start ping (no output/log attached)
if [[ -n "$HEALTHCHECKS_URL" ]]; then
    curl -fsS --retry 3 "${HEALTHCHECKS_URL}/start" > /dev/null
else
    echo "Warning: HEALTHCHECKS_URL is not set. Skipping Healthchecks.io start ping."
fi

main 2>&1 | tee "$OUT_LOG"
SCRIPT_STATUS=${PIPESTATUS[0]}

send_log_email "$OUT_LOG"

if [[ -z "$HEALTHCHECKS_URL" ]]; then
    echo "Warning: HEALTHCHECKS_URL is not set. Skipping Healthchecks.io ping."
else
    if [ "$SCRIPT_STATUS" -eq 0 ]; then
        curl -fsS --retry 3 --data-binary @"$OUT_LOG" "$HEALTHCHECKS_URL" > /dev/null
    else
        curl -fsS --retry 3 --data-binary @"$OUT_LOG" "$HEALTHCHECKS_URL/fail" > /dev/null
    fi
fi

exit "$SCRIPT_STATUS"
