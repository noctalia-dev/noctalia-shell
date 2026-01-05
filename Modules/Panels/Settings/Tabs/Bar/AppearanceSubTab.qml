import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.bar.appearance.section.label")
    description: I18n.tr("settings.bar.appearance.section.description")
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.position.label")
    description: I18n.tr("settings.bar.appearance.position.description")
    model: [
      {
        "key": "top",
        "name": I18n.tr("options.bar.position.top")
      },
      {
        "key": "bottom",
        "name": I18n.tr("options.bar.position.bottom")
      },
      {
        "key": "left",
        "name": I18n.tr("options.bar.position.left")
      },
      {
        "key": "right",
        "name": I18n.tr("options.bar.position.right")
      }
    ]
    currentKey: Settings.data.bar.position
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.position")
    onSelected: key => Settings.data.bar.position = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.density.label")
    description: I18n.tr("settings.bar.appearance.density.description")
    model: [
      {
        "key": "mini",
        "name": I18n.tr("options.bar.density.mini")
      },
      {
        "key": "compact",
        "name": I18n.tr("options.bar.density.compact")
      },
      {
        "key": "default",
        "name": I18n.tr("options.bar.density.default")
      },
      {
        "key": "comfortable",
        "name": I18n.tr("options.bar.density.comfortable")
      },
      {
        "key": "spacious",
        "name": I18n.tr("options.bar.density.spacious")
      }
    ]
    currentKey: Settings.data.bar.density
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.density")
    onSelected: key => Settings.data.bar.density = key
  }

  NToggle {
    label: I18n.tr("settings.bar.appearance.use-separate-opacity.label")
    description: I18n.tr("settings.bar.appearance.use-separate-opacity.description")
    checked: Settings.data.bar.useSeparateOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.useSeparateOpacity")
    onToggled: checked => Settings.data.bar.useSeparateOpacity = checked
  }

  NValueSlider {
    Layout.fillWidth: true
    visible: Settings.data.bar.useSeparateOpacity
    label: I18n.tr("settings.bar.appearance.background-opacity.label")
    description: I18n.tr("settings.bar.appearance.background-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.bar.backgroundOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.backgroundOpacity")
    onMoved: value => Settings.data.bar.backgroundOpacity = value
    text: Math.floor(Settings.data.bar.backgroundOpacity * 100) + "%"
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.show-outline.label")
    description: I18n.tr("settings.bar.appearance.show-outline.description")
    checked: Settings.data.bar.showOutline
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.showOutline")
    onToggled: checked => Settings.data.bar.showOutline = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.show-capsule.label")
    description: I18n.tr("settings.bar.appearance.show-capsule.description")
    checked: Settings.data.bar.showCapsule
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.showCapsule")
    onToggled: checked => Settings.data.bar.showCapsule = checked
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginXXS
    visible: Settings.data.bar.showCapsule

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.bar.appearance.capsule-opacity.label")
      description: I18n.tr("settings.bar.appearance.capsule-opacity.description")
      from: 0
      to: 1
      stepSize: 0.01
      value: Settings.data.bar.capsuleOpacity
      isSettings: true
      defaultValue: Settings.getDefaultValue("bar.capsuleOpacity")
      onMoved: value => Settings.data.bar.capsuleOpacity = value
      text: Math.floor(Settings.data.bar.capsuleOpacity * 100) + "%"
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.floating.label")
    description: I18n.tr("settings.bar.appearance.floating.description")
    checked: Settings.data.bar.floating
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.floating")
    onToggled: checked => {
                 Settings.data.bar.floating = checked;
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.outer-corners.label")
    description: I18n.tr("settings.bar.appearance.outer-corners.description")
    checked: Settings.data.bar.outerCorners
    visible: !Settings.data.bar.floating
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.outerCorners")
    onToggled: checked => Settings.data.bar.outerCorners = checked
  }

  ColumnLayout {
    visible: Settings.data.bar.floating
    spacing: Style.marginS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.bar.appearance.margins.label")
      description: I18n.tr("settings.bar.appearance.margins.description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginL

      ColumnLayout {
        spacing: Style.marginXXS

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("settings.bar.appearance.margins.vertical")
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginVertical
          isSettings: true
          defaultValue: Settings.getDefaultValue("bar.marginVertical")
          onMoved: value => Settings.data.bar.marginVertical = value
          text: Math.round(Settings.data.bar.marginVertical * 100) + "%"
        }
      }

      ColumnLayout {
        spacing: Style.marginXXS

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("settings.bar.appearance.margins.horizontal")
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginHorizontal
          isSettings: true
          defaultValue: Settings.getDefaultValue("bar.marginHorizontal")
          onMoved: value => Settings.data.bar.marginHorizontal = value
          text: Math.ceil(Settings.data.bar.marginHorizontal * 100) + "%"
        }
      }
    }
  }
}
