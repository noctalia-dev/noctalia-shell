import QtQuick
import qs.Commons

Item {
  id: root
  property color fillColor: Color.mPrimary
  property color strokeColor: Color.mOnSurface
  property int strokeWidth: 0
  property var values: []
  property bool vertical: false
  property string barPosition: "top" // "top", "bottom", "left", "right"
  property bool mirrored: true

  // Minimum signal properties
  property bool showMinimumSignal: false
  property real minimumSignalValue: 0.01 // Default to 1% of height

  // Pre compute horizontal mirroring
  readonly property int valuesCount: (values && values.length !== undefined) ? values.length : 0
  readonly property int totalBars: mirrored ? valuesCount * 2 : valuesCount
  readonly property real barSlotSize: totalBars > 0 ? (vertical ? height : width) / totalBars : 0
  readonly property bool highQuality: (Settings.data.audio.visualizerType === "low") ? false : true

  Repeater {
    model: root.totalBars

    Rectangle {
      property int valueIndex: root.mirrored ? (index < root.valuesCount ? root.valuesCount - 1 - index : index - root.valuesCount) : index

      property real rawAmp: (root.values && root.values[valueIndex] !== undefined) ? root.values[valueIndex] : 0
      property real amp: (root.showMinimumSignal && rawAmp === 0) ? root.minimumSignalValue : rawAmp

      color: root.fillColor
      border.color: root.strokeColor
      border.width: root.strokeWidth
      antialiasing: root.highQuality
      smooth: root.highQuality

      // Only update when value actually changes - reduces GPU load
      width: vertical ? root.width * amp : root.barSlotSize * 0.5
      height: vertical ? root.barSlotSize * 0.5 : root.height * amp
      x: vertical ? (root.barPosition === "left" ? 0 : root.width - width) : index * root.barSlotSize + (root.barSlotSize * 0.25)
      y: vertical ? index * root.barSlotSize + (root.barSlotSize * 0.25) : root.height - height

      // Disable updates when invisible to save GPU
      visible: root.visible
    }
  }
}
