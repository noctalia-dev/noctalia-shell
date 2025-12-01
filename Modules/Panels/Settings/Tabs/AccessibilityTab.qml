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

        // Source
        NComboBox {
        label: I18n.tr("settings.accessibility.virtual-keyboard.position.label")
        description: I18n.tr("settings.accessibility.virtual-keyboard.position.description")
        model: [
            {
            "key": "top",
            "name": I18n.tr("options.accessibility.virtual-keyboard.position.top")
            },
            {
            "key": "bottom",
            "name": I18n.tr("options.accessibility.virtual-keyboard.position.bottom")
            }
        ]
        currentKey: Settings.data.virtualKeyboard.keyboardLocation
        onSelected: key => Settings.data.virtualKeyboard.keyboardLocation = key
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
                onClicked: PanelService.getPanel("keyboardPanel", screen)?.toggle()
            }
            }
    }
}