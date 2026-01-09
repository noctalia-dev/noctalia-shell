import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  // Profile section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginL

    // Avatar preview
    NImageRounded {
      Layout.preferredWidth: 88 * Style.uiScaleRatio
      Layout.preferredHeight: width
      radius: width / 2
      imagePath: Settings.preprocessPath(Settings.data.general.avatarImage)
      fallbackIcon: "person"
      borderColor: Color.mPrimary
      borderWidth: Style.borderM
      Layout.alignment: Qt.AlignTop
    }

    NTextInputButton {
      label: I18n.tr("panels.general.profile-picture-label", {
                       "user": HostService.displayName
                     })
      description: I18n.tr("panels.general.profile-picture-description")
      text: Settings.data.general.avatarImage
      placeholderText: '~/.face' // don't translate path
      buttonIcon: "photo"
      buttonTooltip: I18n.tr("panels.general.profile-tooltip")
      onInputEditingFinished: Settings.data.general.avatarImage = text
      onButtonClicked: {
        avatarPicker.openFilePicker();
      }
    }
  }

  NFilePicker {
    id: avatarPicker
    title: I18n.tr("panels.general.profile-select-avatar")
    selectionMode: "files"
    initialPath: Settings.preprocessPath(Settings.data.general.avatarImage).substr(0, Settings.preprocessPath(Settings.data.general.avatarImage).lastIndexOf("/")) || Quickshell.env("HOME")
    nameFilters: ImageCacheService.basicImageFilters
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.general.avatarImage = paths[0];
                  }
                }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // Fonts
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    // Font configuration section
    ColumnLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NSearchableComboBox {
        label: I18n.tr("panels.general.fonts-default-label")
        description: I18n.tr("panels.general.fonts-default-description")
        model: FontService.availableFonts
        currentKey: Settings.data.ui.fontDefault
        placeholder: I18n.tr("panels.general.fonts-default-placeholder")
        searchPlaceholder: I18n.tr("panels.general.fonts-default-search-placeholder")
        popupHeight: 420
        defaultValue: Settings.getDefaultValue("ui.fontDefault")
        settingsPath: "ui.fontDefault"
        onSelected: key => Settings.data.ui.fontDefault = key
      }

      NSearchableComboBox {
        label: I18n.tr("panels.general.fonts-monospace-label")
        description: I18n.tr("panels.general.fonts-monospace-description")
        model: FontService.monospaceFonts
        currentKey: Settings.data.ui.fontFixed
        placeholder: I18n.tr("panels.general.fonts-monospace-placeholder")
        searchPlaceholder: I18n.tr("panels.general.fonts-monospace-search-placeholder")
        popupHeight: 320
        defaultValue: Settings.getDefaultValue("ui.fontFixed")
        settingsPath: "ui.fontFixed"
        onSelected: key => Settings.data.ui.fontFixed = key
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("panels.general.fonts-default-scale-label")
          description: I18n.tr("panels.general.fonts-default-scale-description")
          from: 0.75
          to: 1.25
          stepSize: 0.01
          value: Settings.data.ui.fontDefaultScale
          defaultValue: Settings.getDefaultValue("ui.fontDefaultScale")
          onMoved: value => Settings.data.ui.fontDefaultScale = value
          text: Math.floor(Settings.data.ui.fontDefaultScale * 100) + "%"
        }

        // Reset button container
        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "restore"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: I18n.tr("panels.general.fonts-reset-scaling")
            onClicked: Settings.data.ui.fontDefaultScale = 1.0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("panels.general.fonts-monospace-scale-label")
          description: I18n.tr("panels.general.fonts-monospace-scale-description")
          from: 0.75
          to: 1.25
          stepSize: 0.01
          value: Settings.data.ui.fontFixedScale
          defaultValue: Settings.getDefaultValue("ui.fontFixedScale")
          onMoved: value => Settings.data.ui.fontFixedScale = value
          text: Math.floor(Settings.data.ui.fontFixedScale * 100) + "%"
        }

        // Reset button container
        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "restore"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: I18n.tr("panels.general.fonts-reset-scaling")
            onClicked: Settings.data.ui.fontFixedScale = 1.0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NButton {
    visible: !HostService.isNixOS
    icon: "wand"
    text: I18n.tr("panels.general.launch-setup-wizard")
    outlined: true
    onClicked: {
      var targetScreen = PanelService.openedPanel ? PanelService.openedPanel.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
      if (!targetScreen) {
        return;
      }
      var setupPanel = PanelService.getPanel("setupWizardPanel", targetScreen);
      if (setupPanel) {
        setupPanel.open();
      } else {
        Qt.callLater(() => {
                       var sp = PanelService.getPanel("setupWizardPanel", targetScreen);
                       if (sp)
                       sp.open();
                     });
      }
    }
  }
}
