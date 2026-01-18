#!/usr/bin/env bash

# bluetooth-connect.sh
# Pairs, trusts, and attempts to connect to a Bluetooth device using bluetoothctl.
# Usage: bluetooth-connect.sh <addr> <pairWaitSeconds> <attempts> <intervalSec>

set -euo pipefail

if [[ ${#} -lt 4 ]]; then
  echo "Usage: $0 <addr> <pairWaitSeconds> <attempts> <intervalSec>" >&2
  exit 2
fi

addr=$1
pair_wait_seconds=$2
attempts=$3
interval_sec=$4

if [[ -z "${addr}" || ${#addr} -lt 7 ]]; then
  echo "Invalid Bluetooth address: '${addr}'" >&2
  exit 2
fi

# Launch bluetoothctl session to pair, trust, and try to connect repeatedly.
{
  echo 'agent KeyboardDisplay'
  echo 'default-agent'
  echo 'power on'
  echo "pair ${addr}"
  # Give time for potential confirmation prompt; send 'yes' optimistically (no-op if not needed)
  sleep 1
  echo 'yes'
  # Mark device trusted
  echo "trust ${addr}"
  # Attempt multiple connects within the session
  for i in $(seq 1 "${attempts}"); do
    echo "connect ${addr}"
    sleep "${interval_sec}"
  done
  echo 'quit'
} | bluetoothctl &

# Wait up to pair_wait_seconds for pairing to complete
for i in $(seq 1 "${pair_wait_seconds}"); do
  if bluetoothctl info "${addr}" | grep -q 'Paired: yes'; then
    break
  fi
  sleep 1
done

# Check connection state for ~attempts*interval_sec seconds total
for i in $(seq 1 "${attempts}"); do
  if bluetoothctl info "${addr}" | grep -q 'Connected: yes'; then
    exit 0
  fi
  sleep "${interval_sec}"
done

exit 1
