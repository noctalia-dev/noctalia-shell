function getKeybindString(event) {
    let keyStr = "";
    if (event.modifiers & Qt.ControlModifier)
        keyStr += "Ctrl+";
    if (event.modifiers & Qt.AltModifier)
        keyStr += "Alt+";
    if (event.modifiers & Qt.ShiftModifier)
        keyStr += "Shift+";

    let keyName = "";
    let rawText = event.text;

    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z || event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
        keyName = String.fromCharCode(event.key);
    } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
        keyName = "F" + (event.key - Qt.Key_F1 + 1);
    } else if (rawText && rawText.length > 0 && rawText.charCodeAt(0) > 31 && rawText.charCodeAt(0) !== 127) {
        keyName = rawText.toUpperCase();

        if (event.modifiers & Qt.ShiftModifier) {
            const shiftMap = {
                "!": "1",
                "\"": "2",
                "§": "3",
                "$": "4",
                "%": "5",
                "&": "6",
                "/": "7",
                "(": "8",
                ")": "9",
                "=": "0",
                "@": "2",
                "#": "3",
                "^": "6",
                "*": "8"
            };
            if (shiftMap[keyName]) {
                keyName = shiftMap[keyName];
            }
        }
    } else {
        switch (event.key) {
            case Qt.Key_Escape:
                keyName = "Esc";
                break;
            case Qt.Key_Space:
                keyName = "Space";
                break;
            case Qt.Key_Return:
                keyName = "Return";
                break;
            case Qt.Key_Enter:
                keyName = "Enter";
                break;
            case Qt.Key_Tab:
                keyName = "Tab";
                break;
            case Qt.Key_Backspace:
                keyName = "Backspace";
                break;
            case Qt.Key_Delete:
                keyName = "Del";
                break;
            case Qt.Key_Insert:
                keyName = "Ins";
                break;
            case Qt.Key_Home:
                keyName = "Home";
                break;
            case Qt.Key_End:
                keyName = "End";
                break;
            case Qt.Key_PageUp:
                keyName = "PgUp";
                break;
            case Qt.Key_PageDown:
                keyName = "PgDn";
                break;
            case Qt.Key_Left:
                keyName = "Left";
                break;
            case Qt.Key_Right:
                keyName = "Right";
                break;
            case Qt.Key_Up:
                keyName = "Up";
                break;
            case Qt.Key_Down:
                keyName = "Down";
                break;
        }
    }

    if (!keyName)
        return "";
    return keyStr + keyName;
}

function checkKey(event, settingName, settings) {
    // Map simplified names to the actual setting property names
    var propName = "key" + settingName.charAt(0).toUpperCase() + settingName.slice(1);
    var boundKeys = settings.data.general.keybinds[propName];
    if (!boundKeys || boundKeys.length === 0)
        return false;
    var eventString = getKeybindString(event);
    for (var i = 0; i < boundKeys.length; i++) {
        if (boundKeys[i] === eventString)
            return true;
    }
    return false;
}

/**
 * Check if a keybind string conflicts with any other existing keybinds.
 * @param {string} keyStr - The keybind string to check (e.g., "Ctrl+A").
 * @param {string} currentPath - The settings path of the keybind being edited (to skip checking itself).
 * @param {object} data - The settings data object (from Settings.data).
 * @returns {string|null} - The name of the conflicting action, or null if no conflict.
 */
function getKeybindConflict(keyStr, currentPath, data) {
    if (!keyStr || !data) return null;

    const searchKey = String(keyStr).trim().toLowerCase();

    // 1. Check navigation keybinds
    const navKeybinds = data.general ? data.general.keybinds : null;
    const navMap = {
        "keyUp": "Navigation: Up",
        "keyDown": "Navigation: Down",
        "keyLeft": "Navigation: Left",
        "keyRight": "Navigation: Right",
        "keyEnter": "Navigation: Enter",
        "keyEscape": "Navigation: Escape"
    };

    if (navKeybinds) {
        for (const prop in navMap) {
            const fullPath = "general.keybinds." + prop;
            if (fullPath === currentPath) continue;

            const boundKeys = navKeybinds[prop];
            if (boundKeys && boundKeys.length !== undefined) {
                for (let i = 0; i < boundKeys.length; i++) {
                    if (String(boundKeys[i]).trim().toLowerCase() === searchKey) {
                        return navMap[prop];
                    }
                }
            }
        }
    }

    // 2. Check session menu power options
    const sessionMenu = data.sessionMenu;
    if (sessionMenu && sessionMenu.powerOptions) {
        const powerOptions = sessionMenu.powerOptions;
        for (let i = 0; i < powerOptions.length; i++) {
            const entry = powerOptions[i];
            const fullPath = "sessionMenu.powerOptions[" + i + "].keybind";
            if (fullPath === currentPath) continue;

            if (entry.keybind && String(entry.keybind).trim().toLowerCase() === searchKey) {
                // Capitalize action name
                const actionName = entry.action ? entry.action.charAt(0).toUpperCase() + entry.action.slice(1) : "Unknown";
                return "Session Menu: " + actionName;
            }
        }
    }

    return null;
}
