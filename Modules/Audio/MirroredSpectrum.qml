import QtQuick
import qs.Commons

Item {
  id: root
  property color fillColor: Color.mPrimary
  property color strokeColor: Color.mOnSurface
  property int strokeWidth: 0
  property var values: []

  // Pre-compute mirroring
  readonly property int valuesCount: values.length
  readonly property int totalBars: valuesCount * 2
  readonly property real barSlotWidth: totalBars > 0 ? width / totalBars : 0

  readonly property real centerY: height / 2

  Repeater {
    model: root.totalBars

    Rectangle {
      // The first half of bars are a mirror image (reversed values array).
      // The second half of bars are in normal order.
      property int valueIndex: index < root.valuesCount ? root.valuesCount - 1 - index // Mirrored half
                                                        : index - root.valuesCount // Normal half

      property real amp: root.values[valueIndex]

      property real barHeight: root.height * amp

      color: root.fillColor
      border.color: root.strokeColor
      border.width: root.strokeWidth
      antialiasing: true

      width: root.barSlotWidth * 0.8 // Creates a small gap between bars
      height: barHeight
      x: index * root.barSlotWidth + (root.barSlotWidth * 0.25)
      y: root.centerY - (barHeight / 2)
    }
  }
}
