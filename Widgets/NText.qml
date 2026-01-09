import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  id: root

  property bool richTextEnabled: false
  property bool markdownTextEnabled: false
  property string family: Settings.data.ui.fontDefault
  property real pointSize: Style.fontSizeM
  property bool applyUiScale: true
  property real fontScale: {
    const fontScale = (root.family === Settings.data.ui.fontDefault ? Settings.data.ui.fontDefaultScale : Settings.data.ui.fontFixedScale);
    if (applyUiScale) {
      return fontScale * Style.uiScaleRatio;
    }
    return fontScale;
  }

  font.family: root.family
  font.weight: Style.fontWeightMedium
  font.pointSize: Math.max(1, root.pointSize * fontScale)
  color: Color.mOnSurface
  elide: Text.ElideRight
  wrapMode: Text.NoWrap
  verticalAlignment: Text.AlignVCenter

  textFormat: {
    if (root.richTextEnabled) {
      return Text.RichText;
    } else if (root.markdownTextEnabled) {
      return Text.MarkdownText;
    }
    return Text.PlainText;
  }
}
