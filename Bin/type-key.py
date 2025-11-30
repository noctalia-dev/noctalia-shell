import subprocess
import sys
import time
import re
import os
import json
import glob

# ---------- CONSTANTS ----------
SPECIAL_KEYS = {
    "return": 28, "space": 57, "tab": 15, "backspace": 14, "esc": 1,
    "left": 105, "up": 103, "right": 106, "down": 108, "caps": 58, "*": 55
}

MODIFIER_KEYS = {
    "shift": 42, "ctrl": 29, "alt": 56, "super": 125
}

AZERTY_TO_QWERTY = {
    "a":"q","z":"w","q":"a","w":"z","m":";",
    "&":"1","é":"2",'"':"3","'":"4","(":"5","-":"6","è":"7","_":"8","ç":"9","à":"0",
    ")":"-","^":"[","$":"]","ù":"'",",":"m",";":",",":":".","!":"/"
}

STATE_FILE = os.path.abspath(os.path.join(__file__, "../ydotool_toggle_state.json"))

# ---------- FILE HELPERS ----------
def load_state():
    if not os.path.isfile(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except:
        return {}

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

# ---------- SYSTEM HELPERS ----------
def run(cmd):
    subprocess.run(cmd, capture_output=False)

def check_ydotool_service():
    try:
        status = subprocess.run(
            ["systemctl", "--user", "is-active", "ydotool.service"],
            capture_output=True, text=True
        ).stdout.strip()
        if status != "active":
            print("[INFO] Starting ydotool service...")
            run(["systemctl", "--user", "start", "ydotool.service"])
            time.sleep(1)
    except:
        sys.exit("[ERROR] Could not manage ydotool service")

def get_keyboard_layout():
    try:
        out = subprocess.check_output(["localectl", "status"], text=True)
        match = re.search(r"Layout:\s+(\w+)", out)
        return match.group(1).lower() if match else "unknown"
    except:
        return "unknown"

# ---------- KEY ACTIONS ----------
def press_key(code, down=True):
    run(["ydotool", "key", f"{code}:{1 if down else 0}"])

def toggle_special_key(name):
    code = MODIFIER_KEYS.get(name)
    if code is None:
        sys.exit(f"[ERROR] Not toggleable: {name}")

    state = load_state()
    pressed = state.get(name, False)

    # Toggle
    state[name] = not pressed
    save_state(state)

    print(f"[INFO] {name} {'DOWN' if state[name] else 'UP'}")

def apply_layout(key, layout):
    return AZERTY_TO_QWERTY.get(key.lower(), key) if layout == "fr" else key

# ---------- SEND KEY ----------
def send_key(key, modifiers):
    layout = get_keyboard_layout()
    _key = apply_layout(key, layout)

    # Auto-apply toggled modifiers
    if not modifiers:
        active = [k for k, v in load_state().items() if v]
        if active:
            send_key(key, active)
            for m in active:
                toggle_special_key(m)
            return

    # Press modifiers
    for m in modifiers:
        if m in MODIFIER_KEYS:
            press_key(MODIFIER_KEYS[m], True)

    # Special key
    if _key in SPECIAL_KEYS:
        code = SPECIAL_KEYS[_key]
        press_key(code, True)
        press_key(code, False)
    else:
        # Regular text
        run(["ydotool", "type", _key])

    print(f"Text sent: {_key}")

    # Release modifiers
    for m in reversed(modifiers):
        if m in MODIFIER_KEYS:
            press_key(MODIFIER_KEYS[m], False)

# ---------- RESET ----------
def reset():
    state = load_state()

    # Release all toggled modifiers
    for key, pressed in state.items():
        if pressed:
            toggle_special_key(key)
            press_key(MODIFIER_KEYS[key], False)

    # Reset CapsLock LED if needed
    caps_paths = glob.glob("/sys/class/leds/input*::capslock/brightness")
    if not caps_paths:
        return

    caps_file = caps_paths[0]
    if open(caps_file).read().strip() == "1":
        press_key(SPECIAL_KEYS["caps"], True)
        press_key(SPECIAL_KEYS["caps"], False)

# ---------- MAIN ----------
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python type-key.py <key_or_text> [modifiers...]")
        sys.exit(1)

    key = sys.argv[1]
    mods = [m.lower() for m in sys.argv[2:]]

    if key == "reset":
        reset()
        sys.exit(0)

    check_ydotool_service()

    # Toggle mode
    if key.lower() in MODIFIER_KEYS and not mods:
        toggle_special_key(key.lower())
        sys.exit(0)

    send_key(key.lower(), mods)
