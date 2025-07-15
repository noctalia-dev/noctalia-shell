import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Scope {
    id: root
    property int count: 32
    property int noiseReduction: 60
    property string channels: "mono"
    property string monoOption: "average"

    property var config: ({
        general: { bars: count },
        smoothing: { noise_reduction: noiseReduction },
        output: {
            method: "raw",
            bit_format: 8,
            channels: channels,
            mono_option: monoOption,
        }
    })

    property var values: Array(count).fill(0) // 0 <= value <= 1

    Process {
        property int index: 0
        id: process
        stdinEnabled: true
        running: MusicManager.isPlaying
        command: ["cava", "-p", "/dev/stdin"]
        onExited: {
            stdinEnabled = true;
            index = 0;
            for (let i = 0; i < values.length; i++) {
                values[i] = 0;
            }
        }
        onStarted: {
            const iniParts = []
            for (const k in config) {
                if (typeof config[k] !== "object") {
                    write(k + "=" + config[k] + "\n")
                    continue
                }
                write("[" + k + "]\n")
                const obj = config[k]
                for (const k2 in obj) {
                    write(k2 + "=" + obj[k2] + "\n")
                }
            }
            stdinEnabled = false
        }
        stdout: SplitParser {
            property var newValuesBuffer: Array(count).fill(0)

            splitMarker: ""
            onRead: data => {
                if (newValuesBuffer.length !== root.count) {
                    newValuesBuffer = Array(root.count).fill(0);
                }

                if (process.index + data.length > root.config.general.bars) {
                    process.index = 0
                }
                for (let i = 0; i < data.length; i += 1) {
                    newValuesBuffer[i + process.index] = Math.min(data.charCodeAt(i), 128) / 128
                }
                process.index += data.length
                root.values = newValuesBuffer
            }
        }
    }
}