import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Services.Power

// Unified shadow system
Item {
  id: root

  required property var source

  property bool autoPaddingEnabled: false
  property real shadowHorizontalOffset: Settings.data.general.shadowOffsetX
  property real shadowVerticalOffset: Settings.data.general.shadowOffsetY
  property real shadowOpacity: Style.shadowOpacity
  property color shadowColor: "black"
  property real shadowBlur: Style.shadowBlur

  layer.enabled: Settings.data.general.enableShadows && !PowerProfileService.noctaliaPerformanceMode
  layer.effect: MultiEffect {
    source: root.source
    shadowEnabled: true
    blurMax: Style.shadowBlurMax
    shadowBlur: root.shadowBlur
    shadowOpacity: root.shadowOpacity
    shadowColor: root.shadowColor
    shadowHorizontalOffset: root.shadowHorizontalOffset
    shadowVerticalOffset: root.shadowVerticalOffset
    autoPaddingEnabled: root.autoPaddingEnabled
  }
}
