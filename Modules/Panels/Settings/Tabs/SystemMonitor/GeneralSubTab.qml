import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.System

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var screen

  NToggle {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    label: I18n.tr("panels.system-monitor.enable-dgpu-monitoring-label")
    description: I18n.tr("panels.system-monitor.enable-dgpu-monitoring-description")
    checked: Settings.data.systemMonitor.enableDgpuMonitoring
    defaultValue: Settings.getDefaultValue("systemMonitor.enableDgpuMonitoring")
    onToggled: checked => Settings.data.systemMonitor.enableDgpuMonitoring = checked
  }

  NDivider {
    Layout.fillWidth: true
    visible: SystemStatService.availableGpus.length > 0
  }

  // GPU Selection Section
  NHeader {
    visible: SystemStatService.availableGpus.length > 0
    label: I18n.tr("panels.system-monitor.gpu-selection-label")
    description: I18n.tr("panels.system-monitor.gpu-selection-description")
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    visible: SystemStatService.availableGpus.length > 0

    // Auto selection radio button
    NRadioButton {
      id: autoRadio
      text: I18n.tr("panels.system-monitor.gpu-selection-auto")
      checked: Settings.data.systemMonitor.gpuSelectionMode === "auto"
      onClicked: {
        Settings.data.systemMonitor.gpuSelectionMode = "auto";
      }
    }

    // Manual selection radio button
    NRadioButton {
      id: manualRadio
      text: I18n.tr("panels.system-monitor.gpu-selection-manual")
      checked: Settings.data.systemMonitor.gpuSelectionMode === "manual"
      onClicked: {
        Settings.data.systemMonitor.gpuSelectionMode = "manual";
      }
    }

    // GPU list (visible when manual mode is selected)
    ColumnLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginXL
      spacing: Style.marginS
      visible: Settings.data.systemMonitor.gpuSelectionMode === "manual"

      Repeater {
        model: SystemStatService.availableGpus

        ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginXS

          NRadioButton {
            text: modelData.name
            checked: Settings.data.systemMonitor.selectedGpuId === modelData.id
            onClicked: {
              Settings.data.systemMonitor.selectedGpuId = modelData.id;
            }
          }

          NText {
            Layout.leftMargin: Style.marginXL
            text: {
              if (modelData.isDgpu && !Settings.data.systemMonitor.enableDgpuMonitoring) {
                return I18n.tr("panels.system-monitor.gpu-dgpu-warning-disabled");
              } else if (modelData.isDgpu) {
                return I18n.tr("panels.system-monitor.gpu-dgpu-warning");
              }
              return "";
            }
            pointSize: Style.fontSizeXS
            color: Color.mTertiary
            visible: modelData.isDgpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  // Colors Section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("panels.system-monitor.use-custom-highlight-colors-label")
      description: I18n.tr("panels.system-monitor.use-custom-highlight-colors-description")
      checked: Settings.data.systemMonitor.useCustomColors
      defaultValue: Settings.getDefaultValue("systemMonitor.useCustomColors")
      onToggled: checked => {
                   // If enabling custom colors and no custom color is saved, persist current theme colors
                   if (checked) {
                     if (!Settings.data.systemMonitor.warningColor || Settings.data.systemMonitor.warningColor === "") {
                       Settings.data.systemMonitor.warningColor = Color.mTertiary.toString();
                     }
                     if (!Settings.data.systemMonitor.criticalColor || Settings.data.systemMonitor.criticalColor === "") {
                       Settings.data.systemMonitor.criticalColor = Color.mError.toString();
                     }
                   }
                   Settings.data.systemMonitor.useCustomColors = checked;
                 }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginXL
    visible: Settings.data.systemMonitor.useCustomColors

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("panels.system-monitor.warning-color-label")
        pointSize: Style.fontSizeM
      }

      NColorPicker {
        screen: root.screen
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        enabled: Settings.data.systemMonitor.useCustomColors
        selectedColor: Settings.data.systemMonitor.warningColor || Color.mTertiary
        onColorSelected: color => Settings.data.systemMonitor.warningColor = color
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("panels.system-monitor.critical-color-label")
        pointSize: Style.fontSizeM
      }

      NColorPicker {
        screen: root.screen
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        enabled: Settings.data.systemMonitor.useCustomColors
        selectedColor: Settings.data.systemMonitor.criticalColor || Color.mError
        onColorSelected: color => Settings.data.systemMonitor.criticalColor = color
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NTextInput {
    label: I18n.tr("panels.system-monitor.external-monitor-label")
    description: I18n.tr("panels.system-monitor.external-monitor-description")
    placeholderText: I18n.tr("panels.system-monitor.external-monitor-placeholder")
    text: Settings.data.systemMonitor.externalMonitor
    defaultValue: Settings.getDefaultValue("systemMonitor.externalMonitor")
    onTextChanged: Settings.data.systemMonitor.externalMonitor = text
  }
}
