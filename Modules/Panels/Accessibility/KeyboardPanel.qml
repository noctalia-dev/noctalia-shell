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
    preferredWidth: Math.round(1200 * Style.uiScaleRatio)
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
        activeModifiers = {"shift": false, "alt": false, "super": false, "ctrl": false, "caps": false}
    }

    property var qwerty: [
        // line 1
        [
            { key: "esc", width: 60, txt: "esc" }, { key: "1", width: 60, txt: "1"  }, { key: "2", width: 60, txt: "2"  }, { key: "3", width: 60, txt: "3"  },
            { key: "4", width: 60, txt: "4"  }, { key: "5", width: 60, txt: "5"  }, { key: "6", width: 60, txt: "6"  }, { key: "7", width: 60, txt: "7"  },
            { key: "8", width: 60, txt: "8" }, { key: "9", width: 60, txt: "9" }, { key: "0", width: 60, txt: "0"  }, { key: "-",width: 60 , txt: "-" },
            { key: "=", width: 60, txt: "="  }, { key: "backspace", width: 100, txt: "⌫"  }
        ],
        // line 2
        [
            { key: "tab", width: 80, txt: "↹" }, { key: "Q", width: 60, txt: "Q" }, { key: "W", width: 60, txt: "W" }, { key: "E", width: 60, txt: "E" },
            { key: "R", width: 60, txt: "R" }, { key: "T", width: 60, txt: "T" }, { key: "Y", width: 60, txt: "Y" }, { key: "U", width: 60, txt: "U" },
            { key: "I", width: 60, txt: "I" }, { key: "O", width: 60, txt: "O" }, { key: "P", width: 60, txt: "P" }, { key: "[", width: 60, txt: "[" },
            { key: "]", width: 60, txt: "]" }
        ],
        // line 3
        [
            { key: "caps", width: 90, txt: "⇪" }, { key: "A", width: 60, txt: "A" }, { key: "S", width: 60, txt: "S" }, { key: "D", width: 60, txt: "D" },
            { key: "F", width: 60, txt: "F" }, { key: "G", width: 60, txt: "G" }, { key: "H", width: 60, txt: "H" }, { key: "J", width: 60, txt: "J" },
            { key: "K", width: 60, txt: "K" }, { key: "L", width: 60, txt: "L" }, { key: ";", width: 60, txt: ";" }, { key: "'", width: 60, txt: "'" },
            { key: "return", width: 160, txt: "↵" }
        ],
        // line 4
        [
            { key: "shift", width: 120, txt: "⇧" }, { key: "Z", width: 60, txt: "Z" }, { key: "X", width: 60, txt: "X" }, { key: "C", width: 60, txt: "C" },
            { key: "V", width: 60, txt: "V" }, { key: "B", width: 60, txt: "B" }, { key: "N", width: 60, txt: "N" },
            { key: "M", width: 60, txt: "M" }, { key: ",", width: 60, txt: "," }, { key: ".", width: 60, txt: "." }, { key: "/", width: 60, txt: "/" },
            { key: "up", width: 60, txt: "⭡" }
        ],
        [
            { key: "ctrl", width: 70, txt: "ctrl" }, { key: "super", width: 60, txt: "⌘" }, { key: "alt", width: 60, txt: "alt" },
            { key: "space", width: 550, txt: "⎵" }, { key: "left", width: 60, txt: "⭠" }, { key: "down", width: 60, txt: "⭣" }, { key: "right", width: 60, txt: "⭢" }
        ],
    ]
    property var azerty: [
        // line 1
        [
            { key: "esc", width: 60, txt: "esc" }, { key: "&", width: 60, txt: "&"  }, { key: "é", width: 60, txt: "é"  }, { key: "\"", width: 60, txt: "\""  },
            { key: "'", width: 60, txt: "'"  }, { key: "(", width: 60, txt: "("  }, { key: "-", width: 60, txt: "-"  }, { key: "è", width: 60, txt: "è"  },
            { key: "_", width: 60, txt: "_" }, { key: "ç", width: 60, txt: "ç" }, { key: "à", width: 60, txt: "à"  }, { key: ")",width: 60 , txt: ")" },
            { key: "=", width: 60, txt: "="  }, { key: "backspace", width: 100, txt: "⌫"  }
        ],
        // line 2
        [
            { key: "tab", width: 80, txt: "↹" }, { key: "A", width: 60, txt: "A" }, { key: "Z", width: 60, txt: "Z" }, { key: "E", width: 60, txt: "E" },
            { key: "R", width: 60, txt: "R" }, { key: "T", width: 60, txt: "T" }, { key: "Y", width: 60, txt: "Y" }, { key: "U", width: 60, txt: "U" },
            { key: "I", width: 60, txt: "I" }, { key: "O", width: 60, txt: "O" }, { key: "P", width: 60, txt: "P" }, { key: "^", width: 60, txt: "^" },
            { key: "$", width: 60, txt: "$" }
        ],
        // line 3
        [
            { key: "caps", width: 90, txt: "⇪" }, { key: "Q", width: 60, txt: "Q" }, { key: "S", width: 60, txt: "S" }, { key: "D", width: 60, txt: "D" },
            { key: "F", width: 60, txt: "F" }, { key: "G", width: 60, txt: "G" }, { key: "H", width: 60, txt: "H" }, { key: "J", width: 60, txt: "J" },
            { key: "K", width: 60, txt: "K" }, { key: "L", width: 60, txt: "L" }, { key: "M", width: 60, txt: "M" }, { key: "ù", width: 60, txt: "ù" },
            { key: "*", width: 60, txt: "*" }, { key: "return", width: 100, txt: "↵" }
        ],
        // line 4
        [
            { key: "shift", width: 120, txt: "⇧" }, { key: "W", width: 60, txt: "W" }, { key: "X", width: 60, txt: "X" }, { key: "C", width: 60, txt: "C" },
            { key: "V", width: 60, txt: "V" }, { key: "B", width: 60, txt: "B" }, { key: "N", width: 60, txt: "N" },
            { key: ",", width: 60, txt: "," }, { key: ";", width: 60, txt: ";" }, { key: ":", width: 60, txt: ":" }, { key: "!", width: 60, txt: "!" },
            { key: "up", width: 60, txt: "⭡" }
        ],
        // line 5
        [
            { key: "ctrl", width: 70, txt: "ctrl" }, { key: "super", width: 60, txt: "⌘" }, { key: "alt", width: 60, txt: "alt" },
            { key: "space", width: 550, txt: "⎵" }, { key: "left", width: 60, txt: "⭠" }, { key: "down", width: 60, txt: "⭣" }, { key: "right", width: 60, txt: "⭢" }
        ]
    ]

    property var layout: KeyboardLayoutService.currentLayout === "fr" ? azerty : qwerty

    property var activeModifiers: {"shift": false, "alt": false, "super": false, "ctrl": false, "caps": false}

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
                            color: (runScript.running || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mPrimary : Color.mSurfaceVariant

                            // refresh color ever 0.2 seconds for modifier keys only
                            Timer {
                                interval: 200; running: true; repeat: true
                                onTriggered: {
                                    if (modelData.key in root.activeModifiers) {
                                        color = (runScript.running || (modelData.key in root.activeModifiers & root.activeModifiers[modelData.key])) ? Color.mPrimary : Color.mSurfaceVariant
                                    }
                                }
                            }

                            NText {
                                anchors.centerIn: parent
                                text: modelData.txt
                            }

                            function toggleModifier(mod) {
                                if (mod in root.activeModifiers) {
                                    root.activeModifiers[mod] = !root.activeModifiers[mod]
                                }
                                else {
                                    // pressed a non-modifier key, reset modifiers (exept caps-lock)
                                    root.activeModifiers["shift"] = false
                                    root.activeModifiers["ctrl"] = false
                                    root.activeModifiers["alt"] = false
                                    root.activeModifiers["super"] = false
                                }
                            }
                            
                            Process {
                                id: runScript
                                command: ["python", root.typeKeyScript, modelData.key.toString()]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        toggleModifier(modelData.key.toString())
                                    }
                                }
                                stderr: StdioCollector {
                                    onStreamFinished: {
                                        if(text) {
                                            Logger.w("Keyboard", text.trim());
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    runScript.running = true
                                    Logger.d(modelData.key.toString())
                                }
                                onReleased: {
                                    runScript.running = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}