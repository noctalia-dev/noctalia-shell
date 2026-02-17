#!/usr/bin/env python3
import errno
import os
import pty
import select
import subprocess
import sys
import time
# flake8: noqa: E501 # Line too long
version = "0.0.2-1"


def log(msg) -> None:
    sys.stdout.write(f"[pair] {msg}\n")
    sys.stdout.flush()  # Flush to ensure the message is passed


def pair_fast():
    if len(sys.argv) < 5:
        log("Usage: bluetooth-pair.py <addr> <pairWaitSeconds> <attempts> <intervalSec>")
        sys.exit(2)

    addr = sys.argv[1]
    # We won't use pair_wait_seconds in the same way, but we'll respect the timeout logic.
    pair_wait_seconds = float(sys.argv[2])
    if pair_wait_seconds < 30:
        log(f"Warning: pairWaitSeconds ({pair_wait_seconds}s) is too short. Enforcing 45s minimum.")
        pair_wait_seconds = 45.0

    attempts = int(sys.argv[3])
    interval_sec = float(sys.argv[4])

    if not addr or len(addr) < 17:
        # Basic MAC address length check
        log(f"Invalid Bluetooth address: '{addr}'")
        sys.exit(2)

    # m/s PTY for interactive control
    mfd, sfd = pty.openpty()

    # Start bluetoothctl
    subprocess.Popen(['bluetoothctl'], stdin=sfd, stdout=sfd, stderr=sfd, close_fds=True, text=True)

    os.close(sfd)

    def send_command(cmd):
        log(f"Sending cmd: {cmd}")
        os.write(mfd, (cmd + "\n").encode('utf-8'))

    def read_output(timeout=1.0):
        # Reads available output from mfd
        output = b""
        end_time = time.time() + timeout
        while time.time() < end_time:
            r, _, _ = select.select([mfd], [], [], 0.1)
            if mfd in r:
                try:
                    data = os.read(mfd, 1024)
                    if not data:
                        break
                    output += data
                except OSError as e:
                    if e.errno == errno.EIO:
                        break
                    raise
            else:
                pass
        return output.decode('utf-8', errors='replace')

    log("Initializing bluetoothctl...")
    time.sleep(1)  # Wait for startup
    # initial_out = read_output(timeout=1)
    # print(initial_out) # Debug

    send_command("agent on")
    send_command("default-agent")
    # send_command("power on") # If we are pairing bluetooth is already powered on
    time.sleep(0.5)

    # Pair directly since the device is already discovered in the UI/Panel (Removed previous scan/wait part)
    log(f"Attempting to pair with {addr}...")
    send_command(f"pair {addr}")

    # Loop to watch for confirmation or success
    start_time = time.time()
    paired = False

    log("Waiting for pairing sequence start...")
    while time.time() - start_time < pair_wait_seconds:
        out = read_output(timeout=0.5)
        if out:
            print(out, end='')
            # Device not found yet
            device_not_discovered: list[str] = [f"Device {addr} not available"]
            if any(e in out for e in device_not_discovered):
                log(f"Device {addr} is discovered yet...")
                pair_wait_seconds += 30  # Add additional time for device discovery

            # Confirm Passkey
            # Numberic Comparison (NC) 1 of 4 - Tested pairing with my iPhone.
            expected_confirmation: list[str] = ["Confirm passkey", "yes/no", "Request confirmation"]
            if any(e in out for e in expected_confirmation):
                log("Detected passkey prompt. Sending 'yes'.")
                send_command("yes")

            # Authorization Request
            expected_auth: list[str] = ["Authorize service", "Request authorization"]
            if any(e in out for e in expected_auth):
                log("Detected authorization request. Sending 'yes'.")
                send_command("yes")

            # Interactive PIN/Passkey Entry (Device displays code, User must enter on PC)
            expected_pin: list[str] = ["Enter passkey", "Enter PIN code", "Passkey: "]
            if any(e in out for e in expected_pin):
                log("Device requested PIN/Passkey. Waiting for user input...")
                log("PIN_REQUIRED")  # Signal to service, to prompt user.

                try:
                    # Read PIN from stdin (blocking)
                    user_pin = sys.stdin.readline().strip()
                    if user_pin:
                        log(f"Received PIN: {user_pin}, relaying to bluetoothctl...")
                        send_command(user_pin)
                except Exception as e:
                    log(f"Error reading stdin: {e}")
                    break

            # Just Works (JW) is implicit (no prompt)
            expected_success: list[str] = ["Pairing successful", "Paired: yes", "Bonded: yes"]
            if any(e in out for e in expected_success):
                paired = True
                log("Pairing successful detected in stream.")
                break

            if "Failed to pair" in out:
                log("Pairing failed explicitly.")
                break
            
            expected_already_paired: list[str] = ["Already joined", "Already exists"]
            if any(e in out for e in expected_already_paired):
                paired = True
                log("Device already paired.")
                break

    # Double check pairing status via info command if not sure
    if not paired:
        send_command(f"info {addr}")
        time.sleep(1)
        out = read_output(timeout=1)
        if "Paired: yes" in out:
            paired = True

    if paired:
        log("Device is paired. Trusting...")
        send_command(f"trust {addr}")
        time.sleep(1)

        log("Connecting...")
        connected = False
        for i in range(attempts):
            send_command(f"connect {addr}")
            # Wait a bit for connection
            time.sleep(interval_sec)

            # Check status
            send_command(f"info {addr}")
            time.sleep(1)
            out = read_output(timeout=1)
            if "Connected: yes" in out:
                log("Connected successfully, we are done here.")
                connected = True
                break
            else:
                log(f"Connection attempt {i + 1}/{attempts} failed. Retrying...")

        if connected:
            send_command("quit")
            sys.exit(0)
        else:
            log("Failed to connect after all attempts.")
            send_command("quit")
            sys.exit(1)

    else:
        log("Failed to pair within timeout.")
        send_command("quit")
        sys.exit(1)


if __name__ == "__main__":
    pair_fast()
