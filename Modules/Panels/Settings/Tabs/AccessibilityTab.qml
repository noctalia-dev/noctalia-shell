import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
    id: root

    NHeader {
        label: I18n.tr("settings.accessibility.general.section.label")
        description: I18n.tr("settings.accessibility.general.section.description")
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginL
        Layout.bottomMargin: Style.marginL
    }

    ColumnLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NHeader {
        label: I18n.tr("settings.accessibility.virtual-keyboard.section.label")
        description: I18n.tr("settings.accessibility.virtual-keyboard.section.description")
        }
           
        RowLayout {
            NLabel {
                label: I18n.tr("settings.accessibility.virtual-keyboard.selector.label")
                description: I18n.tr("settings.accessibility.virtual-keyboard.selector.description")
                Layout.alignment: Qt.AlignTop
            }

            NIconButton {
                icon: "keyboard"
                tooltipText: I18n.tr("settings.accessibility.virtual-keyboard.selector.tooltip")
                onClicked: Settings.data.virtualKeyboard.enabled = !Settings.data.virtualKeyboard.enabled
            }
            }
    }
}