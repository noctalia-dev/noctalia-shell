// Modules/SettingsPanel/Bar/WidgetSettings/CavaVisualizerSettings.qml
import QtQuick
import QtQuick.Controls

Item {
  id: root
  // Bind the target from your settings loader to this component
  // e.g., settings system sets root.target = the widget instance
  property var target

  Column {
    spacing: 8

    Row { spacing: 8
      Label { text: "Bars"; width: 140 }
      SpinBox {
        from: 8; to: 256; value: target ? target.bars : 48
        onValueChanged: if (target) target.bars = value
      }
    }

    Row { spacing: 8
      Label { text: "Bar Width"; width: 140 }
      SpinBox {
        from: 1; to: 12; value: target ? target.barWidth : 3
        onValueChanged: if (target) target.barWidth = value
      }
    }

    Row { spacing: 8
      Label { text: "Spacing"; width: 140 }
      SpinBox {
        from: 0; to: 12; value: target ? target.barSpacing : 1
        onValueChanged: if (target) target.barSpacing = value
      }
    }

    Row { spacing: 8
      Label { text: "Radius"; width: 140 }
      SpinBox {
        from: 0; to: 12; value: target ? target.barRadius : 2
        onValueChanged: if (target) target.barRadius = value
      }
    }

    Row { spacing: 8
      Label { text: "Framerate"; width: 140 }
      SpinBox {
        from: 24; to: 120; value: target ? target.framerate : 60
        onValueChanged: if (target) target.framerate = value
      }
    }

    Row { spacing: 8
      Label { text: "ASCII Max"; width: 140 }
      SpinBox {
        from: 100; to: 5000; value: target ? target.asciiMax : 1000
        onValueChanged: if (target) target.asciiMax = value
      }
    }

    Row { spacing: 8
      Label { text: "Noise Reduction"; width: 140 }
      SpinBox {
        from: 0; to: 100; value: target ? target.noiseReduction : 77
        onValueChanged: if (target) target.noiseReduction = value
      }
    }

    Row { spacing: 8
      Label { text: "Mono"; width: 140 }
      Switch {
        checked: target ? target.mono : true
        onToggled: if (target) target.mono = checked
      }
    }
  }
}
