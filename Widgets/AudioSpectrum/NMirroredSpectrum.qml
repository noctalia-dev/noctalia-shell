import QtQuick
import qs.Commons

Item {
  id: root
  property color fillColor: Color.mPrimary
  property color strokeColor: Color.mOnSurface
  property int strokeWidth: 0
  property var values: []
  property bool vertical: false

  // Minimum signal properties
  property bool showMinimumSignal: false
  property real minimumSignalValue: 0.05 // Default to 5% of height

  // Pre-compute mirroring
  readonly property int valuesCount: (values && Array.isArray(values)) ? values.length : 0
  readonly property int totalBars: valuesCount * 2
  readonly property real barSlotSize: totalBars > 0 ? (vertical ? height : width) / totalBars : 0
  readonly property bool highQuality: (Settings.data.audio.visualizerType === "low") ? false : true
  readonly property real centerY: height / 2
  readonly property real centerX: width / 2

  Repeater {
    model: root.totalBars

    Rectangle {
      // The first half of bars are a mirror image (reversed values array).
      // The second half of bars are in normal order.
      property int valueIndex: index < root.valuesCount ? root.valuesCount - 1 - index // Mirrored half
                                                        : index - root.valuesCount // Normal half

      property real rawAmp: (root.values && root.values[valueIndex] !== undefined) ? root.values[valueIndex] : 0
      property real amp: (root.showMinimumSignal && rawAmp === 0) ? root.minimumSignalValue : rawAmp

      property real barSize: (vertical ? root.width : root.height) * amp

      color: root.fillColor
      border.color: root.strokeColor
      border.width: root.strokeWidth
      antialiasing: root.highQuality
      smooth: root.highQuality

      width: vertical ? barSize : root.barSlotSize * 0.8
      height: vertical ? root.barSlotSize * 0.8 : barSize
      x: vertical ? root.centerX - (barSize / 2) : index * root.barSlotSize + (root.barSlotSize * 0.25)
      y: vertical ? index * root.barSlotSize + (root.barSlotSize * 0.25) : root.centerY - (barSize / 2)

      // Disable updates when invisible to save GPU
      visible: root.visible
    }
  }
}
