import QtQuick
import qs.Commons
import qs.Widgets

Text {
  text: "question_mark"
  font.family: "Material Symbols Rounded"
  font.pointSize: Style.fontSizeLarge * scaling
  font.variableAxes: {
    "wght"// slightly bold to ensure all lines looks good
    : (Font.Normal + Font.Bold) / 2.5
  }
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
}
