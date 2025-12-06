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

  NHeader {
    label: I18n.tr("settings.general.profile.section.label")
    description: I18n.tr("settings.general.profile.section.description")
  }

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
      label: I18n.tr("settings.general.profile.picture.label", {
                       "user": HostService.displayName
                     })
      description: I18n.tr("settings.general.profile.picture.description")
      text: Settings.data.general.avatarImage
      placeholderText: I18n.tr("placeholders.profile-picture-path")
      buttonIcon: "photo"
      buttonTooltip: I18n.tr("settings.general.profile.tooltip")
      onInputEditingFinished: Settings.data.general.avatarImage = text
      onButtonClicked: {
        avatarPicker.openFilePicker();
      }
    }
  }

  NFilePicker {
    id: avatarPicker
    title: I18n.tr("settings.general.profile.select-avatar")
    selectionMode: "files"
    initialPath: Settings.preprocessPath(Settings.data.general.avatarImage).substr(0, Settings.preprocessPath(Settings.data.general.avatarImage).lastIndexOf("/")) || Quickshell.env("HOME")
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.general.avatarImage = paths[0];
                  }
                }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Fonts
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.general.fonts.section.label")
      description: I18n.tr("settings.general.fonts.section.description")
    }

    // Font configuration section
    ColumnLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NSearchableComboBox {
        label: I18n.tr("settings.general.fonts.default.label")
        description: I18n.tr("settings.general.fonts.default.description")
        model: FontService.availableFonts
        currentKey: Settings.data.ui.fontDefault
        placeholder: I18n.tr("settings.general.fonts.default.placeholder")
        searchPlaceholder: I18n.tr("settings.general.fonts.default.search-placeholder")
        popupHeight: 420
        minimumWidth: 300
        onSelected: function (key) {
          Settings.data.ui.fontDefault = key;
        }
      }

      NSearchableComboBox {
        label: I18n.tr("settings.general.fonts.monospace.label")
        description: I18n.tr("settings.general.fonts.monospace.description")
        model: FontService.monospaceFonts
        currentKey: Settings.data.ui.fontFixed
        placeholder: I18n.tr("settings.general.fonts.monospace.placeholder")
        searchPlaceholder: I18n.tr("settings.general.fonts.monospace.search-placeholder")
        popupHeight: 320
        minimumWidth: 300
        onSelected: function (key) {
          Settings.data.ui.fontFixed = key;
        }
      }

      ColumnLayout {
        NLabel {
          label: I18n.tr("settings.general.fonts.default.scale.label")
          description: I18n.tr("settings.general.fonts.default.scale.description")
        }

        RowLayout {
          spacing: Style.marginL
          Layout.fillWidth: true

          NValueSlider {
            Layout.fillWidth: true
            from: 0.75
            to: 1.25
            stepSize: 0.01
            value: Settings.data.ui.fontDefaultScale
            onMoved: value => Settings.data.ui.fontDefaultScale = value
            text: Math.floor(Settings.data.ui.fontDefaultScale * 100) + "%"
          }

          // Reset button container
          Item {
            Layout.preferredWidth: 30 * Style.uiScaleRatio
            Layout.preferredHeight: 30 * Style.uiScaleRatio

            NIconButton {
              icon: "refresh"
              baseSize: Style.baseWidgetSize * 0.8
              tooltipText: I18n.tr("settings.general.fonts.reset-scaling")
              onClicked: Settings.data.ui.fontDefaultScale = 1.0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      ColumnLayout {
        NLabel {
          label: I18n.tr("settings.general.fonts.monospace.scale.label")
          description: I18n.tr("settings.general.fonts.monospace.scale.description")
        }

        RowLayout {
          spacing: Style.marginL
          Layout.fillWidth: true

          NValueSlider {
            Layout.fillWidth: true
            from: 0.75
            to: 1.25
            stepSize: 0.01
            value: Settings.data.ui.fontFixedScale
            onMoved: value => Settings.data.ui.fontFixedScale = value
            text: Math.floor(Settings.data.ui.fontFixedScale * 100) + "%"
          }

          // Reset button container
          Item {
            Layout.preferredWidth: 30 * Style.uiScaleRatio
            Layout.preferredHeight: 30 * Style.uiScaleRatio

            NIconButton {
              icon: "refresh"
              baseSize: Style.baseWidgetSize * 0.8
              tooltipText: I18n.tr("settings.general.fonts.reset-scaling")
              onClicked: Settings.data.ui.fontFixedScale = 1.0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Language selection
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.general.language.section.label")
      description: I18n.tr("settings.general.language.section.description")
    }

    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("settings.general.language.select.label")
      description: I18n.tr("settings.general.language.select.description")
      model: [
        {
          "key": "",
          "name": I18n.tr("settings.general.language.select.auto-detect") + " (" + I18n.systemDetectedLangCode + ")"
        }
      ].concat(I18n.availableLanguages.map(function (langCode) {
        return {
          "key": langCode,
          "name": langCode
        };
      }))
      currentKey: Settings.data.general.language
      onSelected: key => {
                    Settings.data.general.language = key;
                    if (key === "") {
                      I18n.detectLanguage(); // Re-detect system language if "Automatic" is selected
                    } else {
                      I18n.setLanguage(key); // Set specific language
                    }
                  }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  NButton {
    visible: !HostService.isNixOS
    text: I18n.tr("settings.general.launch-setup-wizard")
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
