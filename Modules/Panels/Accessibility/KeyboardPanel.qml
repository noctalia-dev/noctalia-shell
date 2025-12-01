import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Modules.MainScreen
import qs.Commons
import qs.Widgets
import qs.Services.Keyboard

SmartPanel {
    id: root
    panelAnchorBottom: true
    panelAnchorHorizontalCenter: true
    preferredWidth: Math.round(1100 * Style.uiScaleRatio)
    preferredHeight: Math.round(800 * Style.uiScaleRatio)
    readonly property string typeKeyScript: Quickshell.shellDir + '/Bin/type-key.py'
    exclusiveKeyboard: false
    hasFocus: false
    
    Process {
        id: resetScript
        command: ["python", root.typeKeyScript, "reset"]
        stderr: StdioCollector {
            onStreamFinished: {
                Logger.d("Keyboard", "modifier toggles reset")
            }
        }
    }

    onOpened: {
        resetScript.running = false
    }
    onClosed: {
        resetScript.running = true
        capsON = false
        activeModifiers = {"shift": false, "alt": false, "super": false, "ctrl": false, "caps": false}
    }

    property var qwerty: [
        // line 1
        [
            { key: "esc", width: 60, txt: "esc", shift: "esc" }, { key: "grave", width: 60, txt: "`", shift: "~"  }, { key: "1", width: 60, txt: "1", shift: "!"  }, { key: "2", width: 60, txt: "2", shift: "@"  }, { key: "3", width: 60, txt: "3", shift: "#" },
            { key: "4", width: 60, txt: "4", shift: "$"  }, { key: "5", width: 60, txt: "5", shift: "%" }, { key: "6", width: 60, txt: "6", shift: "^"  }, { key: "7", width: 60, txt: "7", shift: "&"  },
            { key: "8", width: 60, txt: "8", shift: "*" }, { key: "9", width: 60, txt: "9", shift: "(" }, { key: "0", width: 60, txt: "0", shift: ")"  }, { key: "-",width: 60, txt: "-", shift: "_"  },
            { key: "=", width: 60, txt: "=", shift: "+"  }, { key: "backspace", width: 100, txt: "", shift: "" }
        ],
        // line 2
        [
            { key: "tab", width: 80, txt: "", shift: "" }, { key: "Q", width: 60, txt: "Q", shift: "Q" }, { key: "W", width: 60, txt: "W", shift: "W" }, { key: "E", width: 60, txt: "E", shift: "E" },
            { key: "R", width: 60, txt: "R", shift: "R" }, { key: "T", width: 60, txt: "T", shift: "T" }, { key: "Y", width: 60, txt: "Y", shift: "Y" }, { key: "U", width: 60, txt: "U", shift: "U" },
            { key: "I", width: 60, txt: "I", shift: "I" }, { key: "O", width: 60, txt: "O", shift: "O" }, { key: "P", width: 60, txt: "P", shift: "P" }, { key: "[", width: 60, txt: "[", shift: "{" },
            { key: "]", width: 60, txt: "]", shift: "}" }, { key: "backslash", width: 60, txt: "\\", shift: "|" }
        ],
        // line 3
        [
            { key: "caps", width: 90, txt: "", shift: "" }, { key: "A", width: 60, txt: "A", shift: "A" }, { key: "S", width: 60, txt: "S", shift: "S" }, { key: "D", width: 60, txt: "D", shift: "D" },
            { key: "F", width: 60, txt: "F", shift: "F" }, { key: "G", width: 60, txt: "G", shift: "G" }, { key: "H", width: 60, txt: "H", shift: "H" }, { key: "J", width: 60, txt: "J", shift: "J" },
            { key: "K", width: 60, txt: "K", shift: "K" }, { key: "L", width: 60, txt: "L", shift: "L" }, { key: ";", width: 60, txt: ";", shift: ":" }, { key: "'", width: 60, txt: "'", shift: "\"" },
            { key: "return", width: 100, txt: "", shift: "" }
        ],
        // line 4
        [
            { key: "shift", width: 120, txt: "", shift: "" }, { key: "Z", width: 60, txt: "Z", shift: "Z" }, { key: "X", width: 60, txt: "X", shift: "X" }, { key: "C", width: 60, txt: "C", shift: "C" },
            { key: "V", width: 60, txt: "V", shift: "V" }, { key: "B", width: 60, txt: "B", shift: "B" }, { key: "N", width: 60, txt: "N", shift: "N" },
            { key: "M", width: 60, txt: "M", shift: "M" }, { key: ",", width: 60, txt: ",", shift: "<" }, { key: ".", width: 60, txt: ".", shift: ">" }, { key: "/", width: 60, txt: "/", shift: "?" },
            { key: "up", width: 60, txt: "", shift: "" }
        ],
        [
            { key: "ctrl", width: 70, txt: "ctrl", shift: "ctrl" }, { key: "super", width: 60, txt: "", shift: "" }, { key: "alt", width: 60, txt: "alt", shift: "alt" },
            { key: "space", width: 550, txt: "", shift: "" }, { key: "left", width: 60, txt: "", shift: "" }, { key: "down", width: 60, txt: "", shift: "" }, { key: "right", width: 60, txt: "", shift: "" }
        ],
    ]
    property var azerty: [
        // line 1
        [
            { key: "esc", width: 60, txt: "esc", shift: "esc" }, { key: "&", width: 60, txt: "&", shift: "1"  }, { key: "é", width: 60, txt: "é", shift: "2"  }, { key: "\"", width: 60, txt: "\"", shift: "3"  },
            { key: "'", width: 60, txt: "'", shift: "4"  }, { key: "(", width: 60, txt: "(", shift: "5"  }, { key: "-", width: 60, txt: "-", shift: "6"  }, { key: "è", width: 60, txt: "è", shift: "7"  },
            { key: "_", width: 60, txt: "_", shift: "8" }, { key: "ç", width: 60, txt: "ç", shift: "9" }, { key: "à", width: 60, txt: "à", shift: "0"  }, { key: ")",width: 60 , txt: ")", shift: "°" },
            { key: "=", width: 60, txt: "=", shift: "+"  }, { key: "backspace", width: 100, txt: "", shift: ""  }
        ],
        // line 2
        [
            { key: "tab", width: 80, txt: "", shift: "" }, { key: "A", width: 60, txt: "A", shift: "A" }, { key: "Z", width: 60, txt: "Z", shift: "Z" }, { key: "E", width: 60, txt: "E", shift: "E" },
            { key: "R", width: 60, txt: "R", shift: "R" }, { key: "T", width: 60, txt: "T", shift: "T" }, { key: "Y", width: 60, txt: "Y", shift: "Y" }, { key: "U", width: 60, txt: "U", shift: "U" },
            { key: "I", width: 60, txt: "I", shift: "I" }, { key: "O", width: 60, txt: "O", shift: "O" }, { key: "P", width: 60, txt: "P", shift: "P" }, { key: "^", width: 60, txt: "^", shift: "¨" },
            { key: "$", width: 60, txt: "$", shift: "£" }
        ],
        // line 3
        [
            { key: "caps", width: 90, txt: "", shift: "" }, { key: "Q", width: 60, txt: "Q", shift: "Q" }, { key: "S", width: 60, txt: "S", shift: "S" }, { key: "D", width: 60, txt: "D", shift: "D" },
            { key: "F", width: 60, txt: "F", shift: "F" }, { key: "G", width: 60, txt: "G", shift: "G" }, { key: "H", width: 60, txt: "H", shift: "H" }, { key: "J", width: 60, txt: "J", shift: "J" },
            { key: "K", width: 60, txt: "K", shift: "K" }, { key: "L", width: 60, txt: "L", shift: "L" }, { key: "M", width: 60, txt: "M", shift: "M" }, { key: "ù", width: 60, txt: "ù", shift: "%" },
            { key: "*", width: 60, txt: "*", shift: "µ" }, { key: "return", width: 100, txt: "", shift: "" }
        ],
        // line 4
        [
            { key: "shift", width: 120, txt: "", shift: "" }, { key: "W", width: 60, txt: "W", shift: "W" }, { key: "X", width: 60, txt: "X", shift: "X" }, { key: "C", width: 60, txt: "C", shift: "C" },
            { key: "V", width: 60, txt: "V", shift: "V" }, { key: "B", width: 60, txt: "B", shift: "B" }, { key: "N", width: 60, txt: "N", shift: "N" },
            { key: ",", width: 60, txt: ",", shift: "?" }, { key: ";", width: 60, txt: ";", shift: "." }, { key: ":", width: 60, txt: ":", shift: "/" }, { key: "!", width: 60, txt: "!", shift: "§" },
            { key: "up", width: 60, txt: "", shift: "" }
        ],
        // line 5
        [
            { key: "ctrl", width: 70, txt: "ctrl", shift: "ctrl" }, { key: "super", width: 60, txt: "", shift: "" }, { key: "alt", width: 60, txt: "alt", shift: "alt" },
            { key: "space", width: 550, txt: "", shift: "" }, { key: "left", width: 60, txt: "", shift: "" }, { key: "down", width: 60, txt: "", shift: "" }, { key: "right", width: 60, txt: "", shift: "" }
        ]
    ]

    property var layout: KeyboardLayoutService.currentLayout === "fr" ? azerty : qwerty

    property var activeModifiers: {"shift": false, "alt": false, "super": false, "ctrl": false}

    property bool capsON: false

    property var keyArray: []

    panelContent: Item {

        property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2
        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            Repeater {
                model: root.layout

                RowLayout {
                    spacing: Style.marginL

                    Repeater {
                        model: modelData

                        NBox {
                            width: modelData.width
                            height: 60
                            color: (runScript.running || (modelData.key ===  "caps" & root.capsON) || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mOnSurface : Color.mSurfaceVariant

                            // refresh colors and text every 0.2 seconds
                            Timer {
                                interval: 200; running: true; repeat: true
                                onTriggered: {
                                    if (modelData.key in root.activeModifiers) {
                                        color = (runScript.running || (modelData.key ===  "caps" & root.capsON) || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mOnSurface : Color.mSurfaceVariant
                                    }
                                    keyText.color = (runScript.running || (modelData.key ===  "caps" & root.capsON) || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mSurfaceVariant : Color.mOnSurface
                                    keyText.text = (root.activeModifiers["shift"] || root.capsON) ? modelData.shift : modelData.txt
                                }
                            }

                            NText {
                                id: keyText
                                anchors.centerIn: parent
                                text: (root.activeModifiers["shift"] || root.capsON) ? modelData.shift : modelData.txt
                                font.weight: Style.fontWeightBold
                                font.pointSize:Style.fontSizeL * fontScale
                                color: (runScript.running || (modelData.key ===  "caps" & root.capsON) || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mSurfaceVariant : Color.mOnSurface
                            }

                            function toggleModifier(mod) {
                                if (mod in root.activeModifiers) {
                                    root.activeModifiers[mod] = !root.activeModifiers[mod]
                                }
                            }
                            
                            Process {
                                id: runScript
                                command: ["python", root.typeKeyScript] // placeholder

                                function startWithKeys(keys) {
                                    var ks = keys.map(function(x){ return x.toString(); });
                                    runScript.command = ["python", root.typeKeyScript].concat(ks);
                                    runScript.running = true;
                                }
                                stderr: StdioCollector {
                                    onStreamFinished: {
                                        if (text) Logger.w(text.trim());
                                    }
                                }
                            }


                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    if (modelData.key in root.activeModifiers) {
                                        toggleModifier(modelData.key)
                                    }
                                    else{
                                        if (modelData.key === "caps") {
                                            root.capsON = !root.capsON
                                        }
                                        root.keyArray = [modelData.key]
                                        for (var k in root.activeModifiers) {
                                            var v = root.activeModifiers[k];
                                            if (v) {
                                                root.keyArray.push(k);
                                            }
                                        }
                                        root.keyArray.unshift(root.layout === root.azerty ? "fr" : "en")
                                        runScript.startWithKeys(keyArray)
                                    }
                                    Logger.d(modelData.key.toString())
                                }
                                onReleased: {
                                    if (!(modelData.key in root.activeModifiers)) {
                                        root.keyArray = []
                                        root.activeModifiers = {"shift": false, "alt": false, "super": false, "ctrl": false}
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}