import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Media
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  panelContent: Item {
    id: panelContent

    // Volume state (lazy-loaded with panelContent)
    property real localOutputVolume: AudioService.volume || 0
    property bool localOutputVolumeChanging: false
    property int lastSinkId: -1

    property real localInputVolume: AudioService.inputVolume || 0
    property bool localInputVolumeChanging: false
    property int lastSourceId: -1

    // UI state (lazy-loaded with panelContent)
    property int currentTabIndex: 0

    Component.onCompleted: {
      var vol = AudioService.volume;
      localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
      var inputVol = AudioService.inputVolume;
      localInputVolume = (inputVol !== undefined && !isNaN(inputVol)) ? inputVol : 0;
      if (AudioService.sink) {
        lastSinkId = AudioService.sink.id;
      }
      if (AudioService.source) {
        lastSourceId = AudioService.source.id;
      }
    }

    // Reset local volume when device changes - use current device's volume
    Connections {
      target: AudioService
      function onSinkChanged() {
        if (AudioService.sink) {
          const newSinkId = AudioService.sink.id;
          if (newSinkId !== panelContent.lastSinkId) {
            panelContent.lastSinkId = newSinkId;
            // Immediately set local volume to current device's volume
            var vol = AudioService.volume;
            panelContent.localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
          }
        } else {
          panelContent.lastSinkId = -1;
          panelContent.localOutputVolume = 0;
        }
      }
    }

    Connections {
      target: AudioService
      function onSourceChanged() {
        if (AudioService.source) {
          const newSourceId = AudioService.source.id;
          if (newSourceId !== panelContent.lastSourceId) {
            panelContent.lastSourceId = newSourceId;
            // Immediately set local volume to current device's volume
            var vol = AudioService.inputVolume;
            panelContent.localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
          }
        } else {
          panelContent.lastSourceId = -1;
          panelContent.localInputVolume = 0;
        }
      }
    }

    // Connections to update local volumes when AudioService changes
    Connections {
      target: AudioService
      function onVolumeChanged() {
        if (!panelContent.localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === panelContent.lastSinkId) {
          var vol = AudioService.volume;
          panelContent.localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
        }
      }
    }

    Connections {
      target: AudioService.sink?.audio ? AudioService.sink?.audio : null
      function onVolumeChanged() {
        if (!panelContent.localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === panelContent.lastSinkId) {
          var vol = AudioService.volume;
          panelContent.localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
        }
      }
    }

    Connections {
      target: AudioService
      function onInputVolumeChanged() {
        if (!panelContent.localInputVolumeChanging && AudioService.source && AudioService.source.id === panelContent.lastSourceId) {
          var vol = AudioService.inputVolume;
          panelContent.localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
        }
      }
    }

    Connections {
      target: AudioService.source?.audio ? AudioService.source?.audio : null
      function onVolumeChanged() {
        if (!panelContent.localInputVolumeChanging && AudioService.source && AudioService.source.id === panelContent.lastSourceId) {
          var vol = AudioService.inputVolume;
          panelContent.localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
        }
      }
    }

    // Timer to debounce volume changes
    // Only sync if the device hasn't changed (check by comparing IDs)
    Timer {
      interval: 100
      running: true
      repeat: true
      onTriggered: {
        // Only sync if sink hasn't changed
        if (AudioService.sink && AudioService.sink.id === panelContent.lastSinkId) {
          if (Math.abs(panelContent.localOutputVolume - AudioService.volume) >= 0.01) {
            AudioService.setVolume(panelContent.localOutputVolume);
          }
        }
        // Only sync if source hasn't changed
        if (AudioService.source && AudioService.source.id === panelContent.lastSourceId) {
          if (Math.abs(panelContent.localInputVolume - AudioService.inputVolume) >= 0.01) {
            AudioService.setInputVolume(panelContent.localInputVolume);
          }
        }
      }
    }

    // Find application streams that are actually playing audio (connected to default sink)
    // Use linkGroups to find nodes connected to the default audio sink
    // Note: We need to use link IDs since source/target properties require binding
    readonly property var appStreams: AudioService.appStreams

    // Use implicitHeight from content + margins to avoid binding loops
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + (Style.marginXL)

        ColumnLayout {
          id: header
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          RowLayout {
            NIcon {
              icon: "settings-audio"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("panels.audio.title")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                root.close();
              }
            }
          }

          NTabBar {
            id: tabBar
            Layout.fillWidth: true
            margins: Style.marginS
            currentIndex: panelContent.currentTabIndex
            distributeEvenly: true
            onCurrentIndexChanged: panelContent.currentTabIndex = currentIndex

            NTabButton {
              text: I18n.tr("common.volumes")
              tabIndex: 0
              checked: tabBar.currentIndex === 0
            }

            NTabButton {
              text: I18n.tr("common.devices")
              tabIndex: 1
              checked: tabBar.currentIndex === 1
            }
          }
        }
      }

      // Content Stack
      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: panelContent.currentTabIndex

        // Applications Tab (Volume)
        NScrollView {
          id: volumeScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          contentWidth: availableWidth
          reserveScrollbarSpace: false
          gradientColor: Color.mSurface

          ColumnLayout {
            spacing: Style.marginM
            width: volumeScrollView.availableWidth

            // Output Volume
            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: outputVolumeColumn.implicitHeight + (Style.marginXL)

              ColumnLayout {
                id: outputVolumeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginM

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  NText {
                    text: I18n.tr("common.output")
                    pointSize: Style.fontSizeM
                    color: Color.mPrimary
                  }

                  NText {
                    text: AudioService.sink ? (" - " + (AudioService.sink.description || AudioService.sink.name || "")) : ""
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginM

                  NValueSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                    value: localOutputVolume
                    stepSize: 0.01
                    heightRatio: 0.5
                    onMoved: function (value) {
                      localOutputVolume = value;
                    }
                    onPressedChanged: function (pressed) {
                      localOutputVolumeChanging = pressed;
                    }
                  }

                  NText {
                    text: Math.round(localOutputVolume * 100) + "%"
                    pointSize: Style.fontSizeM
                    family: Settings.data.ui.fontFixed
                    color: Color.mOnSurface
                    opacity: enabled ? 1.0 : 0.6
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 45 * Style.uiScaleRatio
                    horizontalAlignment: Text.AlignRight
                  }

                  NIconButton {
                    icon: AudioService.getOutputIcon()
                    tooltipText: I18n.tr("tooltips.output-muted")
                    baseSize: Style.baseWidgetSize * 0.7
                    onClicked: {
                      AudioService.suppressOutputOSD();
                      AudioService.setOutputMuted(!AudioService.muted);
                    }
                  }
                }
              }
            }

            // Input Volume
            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: inputVolumeColumn.implicitHeight + (Style.marginXL)

              ColumnLayout {
                id: inputVolumeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginM

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  NText {
                    text: I18n.tr("common.input")
                    pointSize: Style.fontSizeM
                    color: Color.mPrimary
                  }

                  NText {
                    text: AudioService.source ? (" - " + (AudioService.source.description || AudioService.source.name || "")) : ""
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginM

                  NValueSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                    value: localInputVolume
                    stepSize: 0.01
                    heightRatio: 0.5
                    onMoved: function (value) {
                      localInputVolume = value;
                    }
                    onPressedChanged: function (pressed) {
                      localInputVolumeChanging = pressed;
                    }
                  }

                  NText {
                    text: Math.round(localInputVolume * 100) + "%"
                    pointSize: Style.fontSizeM
                    family: Settings.data.ui.fontFixed
                    color: Color.mOnSurface
                    opacity: enabled ? 1.0 : 0.6
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 45 * Style.uiScaleRatio
                    horizontalAlignment: Text.AlignRight
                  }

                  NIconButton {
                    icon: AudioService.getInputIcon()
                    tooltipText: I18n.tr("tooltips.input-muted")
                    baseSize: Style.baseWidgetSize * 0.7
                    onClicked: {
                      AudioService.suppressInputOSD();
                      AudioService.setInputMuted(!AudioService.inputMuted);
                    }
                  }
                }
              }
            }

            // Bind all app stream nodes to access their audio properties
            PwObjectTracker {
              id: appStreamsTracker
              objects: panelContent.appStreams
            }

            Repeater {
              model: panelContent.appStreams

              NBox {
                id: appBox
                required property PwNode modelData
                Layout.fillWidth: true
                Layout.preferredHeight: appRow.implicitHeight + (Style.marginXL)
                visible: !isCaptureStream

                // Track individual node to ensure properties are bound
                PwObjectTracker {
                  objects: modelData ? [modelData] : []
                }

                property PwNodeAudio nodeAudio: (modelData && modelData.audio) ? modelData.audio : null
                property real appVolume: (nodeAudio && nodeAudio.volume !== undefined) ? nodeAudio.volume : 0.0
                property bool appMuted: (nodeAudio && nodeAudio.muted !== undefined) ? nodeAudio.muted : false

                // Check if this is a capture stream (after node is bound)
                readonly property bool isCaptureStream: {
                  if (!modelData || !modelData.properties)
                    return false;
                  const props = modelData.properties;
                  // Exclude capture streams - check for stream.capture.sink property
                  if (props["stream.capture.sink"] !== undefined) {
                    return true;
                  }
                  const mediaClass = props["media.class"] || "";
                  // Exclude Stream/Input (capture) but allow Stream/Output (playback)
                  if (mediaClass.includes("Capture") || mediaClass === "Stream/Input" || mediaClass === "Stream/Input/Audio") {
                    return true;
                  }
                  const mediaRole = props["media.role"] || "";
                  if (mediaRole === "Capture") {
                    return true;
                  }
                  return false;
                }

                // Helper function to validate if a fuzzy match is actually related
                function isValidMatch(searchTerm, entry) {
                  if (!entry)
                    return false;
                  var search = searchTerm.toLowerCase();
                  var id = (entry.id || "").toLowerCase();
                  var name = (entry.name || "").toLowerCase();
                  var icon = (entry.icon || "").toLowerCase();
                  // Match is valid if search term appears in entry or entry appears in search
                  return id.includes(search) || name.includes(search) || icon.includes(search) || search.includes(id.split('.').pop()) || search.includes(name.replace(/\s+/g, ''));
                }

                readonly property string appName: {
                  if (!modelData)
                    return "Unknown App";

                  var props = modelData.properties;
                  var desc = modelData.description || "";
                  var name = modelData.name || "";

                  if (!props) {
                    if (desc)
                      return desc;
                    if (name) {
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0 && nameParts[0])
                        return nameParts[0].charAt(0).toUpperCase() + nameParts[0].slice(1);
                      return name;
                    }
                    return "Unknown App";
                  }

                  var binaryName = props["application.process.binary"] || "";

                  // Try binary name first (fixes Electron apps like vesktop)
                  if (binaryName) {
                    var binParts = binaryName.split("/");
                    if (binParts.length > 0) {
                      var binName = binParts[binParts.length - 1].toLowerCase();
                      var entry = ThemeIcons.findAppEntry(binName);
                      // Only use entry if it's actually related to binary name
                      if (entry && entry.name && isValidMatch(binName, entry))
                        return entry.name;
                    }
                  }

                  var computedAppName = props["application.name"] || "";
                  var mediaName = props["media.name"] || "";
                  var mediaTitle = props["media.title"] || "";
                  var appId = props["application.id"] || "";

                  if (appId) {
                    var entry = ThemeIcons.findAppEntry(appId);
                    if (entry && entry.name && isValidMatch(appId, entry))
                      return entry.name;
                    if (!computedAppName) {
                      var parts = appId.split(".");
                      if (parts.length > 0 && parts[0])
                        computedAppName = parts[0].charAt(0).toUpperCase() + parts[0].slice(1);
                    }
                  }

                  if (!computedAppName && binaryName) {
                    var binParts = binaryName.split("/");
                    if (binParts.length > 0 && binParts[binParts.length - 1])
                      computedAppName = binParts[binParts.length - 1].charAt(0).toUpperCase() + binParts[binParts.length - 1].slice(1);
                  }

                  var result = computedAppName || mediaTitle || mediaName || binaryName || desc || name;

                  if (!result || result === "" || result === "Unknown App") {
                    if (name) {
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0 && nameParts[0])
                        result = nameParts[0].charAt(0).toUpperCase() + nameParts[0].slice(1);
                    }
                  }

                  return result || "Unknown App";
                }

                readonly property string appIcon: {
                  if (!modelData)
                    return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");

                  var props = modelData.properties;

                  if (!props) {
                    var name = modelData.name || "";
                    if (name) {
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0) {
                        var entry = ThemeIcons.findAppEntry(nameParts[0].toLowerCase());
                        if (entry && entry.icon && isValidMatch(nameParts[0].toLowerCase(), entry))
                          return ThemeIcons.iconFromName(entry.icon, "application-x-executable");
                      }
                    }
                    return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");
                  }

                  var binaryName = props["application.process.binary"] || "";
                  if (binaryName) {
                    var binParts = binaryName.split("/");
                    if (binParts.length > 0) {
                      var binName = binParts[binParts.length - 1].toLowerCase();
                      var entry = ThemeIcons.findAppEntry(binName);
                      if (entry && entry.icon && isValidMatch(binName, entry))
                        return ThemeIcons.iconFromName(entry.icon, "");
                    }
                  }

                  var iconName = props["application.icon-name"] || "";
                  if (iconName && ThemeIcons.iconExists(iconName)) {
                    var iconPath = ThemeIcons.iconFromName(iconName, "");
                    if (iconPath && iconPath !== "")
                      return iconPath;
                  }

                  var appId = props["application.id"] || "";
                  if (appId) {
                    var entry = ThemeIcons.findAppEntry(appId);
                    if (entry && entry.icon && isValidMatch(appId, entry))
                      return ThemeIcons.iconFromName(entry.icon, "");
                  }

                  var appName = props["application.name"] || "";
                  if (appName) {
                    var entry = ThemeIcons.findAppEntry(appName.toLowerCase());
                    if (entry && entry.icon && isValidMatch(appName.toLowerCase(), entry))
                      return ThemeIcons.iconFromName(entry.icon, "");
                  }

                  var name = modelData.name || "";
                  if (name) {
                    var nameParts = name.split(/[-_]/);
                    if (nameParts.length > 0) {
                      var entry = ThemeIcons.findAppEntry(nameParts[0].toLowerCase());
                      if (entry && entry.icon && isValidMatch(nameParts[0].toLowerCase(), entry))
                        return ThemeIcons.iconFromName(entry.icon, "");
                    }
                  }

                  return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");
                }

                RowLayout {
                  id: appRow
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginM

                  // App Icon
                  IconImage {
                    id: appIconImage
                    Layout.preferredWidth: Style.baseWidgetSize
                    Layout.preferredHeight: Style.baseWidgetSize
                    source: appBox.appIcon
                    smooth: true
                    asynchronous: true

                    // Fallback icon if image fails to load
                    NIcon {
                      anchors.fill: parent
                      icon: "apps"
                      pointSize: Style.fontSizeXL
                      color: Color.mPrimary
                      visible: appIconImage.status === Image.Error || appIconImage.status === Image.Null || appBox.appIcon === ""
                    }
                  }

                  // App Name and Volume Slider
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS

                    NText {
                      text: appBox.appName || "Unknown App"
                      pointSize: Style.fontSizeM
                      color: Color.mOnSurface
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.marginM

                      NValueSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                        value: (appBox.appVolume !== undefined) ? appBox.appVolume : 0.0
                        stepSize: 0.01
                        heightRatio: 0.5
                        enabled: !!(appBox.nodeAudio && appBox.modelData && appBox.modelData.ready === true)
                        onMoved: function (value) {
                          if (appBox.nodeAudio && appBox.modelData && appBox.modelData.ready === true) {
                            appBox.nodeAudio.volume = value;
                          }
                        }
                      }

                      NText {
                        text: Math.round((appBox.appVolume !== undefined ? appBox.appVolume : 0.0) * 100) + "%"
                        pointSize: Style.fontSizeM
                        family: Settings.data.ui.fontFixed
                        color: Color.mOnSurface
                        opacity: enabled ? 1.0 : 0.6
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 45 * Style.uiScaleRatio
                        horizontalAlignment: Text.AlignRight
                        enabled: !!(appBox.nodeAudio && appBox.modelData && appBox.modelData.ready === true)
                      }

                      // Mute Button
                      NIconButton {
                        icon: (appBox.appMuted === true) ? "volume-mute" : "volume-high"
                        tooltipText: (appBox.appMuted === true) ? I18n.tr("tooltips.unmute") : I18n.tr("tooltips.mute")
                        baseSize: Style.baseWidgetSize * 0.7
                        enabled: !!(appBox.nodeAudio && appBox.modelData && appBox.modelData.ready === true)
                        onClicked: {
                          if (appBox.nodeAudio && appBox.modelData && appBox.modelData.ready === true) {
                            appBox.nodeAudio.muted = !appBox.appMuted;
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Empty state
            NText {
              visible: panelContent.appStreams.length === 0
              text: I18n.tr("panels.audio.panel-applications-empty")
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignHCenter
              Layout.fillWidth: true
              Layout.topMargin: Style.marginXL
            }
          }
        }

        // Devices Tab
        NScrollView {
          id: devicesScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          contentWidth: availableWidth
          reserveScrollbarSpace: false
          gradientColor: Color.mSurface

          // AudioService Devices
          ColumnLayout {
            spacing: Style.marginM
            width: devicesScrollView.availableWidth

            // -------------------------------
            // Output Devices
            ButtonGroup {
              id: sinks
            }

            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: outputColumn.implicitHeight + (Style.marginXL)

              ColumnLayout {
                id: outputColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginS

                NText {
                  text: I18n.tr("panels.audio.devices-output-device-label")
                  pointSize: Style.fontSizeL
                  color: Color.mPrimary
                }

                Repeater {
                  model: AudioService.sinks
                  NRadioButton {
                    ButtonGroup.group: sinks
                    required property PwNode modelData
                    pointSize: Style.fontSizeS
                    text: modelData.description
                    checked: AudioService.sink?.id === modelData.id
                    onClicked: {
                      AudioService.setAudioSink(modelData);
                      localOutputVolume = AudioService.volume;
                    }
                    Layout.fillWidth: true
                  }
                }
              }
            }

            // -------------------------------
            // Input Devices
            ButtonGroup {
              id: sources
            }

            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: inputColumn.implicitHeight + (Style.marginXL)

              ColumnLayout {
                id: inputColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: Style.marginM
                spacing: Style.marginS

                NText {
                  text: I18n.tr("panels.audio.devices-input-device-label")
                  pointSize: Style.fontSizeL
                  color: Color.mPrimary
                }

                Repeater {
                  model: AudioService.sources
                  NRadioButton {
                    ButtonGroup.group: sources
                    required property PwNode modelData
                    pointSize: Style.fontSizeS
                    text: modelData.description
                    checked: AudioService.source?.id === modelData.id
                    onClicked: AudioService.setAudioSource(modelData)
                    Layout.fillWidth: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
