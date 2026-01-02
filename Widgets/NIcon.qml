import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Text {
  id: root

  property string icon: Icons.defaultIcon
  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true

  visible: (icon !== undefined) && (icon !== "")
  text: {
    if ((icon === undefined) || (icon === "")) {
      return "";
    }
    if (Icons.get(icon) === undefined) {
      Logger.w("Icon", `"${icon}"`, "doesn't exist in the icons font");
      Logger.callStack();
      return Icons.get(Icons.defaultIcon);
    }
    return Icons.get(icon);
  }
  font.family: Icons.fontFamily
  font.pointSize: Math.max(1, applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
  color: Color.mOnSurface
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter
}
