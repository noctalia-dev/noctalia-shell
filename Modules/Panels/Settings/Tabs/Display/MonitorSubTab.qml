import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Hardware
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  Layout.fillWidth: true
  Layout.fillHeight: true

  property var monitors: Quickshell.screens || []
  property string selectedOutput: ""
  property bool edidShowRawDecoded: false

  function formatEdidHex(raw) {
    const hex = String(raw || "").replace(/[^0-9a-fA-F]/g, "").toLowerCase();
    if (hex.length === 0) return "";

    const lines = [];
    for (let i = 0; i < hex.length; i += 32) {
      const row = hex.slice(i, i + 32);
      const bytes = [];
      for (let j = 0; j < row.length; j += 2)
        bytes.push(row.slice(j, j + 2));
      lines.push(bytes.join(" "));
    }
    return lines.join("\n");
  }

  function formatEdidSummary(summaryObj) {
    const s = summaryObj && typeof summaryObj === "object" ? summaryObj : null;
    if (!s)
      return "";

    const lines = [];
    if (s.monitorName)
      lines.push(I18n.tr("panels.display.edid-field-monitor-name", { "value": s.monitorName }));
    if (s.manufacturerId)
      lines.push(I18n.tr("panels.display.edid-field-manufacturer-id", { "value": s.manufacturerId }));
    if (s.productCode)
      lines.push(I18n.tr("panels.display.edid-field-product-code", { "value": s.productCode }));

    const serialValue = s.serialText || s.serialNumber;
    if (serialValue)
      lines.push(I18n.tr("panels.display.edid-field-serial-number", { "value": serialValue }));

    if (s.version)
      lines.push(I18n.tr("panels.display.edid-field-version", { "value": s.version }));

    if (s.week !== null && s.year !== null) {
      lines.push(I18n.tr("panels.display.edid-field-manufactured", { "week": s.week, "year": s.year }));
    } else if (s.year !== null) {
      lines.push(I18n.tr("panels.display.edid-field-manufactured", { "week": I18n.tr("common.unknown"), "year": s.year }));
    }

    if (s.inputType)
      lines.push(I18n.tr("panels.display.edid-field-input-type", { "value": s.inputType }));

    const widthCm = s.sizeCm && s.sizeCm.width !== null ? s.sizeCm.width : null;
    const heightCm = s.sizeCm && s.sizeCm.height !== null ? s.sizeCm.height : null;
    if (widthCm !== null && heightCm !== null) {
      const sizeText = I18n.tr("panels.display.edid-size-cm", { "width": widthCm, "height": heightCm });
      lines.push(I18n.tr("panels.display.edid-field-physical-size", { "value": sizeText }));
    }

    if (s.preferredMode)
      lines.push(I18n.tr("panels.display.edid-field-preferred-mode", { "value": s.preferredMode }));

    if (s.source)
      lines.push(I18n.tr("panels.display.edid-field-decoder", { "value": s.source }));

    if (s.warnings && s.warnings.length > 0) {
      for (let i = 0; i < s.warnings.length; i++)
        lines.push("! " + s.warnings[i]);
    }

    return lines.join("\n");
  }

  function formatEdidDetails(rawHex, decodedText, showRawDecoded) {
    const decoded = String(decodedText || "").trim();
    const decodeError = String(typeof DisplayService.edidDecodeError !== "undefined" ? DisplayService.edidDecodeError : "").trim();

    if (showRawDecoded === true) {
      if (decoded !== "")
        return decoded;
      if (decodeError !== "")
        return decodeError;
      const formattedRawOnly = formatEdidHex(rawHex);
      if (formattedRawOnly !== "")
        return formattedRawOnly;
      return I18n.tr("panels.display.edid-empty");
    }

    const summary = formatEdidSummary(typeof DisplayService.edidSummary !== "undefined" ? DisplayService.edidSummary : null);
    if (summary !== "")
      return summary;

    if (decoded !== "")
      return decoded;

    if (decodeError !== "")
      return decodeError;

    const formattedRaw = formatEdidHex(rawHex);
    if (formattedRaw !== "")
      return formattedRaw;

    return I18n.tr("panels.display.edid-empty");
  }

  function buildEdidCopyPayload() {
    const output = DisplayService.edidOutputName || root.selectedOutput || "-";
    const decoded = typeof DisplayService.edidDecoded !== "undefined" ? String(DisplayService.edidDecoded || "") : "";
    const shown = formatEdidDetails(DisplayService.edidHex, decoded, root.edidShowRawDecoded);
    const decodeError = String(typeof DisplayService.edidDecodeError !== "undefined" ? DisplayService.edidDecodeError : "").trim();

    const sections = [
      I18n.tr("panels.display.edid-title", { "output": output }),
      "",
      shown
    ];

    if (decodeError !== "")
      sections.push("", I18n.tr("panels.display.edid-section-decode-error"), decodeError);

    if (decoded.trim() !== "" && decoded.trim() !== shown.trim())
      sections.push("", I18n.tr("panels.display.edid-section-decoded-output"), decoded);

    return sections.join("\n");
  }

  function enabledMonitorCount() {
    const outputs = DisplayService.outputsList || [];
    const tc = DisplayService.targetConfig || {};
    let count = 0;
    for (const out of outputs) {
      const conf = tc[out.name];
      const isEnabled = conf && conf.enabled !== undefined ? conf.enabled : (out.enabled !== false);
      if (isEnabled) count++;
    }
    return count;
  }

  function isInternalOutputName(outputName) {
    const name = String(outputName || "").toUpperCase();
    return name.startsWith("EDP") || name.startsWith("LVDS") || name.startsWith("DSI");
  }

  function outputIndexForScreenName(screenName) {
    const screen = String(screenName || "");
    if (screen === "")
      return -1;

    const outputs = DisplayService.outputsList || [];
    for (let i = 0; i < outputs.length; i++) {
      if (String(outputs[i].name || "") === screen)
        return i + 1;
    }

    // Fallback to runtime screen order when output names don't match one-to-one.
    const screens = Quickshell.screens || [];
    for (let i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === screen)
        return i + 1;
    }

    return -1;
  }

  function outputLabelForScreenName(screenName) {
    const screen = String(screenName || "");
    if (screen === "")
      return "";

    const idx = outputIndexForScreenName(screen);
    return idx > 0 ? (idx + "  " + screen) : screen;
  }

  Component.onCompleted: {
    DisplayService.refresh();
  }

  NBox {
    Layout.fillWidth: true
    implicitHeight: warningContent.implicitHeight + 2 * Style.marginM
    visible: DisplayService.compositor === "readonly"
    color: Qt.alpha(Color.mError, 0.15)
    border.color: Color.mError
    
    RowLayout {
      id: warningContent
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM
      
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        NText {
          text: I18n.tr("panels.display.hw-control-unavailable") || "Hardware Control Unavailable"
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightBold
          color: Color.mError
          Layout.fillWidth: true
        }
        NText {
          text: I18n.tr("panels.display.hw-control-unavailable-desc") || "Rendering in read-only mode."
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL
    enabled: DisplayService.compositor !== "readonly"
    opacity: enabled ? 1.0 : 0.5

      // Layout Section Header
      NText {
        text: I18n.tr("panels.display.monitor-layout")
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        text: I18n.tr("panels.display.monitor-drag-info")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NBox {
        id: canvasContainer
        Layout.fillWidth: true
        Layout.preferredHeight: 220 * Style.uiScaleRatio
        color: Color.mSurface
        border.color: Style.boxBorderColor
        clip: true

        property real snapGuideX: -1
        property real snapGuideY: -1

        property var canvasBounds: {
          // Compute logical layout extents from enabled outputs and pending targetConfig overrides.
          const outputs = DisplayService.outputsList;
          const tc = DisplayService.targetConfig;
          if (!outputs || outputs.length === 0)
            return { minX: 0, minY: 0, maxX: 1, maxY: 1, totalW: 1, totalH: 1 };

          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
          for (const out of outputs) {
            const conf = tc ? tc[out.name] : null;
            if (conf && conf.enabled === false) continue;
            if (!conf && out.enabled === false) continue;
            
            const lx = conf && conf.x !== undefined ? conf.x : (out.logical ? out.logical.x : 0);
            const ly = conf && conf.y !== undefined ? conf.y : (out.logical ? out.logical.y : 0);
            const lw = conf && conf.logicalWidth !== undefined ? conf.logicalWidth : (out.logical ? out.logical.width : 1920);
            const lh = conf && conf.logicalHeight !== undefined ? conf.logicalHeight : (out.logical ? out.logical.height : 1080);
            minX = Math.min(minX, lx);
            minY = Math.min(minY, ly);
            maxX = Math.max(maxX, lx + lw);
            maxY = Math.max(maxY, ly + lh);
          }
          if (minX === Infinity) return { minX: 0, minY: 0, maxX: 1, maxY: 1, totalW: 1, totalH: 1 };
          return { minX, minY, maxX, maxY, totalW: maxX - minX, totalH: maxY - minY };
        }

        property real previewScale: {
          // Fit the entire logical layout into the preview canvas with stable padding.
          const b = canvasBounds;
          const padX = 60 * Style.uiScaleRatio;
          const padY = 40 * Style.uiScaleRatio;
          const availW = canvasContainer.width - padX * 2;
          const availH = canvasContainer.height - padY * 2;
          if (b.totalW <= 0 || b.totalH <= 0) return 0.1;
          return Math.min(availW / b.totalW, availH / b.totalH, 0.3);
        }

        property real offsetX: (canvasContainer.width - canvasBounds.totalW * previewScale) / 2
        property real offsetY: (canvasContainer.height - canvasBounds.totalH * previewScale) / 2

        // Snap computation: find nearest edge/center alignment against other enabled outputs.
        function computeSnap(draggedName, newX, newY, previewW, previewH) {
          const threshold = 5; // pixels in preview space
          let bestSnapX = null, bestDX = threshold;
          let bestSnapY = null, bestDY = threshold;
          let guideX = -1, guideY = -1;

          const dragLeft = newX;
          const dragRight = newX + previewW;
          const dragCenterX = newX + previewW / 2;
          const dragTop = newY;
          const dragBottom = newY + previewH;
          const dragCenterY = newY + previewH / 2;

          const outputs = DisplayService.outputsList;
          const tc = DisplayService.targetConfig;
          for (const out of outputs) {
            if (out.name === draggedName) continue;

            const conf = tc ? tc[out.name] : null;
            if (conf && conf.enabled === false) continue;
            if (!conf && out.enabled === false) continue;
            
            const lx = conf && conf.x !== undefined ? conf.x : (out.logical ? out.logical.x : 0);
            const ly = conf && conf.y !== undefined ? conf.y : (out.logical ? out.logical.y : 0);
            const lw = conf && conf.logicalWidth !== undefined ? conf.logicalWidth : (out.logical ? out.logical.width : 1920);
            const lh = conf && conf.logicalHeight !== undefined ? conf.logicalHeight : (out.logical ? out.logical.height : 1080);

            const ox = offsetX + (lx - canvasBounds.minX) * previewScale;
            const oy = offsetY + (ly - canvasBounds.minY) * previewScale;
            const ow = lw * previewScale;
            const oh = lh * previewScale;

            const otherLeft = ox;
            const otherRight = ox + ow;
            const otherCenterX = ox + ow / 2;
            const otherTop = oy;
            const otherBottom = oy + oh;
            const otherCenterY = oy + oh / 2;

            const xSnaps = [
              { d: Math.abs(dragLeft - otherLeft),    sx: otherLeft,              gx: otherLeft },        
              { d: Math.abs(dragRight - otherRight),  sx: otherRight - previewW,  gx: otherRight },       
              { d: Math.abs(dragLeft - otherRight),   sx: otherRight,             gx: otherRight },       
              { d: Math.abs(dragRight - otherLeft),   sx: otherLeft - previewW,   gx: otherLeft },        
              { d: Math.abs(dragCenterX - otherCenterX), sx: otherCenterX - previewW / 2, gx: otherCenterX }
            ];
            for (const s of xSnaps) {
              if (s.d < bestDX) { bestDX = s.d; bestSnapX = s.sx; guideX = s.gx; }
            }

            const ySnaps = [
              { d: Math.abs(dragTop - otherTop),      sy: otherTop,               gy: otherTop },         
              { d: Math.abs(dragBottom - otherBottom), sy: otherBottom - previewH,  gy: otherBottom },      
              { d: Math.abs(dragTop - otherBottom),   sy: otherBottom,             gy: otherBottom },      
              { d: Math.abs(dragBottom - otherTop),   sy: otherTop - previewH,     gy: otherTop },         
              { d: Math.abs(dragCenterY - otherCenterY), sy: otherCenterY - previewH / 2, gy: otherCenterY }
            ];
            for (const s of ySnaps) {
              if (s.d < bestDY) { bestDY = s.d; bestSnapY = s.sy; guideY = s.gy; }
            }
          }

          return { snapX: bestSnapX, snapY: bestSnapY, guideX: guideX, guideY: guideY };
        }

        Repeater {
          model: DisplayService.outputsList

          delegate: Rectangle {
            id: monitorRect

            property var outputData: modelData
            property string outName: outputData.name || ""
            property var targetConf: DisplayService.targetConfig[outName] || null
            property real logicalX: targetConf && targetConf.x !== undefined ? targetConf.x : (outputData.logical ? outputData.logical.x : 0)
            property real logicalY: targetConf && targetConf.y !== undefined ? targetConf.y : (outputData.logical ? outputData.logical.y : 0)
            property real logicalW: targetConf && targetConf.logicalWidth !== undefined ? targetConf.logicalWidth : (outputData.logical ? outputData.logical.width : 1920)
            property real logicalH: targetConf && targetConf.logicalHeight !== undefined ? targetConf.logicalHeight : (outputData.logical ? outputData.logical.height : 1080)
            property bool isSelected: root.selectedOutput === outName
            property bool isEnabled: targetConf && targetConf.enabled !== undefined ? targetConf.enabled : (outputData.enabled !== false)
            property bool isLastEnabled: isEnabled && root.enabledMonitorCount() <= 1

            property real dataX: canvasContainer.offsetX + (logicalX - canvasContainer.canvasBounds.minX) * canvasContainer.previewScale
            property real dataY: canvasContainer.offsetY + (logicalY - canvasContainer.canvasBounds.minY) * canvasContainer.previewScale

            x: dataX
            y: dataY
            width: logicalW * canvasContainer.previewScale
            height: logicalH * canvasContainer.previewScale

            radius: Style.radiusM
            color: isSelected ? Color.mPrimary : Color.mSurfaceVariant
            border.color: isSelected ? Color.mPrimary : Style.boxBorderColor
            border.width: isSelected ? 2 : 1
            opacity: monitorDragArea.dragging ? 0.7 : 1.0
            visible: isEnabled

            Behavior on x { enabled: !monitorDragArea.dragging; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !monitorDragArea.dragging; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            ColumnLayout {
              anchors.centerIn: parent
              spacing: 2

              NText {
                text: monitorRect.outName
                pointSize: Style.fontSizeS
                font.weight: Style.fontWeightBold
                color: monitorRect.isSelected ? Color.mOnPrimary : Color.mOnSurface
                Layout.alignment: Qt.AlignHCenter
                elide: Text.ElideRight
                Layout.maximumWidth: monitorRect.width - 8
              }

              NText {
                text: monitorRect.logicalW + "×" + monitorRect.logicalH
                pointSize: Style.fontSizeXS
                color: monitorRect.isSelected ? Color.mOnPrimary : Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
                visible: monitorRect.width > 60
              }
            }

            MouseArea {
              id: monitorDragArea
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true

              property bool dragging: false
              property real dragStartMouseX: 0
              property real dragStartMouseY: 0
              property real dragStartRectX: 0
              property real dragStartRectY: 0

              cursorShape: monitorRect.isLastEnabled ? Qt.ArrowCursor : (dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

              onPressed: function(mouse) {
                if (monitorRect.isLastEnabled) {
                  root.selectedOutput = monitorRect.outName;
                  return;
                }
                const canvasPos = mapToItem(canvasContainer, mouse.x, mouse.y);
                dragStartMouseX = canvasPos.x;
                dragStartMouseY = canvasPos.y;
                dragStartRectX = monitorRect.x;
                dragStartRectY = monitorRect.y;
                dragging = true;
              }

              onPositionChanged: function(mouse) {
                if (!dragging) return;
                const canvasPos = mapToItem(canvasContainer, mouse.x, mouse.y);
                let newX = dragStartRectX + (canvasPos.x - dragStartMouseX);
                let newY = dragStartRectY + (canvasPos.y - dragStartMouseY);

                const snap = canvasContainer.computeSnap(
                  monitorRect.outName, newX, newY,
                  monitorRect.width, monitorRect.height
                );

                if (snap.snapX !== null) newX = snap.snapX;
                if (snap.snapY !== null) newY = snap.snapY;

                monitorRect.x = newX;
                monitorRect.y = newY;

                canvasContainer.snapGuideX = snap.guideX;
                canvasContainer.snapGuideY = snap.guideY;
              }

              onReleased: function(mouse) {
                if (!dragging) return;
                dragging = false;

                const canvasPos = mapToItem(canvasContainer, mouse.x, mouse.y);
                const dx = Math.abs(canvasPos.x - dragStartMouseX);
                const dy = Math.abs(canvasPos.y - dragStartMouseY);

                canvasContainer.snapGuideX = -1;
                canvasContainer.snapGuideY = -1;

                // Treat tiny pointer movement as a click-to-select, not a drag commit.
                if (dx < 3 && dy < 3) {
                  root.selectedOutput = monitorRect.outName;
                  monitorRect.x = Qt.binding(function() { return monitorRect.dataX; });
                  monitorRect.y = Qt.binding(function() { return monitorRect.dataY; });
                  return;
                }

                // Convert preview coordinates back into logical layout coordinates.
                const newLogicalX = canvasContainer.canvasBounds.minX + (monitorRect.x - canvasContainer.offsetX) / canvasContainer.previewScale;
                const newLogicalY = canvasContainer.canvasBounds.minY + (monitorRect.y - canvasContainer.offsetY) / canvasContainer.previewScale;

                DisplayService.setPositionNormalized(monitorRect.outName, newLogicalX, newLogicalY);
                
                root.selectedOutput = monitorRect.outName;
                monitorRect.x = Qt.binding(function() { return monitorRect.dataX; });
                monitorRect.y = Qt.binding(function() { return monitorRect.dataY; });
              }
            }
          }
        }

        Rectangle {
          visible: canvasContainer.snapGuideX >= 0
          x: canvasContainer.snapGuideX
          y: 0
          width: 1
          height: canvasContainer.height
          color: Color.mSecondary
          opacity: 0.8
          z: 50
        }

        Rectangle {
          visible: canvasContainer.snapGuideY >= 0
          x: 0
          y: canvasContainer.snapGuideY
          width: canvasContainer.width
          height: 1
          color: Color.mSecondary
          opacity: 0.8
          z: 50
        }

        NText {
          anchors.centerIn: parent
          text: I18n.tr("common.loading")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
          visible: DisplayService.loading && DisplayService.outputsList.length === 0
        }
      }

      NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginS; Layout.bottomMargin: Style.marginS }

      NText {
        text: I18n.tr("panels.display.monitor-settings")
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      Repeater {
        model: DisplayService.outputsList
        delegate: NBox {
          id: monitorCard
          Layout.fillWidth: true
          implicitHeight: monitorCardCol.implicitHeight + 2 * Style.marginL
          color: root.selectedOutput === monitorName ? Qt.alpha(Color.mPrimary, 0.1) : Color.mSurface
          border.color: root.selectedOutput === monitorName ? Color.mPrimary : Style.boxBorderColor

          property var outData: modelData
          property string monitorName: outData.name || ""
          property var screenData: {
            const screens = Quickshell.screens || [];
            for (let i = 0; i < screens.length; i++) {
              if ((screens[i].name || "") === monitorName)
                return screens[i];
            }
            return null;
          }
          property var brightnessMonitor: screenData ? BrightnessService.getMonitorForScreen(screenData) : null
          property real localBrightness: 0.5
          property bool localBrightnessChanging: false
          readonly property string automaticOptionLabel: {
            var baseLabel = I18n.tr("panels.display.monitors-backlight-device-auto-option");
            var autoDevicePath = (BrightnessService.availableBacklightDevices && BrightnessService.availableBacklightDevices.length > 0) ? BrightnessService.availableBacklightDevices[0] : "";
            if (autoDevicePath === "")
              return baseLabel;

            var autoDeviceName = BrightnessService.getBacklightDeviceName(autoDevicePath) || autoDevicePath;
            return baseLabel + "(" + autoDeviceName + ")";
          }
          readonly property var backlightDeviceOptions: {
            var options = [
                  {
                    "key": "",
                    "name": automaticOptionLabel
                  }
                ];

            var devices = BrightnessService.availableBacklightDevices || [];
            for (var i = 0; i < devices.length; i++) {
              var devicePath = devices[i];
              var deviceName = BrightnessService.getBacklightDeviceName(devicePath) || devicePath;
              options.push({
                             "key": devicePath,
                             "name": deviceName
                           });
            }
            return options;
          }
          property var logicalData: outData.logical || {
            x: targetConf && targetConf.x !== undefined ? targetConf.x : 0,
            y: targetConf && targetConf.y !== undefined ? targetConf.y : 0,
            width: targetConf && targetConf.logicalWidth !== undefined ? targetConf.logicalWidth : 0,
            height: targetConf && targetConf.logicalHeight !== undefined ? targetConf.logicalHeight : 0,
            scale: targetConf && targetConf.scale !== undefined ? targetConf.scale : 1.0,
            transform: targetConf && targetConf.transform !== undefined ? targetConf.transform : "Normal"
          }
          property var modes: outData.modes || []
          property int currentModeIdx: outData.current_mode || 0
          property var targetConf: DisplayService.targetConfig[monitorName] || null
          property bool isEnabled: targetConf && targetConf.enabled !== undefined ? targetConf.enabled : (outData.enabled !== false)
          property bool isLastEnabled: isEnabled && root.enabledMonitorCount() <= 1

          property string targetModeStr: targetConf && targetConf.modeStr ? targetConf.modeStr : ""
          property string targetResolution: targetModeStr.indexOf("@") > 0 ? targetModeStr.split("@")[0] : ""
          property string targetRefreshRate: targetModeStr.indexOf("@") > 0 ? targetModeStr.split("@")[1] : ""

          property var uniqueResolutions: {
            // Keep one option per WxH; refresh rate is selected in a dedicated combobox.
            const resMap = {};
            const resList = [];
            for (let i = 0; i < modes.length; i++) {
              const m = modes[i];
              const key = m.width + "x" + m.height;
              if (!resMap[key]) {
                resMap[key] = true;
                resList.push({ "key": key, "name": key });
              }
            }
            return resList;
          }

          property var currentMode: modes[currentModeIdx] || {}
          property string currentResolution: {
            if (currentMode.width && currentMode.height) return currentMode.width + "x" + currentMode.height;
            return targetResolution || "0x0";
          }

          function refreshRatesFor(resolution) {
            // Build sorted refresh-rate options for a selected resolution.
            const rates = [];
            const rateSet = {};
            const parts = resolution.split("x");
            const w = parseInt(parts[0]) || 0;
            const h = parseInt(parts[1]) || 0;
            for (let i = 0; i < modes.length; i++) {
              const m = modes[i];
              if (m.width === w && m.height === h) {
                const rateHz = (m.refresh_rate / 1000).toFixed(3);
                if (!rateSet[rateHz]) {
                  rateSet[rateHz] = true;
                  let label = parseFloat(rateHz).toFixed(2) + " Hz";
                  if (m.is_preferred) label += " ★";
                  rates.push({ "key": rateHz, "name": label });
                }
              }
            }
            rates.sort((a, b) => parseFloat(b.key) - parseFloat(a.key));
            return rates;
          }

          property string currentRefreshRate: currentMode.refresh_rate ? (currentMode.refresh_rate / 1000).toFixed(3) : (targetRefreshRate || "60.000")

          TapHandler {
            onTapped: root.selectedOutput = monitorCard.monitorName
          }

          onBrightnessMonitorChanged: {
            if (brightnessMonitor && !localBrightnessChanging)
              localBrightness = brightnessMonitor.brightness || 0.5;
          }

          Connections {
            target: BrightnessService
            function onMonitorBrightnessChanged(monitor, newBrightness) {
              if (monitor === brightnessMonitor && !localBrightnessChanging)
                localBrightness = newBrightness;
            }
          }

          Connections {
            target: brightnessMonitor
            ignoreUnknownSignals: true
            function onBrightnessUpdated() {
              if (brightnessMonitor && !localBrightnessChanging)
                localBrightness = brightnessMonitor.brightness || 0;
            }
          }

          Timer {
            id: brightnessDebounceTimer
            interval: 120
            repeat: false
            onTriggered: {
              if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable && Math.abs(localBrightness - brightnessMonitor.brightness) >= 0.005)
                brightnessMonitor.setBrightness(localBrightness);
            }
          }

          ColumnLayout {
            id: monitorCardCol
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NIcon {
                icon: root.isInternalOutputName(monitorCard.monitorName) ? "device-laptop" : "device-desktop"
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                NText {
                  text: monitorCard.monitorName
                  pointSize: Style.fontSizeM
                  font.weight: Style.fontWeightBold
                  color: Color.mPrimary
                }

                NText {
                  text: {
                    const parts = [];
                    if (outData.make) parts.push(outData.make);
                    if (outData.model) parts.push(outData.model);
                    if (outData.physical_size) parts.push(outData.physical_size[0] + "×" + outData.physical_size[1] + " mm");
                    return parts.join(" · ") || I18n.tr("common.unknown");
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }
              NIconButton {
                icon: "info-circle"
                tooltipText: I18n.tr("panels.display.read-edid")
                onClicked: {
                  root.selectedOutput = monitorCard.monitorName;
                  root.edidShowRawDecoded = false;
                  DisplayService.readEdid(monitorCard.monitorName);
                  edidDialog.open();
                }
              }
            }

            GridLayout {
              columns: 4
              columnSpacing: Style.marginL
              rowSpacing: Style.marginS
              Layout.fillWidth: true
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              opacity: enabled ? 1.0 : 0.5

              ColumnLayout {
                spacing: 2
                visible: !monitorCard.isLastEnabled
                NText { text: I18n.tr("common.position"); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                NText { text: "(" + (logicalData.x || 0) + ", " + (logicalData.y || 0) + ")"; color: Color.mOnSurface; pointSize: Style.fontSizeS }
              }
              ColumnLayout {
                spacing: 2
                NText { text: I18n.tr("panels.display.logical-size"); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                NText { text: (logicalData.width || 0) + "×" + (logicalData.height || 0); color: Color.mOnSurface; pointSize: Style.fontSizeS }
              }
              ColumnLayout {
                spacing: 2
                NText { text: I18n.tr("common.scale"); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                NText { text: (logicalData.scale || 1.0).toFixed(2) + "x"; color: Color.mOnSurface; pointSize: Style.fontSizeS }
              }
              ColumnLayout {
                spacing: 2
                NText { text: I18n.tr("panels.display.rotation"); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                NText { 
                  text: {
                    const t = logicalData.transform || "Normal";
                    // Simplistic transform labels
                    if (t === "90") return "90°";
                    if (t === "180") return "180°";
                    if (t === "270") return "270°";
                    if (t.startsWith("Flipped")) return I18n.tr("panels.display.flipped") || "Flipped";
                    return I18n.tr("common.normal");
                  }
                  color: Color.mOnSurface; 
                  pointSize: Style.fontSizeS 
                }
              }
            }

            NDivider { Layout.fillWidth: true }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginL

              NText {
                text: I18n.tr("common.brightness")
                Layout.preferredWidth: 90
                Layout.alignment: Qt.AlignVCenter
              }

              NValueSlider {
                id: brightnessSlider
                from: 0
                to: 1
                value: localBrightness
                stepSize: 0.01
                enabled: brightnessMonitor ? brightnessMonitor.brightnessControlAvailable : false
                onMoved: value => {
                           if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                             localBrightness = value;
                             brightnessDebounceTimer.restart();
                           }
                         }
                onPressedChanged: (pressed, value) => {
                                    localBrightnessChanging = pressed;
                                    if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                                      localBrightness = value;
                                      brightnessDebounceTimer.restart();
                                    }
                                  }
                Layout.fillWidth: true
              }

              NText {
                text: brightnessMonitor ? Math.round(localBrightness * 100) + "%" : "N/A"
                Layout.preferredWidth: 55
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
                opacity: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable ? 0.5 : 1.0
              }

              Item {
                Layout.preferredWidth: 30
                Layout.fillHeight: true
                NIcon {
                  icon: brightnessMonitor && brightnessMonitor.method == "internal" ? "device-laptop" : "device-desktop"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable ? 0.5 : 1.0
                }
              }
            }

            NText {
              visible: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable && !(brightnessMonitor.method === "internal" && brightnessMonitor.initInProgress)
              text: !Settings.data.brightness.enableDdcSupport ? I18n.tr("panels.display.monitors-brightness-unavailable-ddc-disabled") : I18n.tr("panels.display.monitors-brightness-unavailable-generic")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            NComboBox {
              Layout.fillWidth: true
              visible: brightnessMonitor && brightnessMonitor.method === "internal"
              label: I18n.tr("panels.display.monitors-backlight-device-label")
              description: I18n.tr("panels.display.monitors-backlight-device-description")
              model: backlightDeviceOptions
              currentKey: BrightnessService.getMappedBacklightDevice(monitorCard.monitorName) || ""
              onSelected: key => BrightnessService.setMappedBacklightDevice(monitorCard.monitorName, key)
            }

            NDivider { visible: DisplayService.compositor !== "readonly"; Layout.fillWidth: true }

            NComboBox {
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              Layout.fillWidth: true
              label: I18n.tr("common.resolution")
              model: monitorCard.uniqueResolutions
              currentKey: monitorCard.currentResolution
              onSelected: function(key) {
                const rates = monitorCard.refreshRatesFor(key);
                if (rates.length > 0) {
                  const modeStr = key + "@" + rates[0].key;
                  DisplayService.setMode(monitorCard.monitorName, modeStr);
                }
              }
            }

            NComboBox {
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              Layout.fillWidth: true
              label: I18n.tr("panels.display.refresh-rate")
              model: monitorCard.refreshRatesFor(monitorCard.currentResolution)
              currentKey: monitorCard.currentRefreshRate
              onSelected: function(key) {
                const modeStr = monitorCard.currentResolution + "@" + key;
                DisplayService.setMode(monitorCard.monitorName, modeStr);
              }
            }

            NSpinBox {
              id: scaleSpinBox
              Layout.fillWidth: true
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              label: I18n.tr("common.scale")
              minimum: 25
              maximum: 400
              stepSize: 5
              suffix: "%"
              value: Math.round((logicalData.scale || 1.0) * 100)
              defaultValue: 100
              
              Timer {
                id: scaleDebounceTimer
                interval: 600
                repeat: false
                onTriggered: {
                  // Debounce slider edits so compositor commands are not spammed while typing.
                  let s = scaleSpinBox.value / 100.0;
                  if (Math.abs(s - (logicalData.scale || 1.0)) > 0.01) {
                    DisplayService.setScale(monitorCard.monitorName, s);
                  }
                }
              }

              onValueChanged: function() {
                scaleDebounceTimer.restart();
              }
            }

            NComboBox {
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              Layout.fillWidth: true
              label: I18n.tr("panels.display.rotation")
              model: [
                { key: "Normal", name: I18n.tr("common.normal")},
                { key: "90", name: "90°" },
                { key: "180", name: "180°" },
                { key: "270", name: "270°" },
                { key: "Flipped", name: I18n.tr("panels.display.flipped") },
                { key: "Flipped90", name: I18n.tr("panels.display.flipped-angle", { "angle": "90°" }) },
                { key: "Flipped180", name: I18n.tr("panels.display.flipped-angle", { "angle": "180°" }) },
                { key: "Flipped270", name: I18n.tr("panels.display.flipped-angle", { "angle": "270°" }) }
              ]
              currentKey: logicalData.transform || "Normal"
              defaultValue: "Normal"
              onSelected: function(key) {
                DisplayService.setTransform(monitorCard.monitorName, key);
              }
            }

            NToggle {
              visible: DisplayService.compositor !== "readonly"
              enabled: monitorCard.isEnabled
              Layout.fillWidth: true
              label: I18n.tr("panels.display.vrr")
              checked: targetConf && targetConf.vrr_enabled !== undefined ? targetConf.vrr_enabled === true : (outData.vrr_enabled === true)
              defaultValue: false
              onToggled: function(checked) {
                DisplayService.setVrr(monitorCard.monitorName, checked);
              }
            }

            NToggle {
              visible: DisplayService.compositor !== "readonly"
              enabled: !monitorCard.isLastEnabled
              Layout.fillWidth: true
              label: I18n.tr("common.enable-display")
              checked: {
                const tc = DisplayService.targetConfig[monitorCard.monitorName];
                return tc && tc.enabled !== undefined ? tc.enabled : (outData.enabled !== false);
              }
              onToggled: function(checked) {
                DisplayService.toggleOutput(monitorCard.monitorName, checked);
              }
            }

          }
        }
      }

      NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      NSpinBox {
        Layout.fillWidth: true
        label: I18n.tr("panels.display.monitors-brightness-step-label")
        description: I18n.tr("panels.display.monitors-brightness-step-description")
        minimum: 1
        maximum: 50
        value: Settings.data.brightness.brightnessStep
        stepSize: 1
        suffix: "%"
        onValueChanged: Settings.data.brightness.brightnessStep = value
        defaultValue: Settings.getDefaultValue("brightness.brightnessStep")
      }

      NToggle {
        Layout.fillWidth: true
        label: I18n.tr("panels.display.monitors-enforce-minimum-label")
        description: I18n.tr("panels.display.monitors-enforce-minimum-description")
        checked: Settings.data.brightness.enforceMinimum
        onToggled: checked => Settings.data.brightness.enforceMinimum = checked
        defaultValue: Settings.getDefaultValue("brightness.enforceMinimum")
      }

      NToggle {
        Layout.fillWidth: true
        label: I18n.tr("panels.display.monitors-external-brightness-label")
        description: I18n.tr("panels.display.monitors-external-brightness-description")
        checked: Settings.data.brightness.enableDdcSupport
        onToggled: checked => {
                     Settings.data.brightness.enableDdcSupport = checked;
                   }
        defaultValue: Settings.getDefaultValue("brightness.enableDdcSupport")
      }

      Item { Layout.preferredHeight: Style.marginL; Layout.fillWidth: true }
    }

  // Per-screen monitor identifier overlay shown while this settings sub-tab is visible.
  Variants {
    id: monitorIdentifierOverlay
    model: root.visible ? (Quickshell.screens || []) : []

    delegate: PanelWindow {
      id: identifierWindow
      required property ShellScreen modelData

      readonly property string identifierLabel: root.outputLabelForScreenName(modelData ? modelData.name : "")

      visible: identifierLabel !== ""
      screen: modelData
      color: "transparent"

      WlrLayershell.namespace: "noctalia-display-identifiers-" + (screen ? screen.name : "unknown")
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      anchors.top: true
      anchors.left: true
      margins.top: Math.max(Style.marginL, 12)
      margins.left: Math.max(Style.marginL, 12)

      implicitWidth: badge.implicitWidth
      implicitHeight: badge.implicitHeight

      mask: Region {}

      Rectangle {
        id: badge
        radius: Style.radiusM
        color: Qt.alpha(Color.mSurface, 0.9)
        border.color: Qt.alpha(Color.mPrimary, 0.95)
        border.width: Math.max(Style.borderS, 2)
        implicitWidth: textItem.implicitWidth + Style.marginXL * 12.8
        implicitHeight: textItem.implicitHeight + Style.marginL * 9.6

        NText {
          id: textItem
          anchors.centerIn: parent
          text: identifierWindow.identifierLabel
          pointSize: Style.fontSizeXXXL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }
      }
    }
  }

  Popup {
    id: edidDialog
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(640 * Style.uiScaleRatio, parent.width * 0.95)
    height: Math.min(520 * Style.uiScaleRatio, parent.height * 0.9)
    modal: true
    focus: true
    dim: true
    padding: Style.marginL

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusL
      border.color: Color.mOutline
      border.width: Style.borderS
    }

    contentItem: ColumnLayout {
      spacing: Style.marginL

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        Layout.alignment: Qt.AlignTop

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXXS

          NText {
            text: I18n.tr("panels.display.edid-title", {
                           "output": DisplayService.edidOutputName || root.selectedOutput || "-"
                         })
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("panels.display.edid-description")
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        NButton {
          text: I18n.tr("panels.display.edid-view-original")
          fontSize: Style.fontSizeS
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
          outlined: !root.edidShowRawDecoded
          onClicked: {
            root.edidShowRawDecoded = !root.edidShowRawDecoded;
          }
        }
      }

      // Item { Layout.preferredHeight: Style.marginL; Layout.fillWidth: true }

      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        border.color: Style.boxBorderColor
        clip: true

        Loader {
          anchors.fill: parent
          anchors.margins: Style.marginM
          active: true
          sourceComponent: DisplayService.edidLoading ? edidLoadingComponent :
                           (DisplayService.edidError !== "" ? edidErrorComponent : edidContentComponent)
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NButton {
          text: I18n.tr("common.refresh")
          enabled: (DisplayService.edidOutputName || root.selectedOutput || "") !== ""
          onClicked: {
            root.edidShowRawDecoded = false;
            DisplayService.readEdid(DisplayService.edidOutputName || root.selectedOutput);
          }
        }

        Item { Layout.fillWidth: true }

        NButton {
          text: I18n.tr("panels.display.copy-edid")
          enabled: !DisplayService.edidLoading && String(DisplayService.edidHex || "").trim() !== ""
          onClicked: {
            copyEdidProc.payload = root.buildEdidCopyPayload();
            copyEdidProc.running = true;
          }
        }

        NButton {
          text: I18n.tr("common.close")
          onClicked: edidDialog.close()
        }
      }
    }

    Component {
      id: edidLoadingComponent
      Item {
        NText {
          anchors.centerIn: parent
          text: I18n.tr("common.loading")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }
      }
    }

    Component {
      id: edidErrorComponent
      Item {
        NText {
          anchors.fill: parent
          text: DisplayService.edidError || I18n.tr("panels.display.edid-empty")
          pointSize: Style.fontSizeS
          color: Color.mError
          wrapMode: Text.WordWrap
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: edidContentComponent
      ScrollView {
        clip: true

        TextEdit {
          id: edidDetailsText
          width: parent.width
          readOnly: true
          selectByMouse: true
          text: root.formatEdidDetails(
                  DisplayService.edidHex,
                  (typeof DisplayService.edidDecoded !== "undefined" ? DisplayService.edidDecoded : ""),
                  root.edidShowRawDecoded
                )
          color: Color.mOnSurface
          font.family: "monospace"
          font.pixelSize: Math.max(11, Style.fontSizeS * Style.uiScaleRatio)
          wrapMode: TextEdit.Wrap
          textFormat: TextEdit.PlainText
          leftPadding: 0
          rightPadding: 0
          topPadding: 0
          bottomPadding: 0
        }
      }
    }

    Process {
      id: copyEdidProc
      property string payload: ""
      command: [
        "sh",
        "-c",
        'payload="$1"; if command -v wl-copy >/dev/null 2>&1; then printf "%s" "$payload" | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf "%s" "$payload" | xclip -selection clipboard; else echo "No clipboard tool found (wl-copy/xclip)" >&2; exit 1; fi',
        "sh",
        payload
      ]
      running: false

      stderr: StdioCollector {
        onStreamFinished: {
          const err = text.trim();
          if (err.length > 0)
            ToastService.showWarning(I18n.tr("panels.display.read-edid"), err);
        }
      }

      onExited: function(exitCode) {
        if (exitCode === 0) {
          ToastService.showNotice(I18n.tr("panels.display.read-edid"), I18n.tr("common.copied-to-clipboard"));
        } else {
          ToastService.showWarning(I18n.tr("panels.display.read-edid"), I18n.tr("panels.display.edid-copy-failed"));
        }
      }
    }
  }

  Popup {
    id: revertDialog
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420 * Style.uiScaleRatio, parent.width * 0.9)
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    dim: true
    padding: Style.marginXL
    // Mirrors DisplayService confirmation window for temporary topology changes.
    visible: DisplayService.awaitingConfirmation

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusL
      border.color: Color.mOutline
      border.width: Style.borderS
    }

    contentItem: ColumnLayout {
      spacing: Style.marginL
      
      NText {
        text: I18n.tr("panels.display.keep-changes")
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        Layout.alignment: Qt.AlignHCenter
      }
      
      NText {
        text: I18n.tr("panels.display.reverting-in-seconds", {
                        "seconds": DisplayService.revertCountdown
                      })
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
        height: 6 * Style.uiScaleRatio
        radius: 3 * Style.uiScaleRatio
        color: Color.mSurfaceVariant

        Rectangle {
          width: parent.width * (DisplayService.revertCountdown / Math.max(DisplayService.revertTimeoutSec, 1))
          height: parent.height
          radius: parent.radius
          color: Color.mError

          Behavior on width {
            NumberAnimation { duration: 900; easing.type: Easing.Linear }
          }
        }
      }
      
      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.marginL
        
        NButton {
          Layout.preferredWidth: 120 * Style.uiScaleRatio
          Layout.preferredHeight: 40 * Style.uiScaleRatio
          text: I18n.tr("common.revert")
          outlined: true
          onClicked: DisplayService.doRevert()
        }
        
        NButton {
          Layout.preferredWidth: 120 * Style.uiScaleRatio
          Layout.preferredHeight: 40 * Style.uiScaleRatio
          text: I18n.tr("common.keep")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: DisplayService.confirmChange()
        }
      }
    }
  }
}
