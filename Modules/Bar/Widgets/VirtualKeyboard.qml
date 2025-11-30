import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

NIconButton {
    id: root
    property ShellScreen screen
    icon: "keyboard"
    MouseArea {
        anchors.fill: parent
        onPressed: {
            var panel = PanelService.getPanel("keyboardPanel", screen);
            panel?.toggle();
            Logger.i("Keyboard", "Virtual Keyboard Toggled")
        }
    }
}