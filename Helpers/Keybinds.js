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
    } else if (rawText && rawText.length > 0 && rawText.charCodeAt(0) > 31) {
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
