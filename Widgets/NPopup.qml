import QtQuick
import QtQuick.Controls
import qs.Services.UI

Popup {
  id: root
  onVisibleChanged: PanelService.childrenVisible(visible)
}
