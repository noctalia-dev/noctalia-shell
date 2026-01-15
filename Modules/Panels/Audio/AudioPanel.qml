import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
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
    readonly property var appStreams: {
      if (!Pipewire.ready || !AudioService.sink) {
        return [];
      }

      var defaultSink = AudioService.sink;
      var defaultSinkId = defaultSink.id;
      var connectedStreamIds = {};
      var connectedStreams = [];

      // Use PwNodeLinkTracker to get properly bound link groups
      if (!sinkLinkTracker.linkGroups) {
        return [];
      }

      // Check if linkGroups is an array or ObjectModel
      var linkGroupsCount = 0;
      if (sinkLinkTracker.linkGroups.length !== undefined) {
        linkGroupsCount = sinkLinkTracker.linkGroups.length;
      } else if (sinkLinkTracker.linkGroups.count !== undefined) {
        linkGroupsCount = sinkLinkTracker.linkGroups.count;
      } else {
        return [];
      }

      if (linkGroupsCount === 0) {
        return [];
      }

      // Collect intermediate node IDs that are connected to the sink
      var intermediateNodeIds = {};

      // Process link groups from sinkLinkTracker
      var nodesToCheck = [];

      for (var i = 0; i < linkGroupsCount; i++) {
        var linkGroup;
        if (sinkLinkTracker.linkGroups.get) {
          linkGroup = sinkLinkTracker.linkGroups.get(i);
        } else {
          linkGroup = sinkLinkTracker.linkGroups[i];
        }

        if (!linkGroup || !linkGroup.source) {
          continue;
        }

        var sourceNode = linkGroup.source;

        // If it's a stream node, add it directly
        if (sourceNode.isStream && sourceNode.audio) {
          if (!connectedStreamIds[sourceNode.id]) {
            connectedStreamIds[sourceNode.id] = true;
            connectedStreams.push(sourceNode);
          }
        } else {
          // Not a stream - this is an intermediate node, track it
          intermediateNodeIds[sourceNode.id] = true;
          nodesToCheck.push(sourceNode);
        }
      }

      // If we found intermediate nodes, we need to find streams connected to them
      // Since Pipewire.linkGroups is not directly accessible, we'll use a heuristic:
      // When intermediate nodes are present, include all active stream nodes
      // (reasonable assumption: if audio is playing, streams are connected)
      if (nodesToCheck.length > 0 || connectedStreams.length === 0) {
        try {
          // Get all nodes from Pipewire
          var allNodes = [];
          if (Pipewire.nodes) {
            if (Pipewire.nodes.count !== undefined) {
              var nodeCount = Pipewire.nodes.count;
              for (var n = 0; n < nodeCount; n++) {
                var node;
                if (Pipewire.nodes.get) {
                  node = Pipewire.nodes.get(n);
                } else {
                  node = Pipewire.nodes[n];
                }
                if (node)
                  allNodes.push(node);
              }
            } else if (Pipewire.nodes.values) {
              allNodes = Pipewire.nodes.values;
            }
          }

          // Find all stream nodes
          for (var j = 0; j < allNodes.length; j++) {
            var node = allNodes[j];
            if (!node || !node.isStream || !node.audio) {
              continue;
            }

            var streamId = node.id;
            if (connectedStreamIds[streamId]) {
              continue; // Already added
            }

            // When intermediate nodes are present, include all stream nodes
            // This is a reasonable heuristic since if audio is playing, they're likely connected
            if (Object.keys(intermediateNodeIds).length > 0) {
              connectedStreamIds[streamId] = true;
              connectedStreams.push(node);
            } else if (connectedStreams.length === 0) {
              // Fallback: if no streams found yet, include as fallback
              connectedStreamIds[streamId] = true;
              connectedStreams.push(node);
            }
          }
        } catch (e)
          // Error finding stream nodes - continue with what we have
        {}
      }

      return connectedStreams;
    }

    // Track links to the default sink using PwNodeLinkTracker (properly binds links)
    PwNodeLinkTracker {
      id: sinkLinkTracker
      node: AudioService.sink
    }

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
        implicitHeight: header.implicitHeight + (Style.marginM * 2)

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

      // Tab Bar

      // Content Stack
      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: panelContent.currentTabIndex

        // Applications Tab (Volume)
        NScrollView {
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          clip: true
          contentWidth: availableWidth

          ColumnLayout {
            spacing: Style.marginM
            width: parent.width

            // Output Volume
            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: outputVolumeColumn.implicitHeight + (Style.marginM * 2)

              RowLayout {
                id: outputVolumeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginM

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

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
                    text: Math.round(localOutputVolume * 100) + "%"
                  }
                }

                NIconButton {
                  icon: AudioService.getOutputIcon()
                  tooltipText: I18n.tr("tooltips.output-muted")
                  baseSize: Style.baseWidgetSize * 0.8
                  onClicked: {
                    AudioService.suppressOutputOSD();
                    AudioService.setOutputMuted(!AudioService.muted);
                  }
                }
              }
            }

            // Input Volume
            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: inputVolumeColumn.implicitHeight + (Style.marginM * 2)

              RowLayout {
                id: inputVolumeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginM

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

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
                    text: Math.round(localInputVolume * 100) + "%"
                  }
                }

                NIconButton {
                  icon: AudioService.getInputIcon()
                  tooltipText: I18n.tr("tooltips.input-muted")
                  baseSize: Style.baseWidgetSize * 0.8
                  onClicked: {
                    AudioService.suppressInputOSD();
                    AudioService.setInputMuted(!AudioService.inputMuted);
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
                Layout.preferredHeight: appRow.implicitHeight + (Style.marginM * 2)
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

                // Get app name from properties (reactive computed property)
                // Access modelData.ready to ensure reactivity when node becomes ready
                readonly property string appName: {
                  if (!modelData) {
                    return "Unknown App";
                  }

                  var props = modelData.properties;
                  var desc = modelData.description || "";
                  var name = modelData.name || "";

                  // If properties aren't available yet, try description or name
                  if (!props) {
                    if (desc) {
                      return desc;
                    }
                    if (name) {
                      // Try to extract meaningful name from node name
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0) {
                        var extracted = nameParts[0];
                        if (extracted) {
                          return extracted.charAt(0).toUpperCase() + extracted.slice(1);
                        }
                      }
                      return name;
                    }
                    return "Unknown App";
                  }

                  // Try to get application name from various properties
                  var computedAppName = props["application.name"] || "";
                  var mediaName = props["media.name"] || "";
                  var mediaTitle = props["media.title"] || "";
                  var appId = props["application.id"] || "";
                  var binaryName = props["application.process.binary"] || "";

                  // If we have application.id, try to extract app name from it (e.g., "firefox.desktop" -> "firefox")
                  if (!computedAppName && appId) {
                    var parts = appId.split(".");
                    if (parts.length > 0) {
                      computedAppName = parts[0];
                      // Capitalize first letter and format nicely
                      if (computedAppName) {
                        computedAppName = computedAppName.charAt(0).toUpperCase() + computedAppName.slice(1);
                      }
                    }
                  }

                  // Try binary name as fallback
                  if (!computedAppName && binaryName) {
                    var binParts = binaryName.split("/");
                    if (binParts.length > 0) {
                      computedAppName = binParts[binParts.length - 1];
                      if (computedAppName) {
                        computedAppName = computedAppName.charAt(0).toUpperCase() + computedAppName.slice(1);
                      }
                    }
                  }

                  // Priority: application.name > media.title > media.name > binary > description > name
                  var result = computedAppName || mediaTitle || mediaName || binaryName || desc || name;

                  // If we still don't have a good name, try to extract from node name
                  if (!result || result === "" || result === "Unknown App") {
                    if (name) {
                      // Try to extract meaningful name from node name (e.g., "firefox-1234" -> "firefox")
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0) {
                        result = nameParts[0];
                        // Capitalize first letter
                        if (result) {
                          result = result.charAt(0).toUpperCase() + result.slice(1);
                        }
                      }
                    }
                  }

                  return result || "Unknown App";
                }

                // Get app icon from properties (returns file path)
                readonly property string appIcon: {
                  if (!modelData) {
                    return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");
                  }

                  var props = modelData.properties;
                  if (!props) {
                    // Try to get icon from app name
                    var name = modelData.name || "";
                    if (name) {
                      // Extract app name from node name (e.g., "firefox-1234" -> "firefox")
                      var nameParts = name.split(/[-_]/);
                      if (nameParts.length > 0) {
                        var appName = nameParts[0].toLowerCase();
                        return ThemeIcons.iconFromName(appName, "application-x-executable");
                      }
                    }
                    return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");
                  }

                  // Try application.icon-name first (from Pipewire)
                  var iconName = props["application.icon-name"] || "";
                  if (iconName) {
                    var iconPath = ThemeIcons.iconFromName(iconName, "");
                    if (iconPath && iconPath !== "") {
                      return iconPath;
                    }
                  }

                  // Try to get app ID and resolve from desktop entry
                  var appId = props["application.id"] || "";
                  if (appId) {
                    var iconPathFromId = ThemeIcons.iconForAppId(appId.toLowerCase(), "");
                    if (iconPathFromId && iconPathFromId !== "") {
                      return iconPathFromId;
                    }
                  }

                  // Try application.name
                  var appName = props["application.name"] || "";
                  if (appName) {
                    var iconPathFromName = ThemeIcons.iconFromName(appName.toLowerCase(), "");
                    if (iconPathFromName && iconPathFromName !== "") {
                      return iconPathFromName;
                    }
                  }

                  // Try binary name
                  var binaryName = props["application.process.binary"] || "";
                  if (binaryName) {
                    var binParts = binaryName.split("/");
                    if (binParts.length > 0) {
                      var binName = binParts[binParts.length - 1].toLowerCase();
                      var iconPathFromBinary = ThemeIcons.iconFromName(binName, "");
                      if (iconPathFromBinary && iconPathFromBinary !== "") {
                        return iconPathFromBinary;
                      }
                    }
                  }

                  // Try node name as fallback
                  var name = modelData.name || "";
                  if (name) {
                    var nameParts = name.split(/[-_]/);
                    if (nameParts.length > 0) {
                      var extractedName = nameParts[0].toLowerCase();
                      var iconPathFromNodeName = ThemeIcons.iconFromName(extractedName, "");
                      if (iconPathFromNodeName && iconPathFromNodeName !== "") {
                        return iconPathFromNodeName;
                      }
                    }
                  }

                  // Final fallback
                  return ThemeIcons.iconFromName("application-x-executable", "application-x-executable");
                }

                RowLayout {
                  id: appRow
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginM

                  // App Icon
                  Image {
                    id: appIconImage
                    Layout.preferredWidth: Style.baseWidgetSize
                    Layout.preferredHeight: Style.baseWidgetSize
                    source: appBox.appIcon
                    sourceSize.width: Style.baseWidgetSize * 2
                    sourceSize.height: Style.baseWidgetSize * 2
                    smooth: true
                    mipmap: true
                    antialiasing: true
                    fillMode: Image.PreserveAspectFit
                    cache: true
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
                      text: Math.round((appBox.appVolume !== undefined ? appBox.appVolume : 0.0) * 100) + "%"
                    }
                  }

                  // Mute Button
                  NIconButton {
                    icon: (appBox.appMuted === true) ? "volume-mute" : "volume-high"
                    tooltipText: (appBox.appMuted === true) ? I18n.tr("tooltips.unmute") : I18n.tr("tooltips.mute")
                    baseSize: Style.baseWidgetSize * 0.8
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
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          clip: true
          contentWidth: availableWidth

          // AudioService Devices
          ColumnLayout {
            spacing: Style.marginM
            width: parent.width

            // -------------------------------
            // Output Devices
            ButtonGroup {
              id: sinks
            }

            NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: outputColumn.implicitHeight + (Style.marginM * 2)

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
              Layout.preferredHeight: inputColumn.implicitHeight + (Style.marginM * 2)

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
