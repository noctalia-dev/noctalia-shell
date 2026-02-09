import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  // Animation type options for per-component dropdowns
  readonly property var animationTypeOptions: [
    {
      "key": "slide",
      "name": I18n.tr("panels.user-interface.animation-type-slide")
    },
    {
      "key": "scale",
      "name": I18n.tr("panels.user-interface.animation-type-scale")
    },
    {
      "key": "fade",
      "name": I18n.tr("panels.user-interface.animation-type-fade")
    },
    {
      "key": "popin",
      "name": I18n.tr("panels.user-interface.animation-type-popin")
    },
    {
      "key": "slideFade",
      "name": I18n.tr("panels.user-interface.animation-type-slideFade")
    },
    {
      "key": "slideScale",
      "name": I18n.tr("panels.user-interface.animation-type-slideScale")
    },
    {
      "key": "none",
      "name": I18n.tr("panels.user-interface.animation-type-none")
    }
  ]

  // Preset definitions: each maps a name to 5 component animation types
  readonly property var presets: [
    {
      "key": "default",
      "name": I18n.tr("panels.user-interface.animation-style-preset-default"),
      "panels": "slideFade",
      "notifications": "slideFade",
      "osd": "scale",
      "toasts": "slide",
      "menus": "fade"
    },
    {
      "key": "fade",
      "name": I18n.tr("panels.user-interface.animation-style-preset-fade"),
      "panels": "fade",
      "notifications": "fade",
      "osd": "fade",
      "toasts": "fade",
      "menus": "fade"
    },
    {
      "key": "pop",
      "name": I18n.tr("panels.user-interface.animation-style-preset-pop"),
      "panels": "popin",
      "notifications": "popin",
      "osd": "popin",
      "toasts": "popin",
      "menus": "popin"
    },
    {
      "key": "slide",
      "name": I18n.tr("panels.user-interface.animation-style-preset-slide"),
      "panels": "slide",
      "notifications": "slide",
      "osd": "scale",
      "toasts": "slide",
      "menus": "fade"
    }
  ]

  // Derive current preset from per-component settings
  readonly property string currentPresetKey: {
    var p = Settings.data.general.panelAnimationType;
    var n = Settings.data.general.notificationAnimationType;
    var o = Settings.data.general.osdAnimationType;
    var t = Settings.data.general.toastAnimationType;
    var m = Settings.data.general.menuAnimationType;
    for (var i = 0; i < presets.length; i++) {
      var preset = presets[i];
      if (p === preset.panels && n === preset.notifications && o === preset.osd && t === preset.toasts && m === preset.menus)
        return preset.key;
    }
    return "custom";
  }

  // Build the preset dropdown model, appending "Custom" only when active
  readonly property var presetModel: {
    var model = presets.slice();
    if (currentPresetKey === "custom")
      model.push({
                   "key": "custom",
                   "name": I18n.tr("panels.user-interface.animation-style-custom")
                 });
    return model;
  }

  function applyPreset(key) {
    for (var i = 0; i < presets.length; i++) {
      var preset = presets[i];
      if (preset.key === key) {
        Settings.data.general.panelAnimationType = preset.panels;
        Settings.data.general.notificationAnimationType = preset.notifications;
        Settings.data.general.osdAnimationType = preset.osd;
        Settings.data.general.toastAnimationType = preset.toasts;
        Settings.data.general.menuAnimationType = preset.menus;
        return;
      }
    }
  }

  NToggle {
    label: I18n.tr("panels.user-interface.animation-disable-label")
    description: I18n.tr("panels.user-interface.animation-disable-description")
    checked: Settings.data.general.animationDisabled
    defaultValue: Settings.getDefaultValue("general.animationDisabled")
    onToggled: checked => Settings.data.general.animationDisabled = checked
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true
    visible: !Settings.data.general.animationDisabled

    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("panels.user-interface.animation-speed-label")
        description: I18n.tr("panels.user-interface.animation-speed-description")
        from: 0
        to: 2.0
        stepSize: 0.01
        value: Settings.data.general.animationSpeed
        defaultValue: Settings.getDefaultValue("general.animationSpeed")
        onMoved: value => Settings.data.general.animationSpeed = Math.max(value, 0.05)
      }

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("panels.user-interface.animation-speed-reset")
        onClicked: Settings.data.general.animationSpeed = 1.0
        Layout.alignment: Qt.AlignBottom
      }
    }

    NDivider {
      Layout.fillWidth: true
    }

    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NComboBox {
        label: I18n.tr("panels.user-interface.animation-style-label")
        description: I18n.tr("panels.user-interface.animation-style-description")
        Layout.fillWidth: true
        model: root.presetModel
        currentKey: root.currentPresetKey
        defaultValue: "default"
        onSelected: key => {
                      if (key !== "custom")
                      root.applyPreset(key);
                    }
      }

      Item {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio

        NIconButton {
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("panels.user-interface.animation-speed-reset")
          onClicked: root.applyPreset("default")
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    NDivider {
      Layout.fillWidth: true
    }

    NText {
      text: I18n.tr("panels.user-interface.animation-style-advanced")
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightSemiBold
      color: Color.mOnSurface
    }

    NComboBox {
      label: I18n.tr("panels.user-interface.animation-type-panels")
      description: I18n.tr("panels.user-interface.animation-type-panels-description")
      Layout.fillWidth: true
      model: animationTypeOptions
      currentKey: Settings.data.general.panelAnimationType
      defaultValue: Settings.getDefaultValue("general.panelAnimationType")
      onSelected: key => Settings.data.general.panelAnimationType = key
    }

    NComboBox {
      label: I18n.tr("panels.user-interface.animation-type-notifications")
      description: I18n.tr("panels.user-interface.animation-type-notifications-description")
      Layout.fillWidth: true
      model: animationTypeOptions
      currentKey: Settings.data.general.notificationAnimationType
      defaultValue: Settings.getDefaultValue("general.notificationAnimationType")
      onSelected: key => Settings.data.general.notificationAnimationType = key
    }

    NComboBox {
      label: I18n.tr("panels.user-interface.animation-type-osd")
      description: I18n.tr("panels.user-interface.animation-type-osd-description")
      Layout.fillWidth: true
      model: animationTypeOptions
      currentKey: Settings.data.general.osdAnimationType
      defaultValue: Settings.getDefaultValue("general.osdAnimationType")
      onSelected: key => Settings.data.general.osdAnimationType = key
    }

    NComboBox {
      label: I18n.tr("panels.user-interface.animation-type-toasts")
      description: I18n.tr("panels.user-interface.animation-type-toasts-description")
      Layout.fillWidth: true
      model: animationTypeOptions
      currentKey: Settings.data.general.toastAnimationType
      defaultValue: Settings.getDefaultValue("general.toastAnimationType")
      onSelected: key => Settings.data.general.toastAnimationType = key
    }

    NComboBox {
      label: I18n.tr("panels.user-interface.animation-type-menus")
      description: I18n.tr("panels.user-interface.animation-type-menus-description")
      Layout.fillWidth: true
      model: animationTypeOptions
      currentKey: Settings.data.general.menuAnimationType
      defaultValue: Settings.getDefaultValue("general.menuAnimationType")
      onSelected: key => Settings.data.general.menuAnimationType = key
    }
  }
}
