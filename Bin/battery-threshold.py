#!/usr/bin/env python3
import sys
import os
import glob
import subprocess
import configparser
from pathlib import Path

# Constants
CONFIG_DIR = os.path.expanduser("~/.config/noctalia")
CONFIG_FILE = os.path.join(CONFIG_DIR, "battery_threshold")
BATTERY_GLOB = "/sys/class/power_supply/BAT*"
THRESHOLD_FILE_NAME = "charge_control_end_threshold"

def get_battery_path():
    # Find the first battery that supports threshold
    batteries = glob.glob(BATTERY_GLOB)
    for bat in batteries:
        if os.path.exists(os.path.join(bat, THRESHOLD_FILE_NAME)):
            return bat
    return None

def read_sysfs_threshold(bat_path):
    try:
        with open(os.path.join(bat_path, THRESHOLD_FILE_NAME), 'r') as f:
            return int(f.read().strip())
    except Exception:
        return -1

def write_sysfs_threshold(bat_path, value):
    path = os.path.join(bat_path, THRESHOLD_FILE_NAME)
    try:
        # Try writing directly 
        with open(path, 'w') as f:
            f.write(str(value))
        return True
    except PermissionError:
        print(f"Permission denied writing to {path}. Please run setup-permissions.", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error writing to sysfs: {e}", file=sys.stderr)
        return False

def load_config():
    if not os.path.exists(CONFIG_FILE):
        return None
    try:
        with open(CONFIG_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return None

def save_config(value):
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            f.write(str(value))
    except Exception as e:
        print(f"Error saving config: {e}", file=sys.stderr)

def main():
    if len(sys.argv) < 2:
        print("Usage: battery-threshold.py [get|set <val>|apply|check]")
        sys.exit(1)

    command = sys.argv[1]
    bat_path = get_battery_path()

    if command == "check":
        if bat_path:
            is_writable = os.access(os.path.join(bat_path, THRESHOLD_FILE_NAME), os.W_OK)
            print(f"supported:{'writable' if is_writable else 'readonly'}")
            sys.exit(0)
        else:
            print("unsupported")
            sys.exit(1)

    if not bat_path:
        print("No battery with threshold support found", file=sys.stderr)
        sys.exit(1)

    if command == "setup-permissions":
        # Create a udev rule to make the file writable by everyone (simplest for single-user desktop)
        udev_rule = 'ACTION=="add", SUBSYSTEM=="power_supply", ATTR{type}=="Battery", RUN+="/bin/sh -c \'chmod 666 /sys/class/power_supply/%k/charge_control_end_threshold\'"'
        
        # 1. Apply immediate permission fix
        try:
            path = os.path.join(bat_path, THRESHOLD_FILE_NAME)
            subprocess.check_call(["pkexec", "chmod", "666", path])
        except subprocess.CalledProcessError:
             print("Failed to set immediate permissions", file=sys.stderr)
             sys.exit(1)

        # 2. Install persistent udev rule
        try:
            # write to a temp file then move it with pkexec
            tmp_rule = "/tmp/90-noctalia-battery.rules"
            with open(tmp_rule, "w") as f:
                f.write(udev_rule + "\n")
            
            subprocess.check_call(["pkexec", "mv", tmp_rule, "/etc/udev/rules.d/90-noctalia-battery.rules"])
            subprocess.check_call(["pkexec", "udevadm", "control", "--reload-rules"])
            subprocess.check_call(["pkexec", "udevadm", "trigger"])
            print("Permissions setup complete")
        except Exception as e:
            print(f"Failed to setup udev rule: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    if command == "setup-permissions-stdin":
        # Read password from stdin
        password = sys.stdin.read().strip()
        udev_rule = 'ACTION=="add", SUBSYSTEM=="power_supply", ATTR{type}=="Battery", RUN+="/bin/sh -c \'chmod 666 /sys/class/power_supply/%k/charge_control_end_threshold\'"'
        
        def run_sudo(cmd_list):
            proc = subprocess.Popen(
                ["sudo", "-S"] + cmd_list,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            out, err = proc.communicate(input=password + "\n")
            if proc.returncode != 0:
                raise Exception(f"Command failed: {err}")

        try:
            # 1. Apply immediate permission fix
            path = os.path.join(bat_path, THRESHOLD_FILE_NAME)
            run_sudo(["chmod", "666", path])

            # 2. Install persistent udev rule
            tmp_rule = "/tmp/90-noctalia-battery.rules"
            with open(tmp_rule, "w") as f:
                f.write(udev_rule + "\n")
            
            run_sudo(["mv",(tmp_rule), "/etc/udev/rules.d/90-noctalia-battery.rules"])
            run_sudo(["udevadm", "control", "--reload-rules"])
            run_sudo(["udevadm", "trigger"])
            print("Permissions setup complete")
        except Exception as e:
            print(f"Failed: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    if command == "get":
        # Return current sysfs value
        print(read_sysfs_threshold(bat_path))

    elif command == "set":
        if len(sys.argv) < 3:
            sys.exit(1)
        value = int(sys.argv[2])
        if 0 <= value <= 100:
            if write_sysfs_threshold(bat_path, value):
                save_config(value)
                print(value)
            else:
                sys.exit(1)

    elif command == "apply":
        # Apply stored config to sysfs
        stored = load_config()
        if stored is not None:
            write_sysfs_threshold(bat_path, stored)
            print(stored)
        else:
            # If no config, just print current
            print(read_sysfs_threshold(bat_path))

if __name__ == "__main__":
    main()
