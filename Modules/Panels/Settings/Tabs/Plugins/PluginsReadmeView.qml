import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Widgets

Item {
  id: root

  property string selectedPluginId: ""

  property var _readmeBlocks: []
  property bool _readmeLoading: false
  property string _readmeBuffer: ""
  property bool _parseFailed: false

  property string fallbackReadmeUrl: ""
  property string _readmeBaseUrl: ""

  readonly property string _mdScriptPath: Quickshell.shellDir + "/Scripts/python/src/plugins/md-to-blocks.py"
  readonly property string _tmpFile: "/tmp/noctalia-readme-" + Date.now() + "-" + Math.floor(Math.random() * 100000) + ".md"

  // Validate plugin ID — only allow safe characters (alphanumeric, hyphens, underscores)
  function _isValidPluginId(pluginId) {
    return (/^[a-zA-Z0-9_-]+$/).test(pluginId)
  }

  // Only open http/https URLs
  function _safeOpenUrl(link) {
    if (link.indexOf("http://") === 0 || link.indexOf("https://") === 0) {
      Qt.openUrlExternally(link)
    }
  }

  onSelectedPluginIdChanged: {
    if (selectedPluginId) {
      _loadReadme(selectedPluginId)
    } else {
      _readmeBlocks = []
      _readmeLoading = false
      _parseFailed = false
    }
  }

  // Step 1: Parse local README via Python script
  Process {
    id: readmeProcess
    stdout: SplitParser {
      onRead: data => { root._readmeBuffer += data + "\n" }
    }
    onExited: exitCode => {
      if (exitCode === 0 && root._readmeBuffer.trim() !== "") {
        root._readmeBaseUrl = "file://" + PluginRegistry.pluginsDir + "/" + root.selectedPluginId + "/"
        root._applyBlocks(root._readmeBuffer)
      } else if (root.fallbackReadmeUrl !== "") {
        root._readmeBuffer = ""
        curlProcess.command = ["curl", "-s", "--max-time", "10", "--fail", "--proto", "=https", "-o", root._tmpFile, root.fallbackReadmeUrl]
        curlProcess.running = true
      } else {
        root._readmeBaseUrl = ""
        root._readmeBlocks = []
        root._readmeBuffer = ""
        root._readmeLoading = false
      }
    }
  }

  // Step 1b: Download remote README
  Process {
    id: curlProcess
    onExited: exitCode => {
      if (exitCode === 0) {
        var url = root.fallbackReadmeUrl
        root._readmeBaseUrl = url.substring(0, url.lastIndexOf("/") + 1)
        root._readmeBuffer = ""
        convertRemoteProcess.command = ["python3", root._mdScriptPath, root._tmpFile]
        convertRemoteProcess.running = true
      } else {
        root._cleanupTmpFile()
        root._readmeBaseUrl = ""
        root._readmeBlocks = []
        root._readmeBuffer = ""
        root._readmeLoading = false
      }
    }
  }

  // Step 2b: Parse remote README
  Process {
    id: convertRemoteProcess
    stdout: SplitParser {
      onRead: data => { root._readmeBuffer += data + "\n" }
    }
    onExited: exitCode => {
      root._cleanupTmpFile()
      if (exitCode === 0 && root._readmeBuffer.trim() !== "") {
        root._applyBlocks(root._readmeBuffer)
      } else {
        root._readmeBlocks = []
        root._readmeBuffer = ""
        root._readmeLoading = false
      }
    }
  }

  function _applyBlocks(buffer) {
    try {
      var parsed = JSON.parse(buffer.trim())
      // Check for fallback raw mode
      if (parsed.length === 1 && parsed[0].type === "raw") {
        root._parseFailed = true
        root._readmeBlocks = parsed
      } else {
        root._parseFailed = false
        root._readmeBlocks = parsed
      }
    } catch (e) {
      root._parseFailed = true
      root._readmeBlocks = [{"type": "raw", "text": buffer}]
    }
    root._readmeBuffer = ""
    root._readmeLoading = false
  }

  function _loadReadme(pluginId) {
    if (readmeProcess.running) readmeProcess.running = false
    if (curlProcess.running) curlProcess.running = false
    if (convertRemoteProcess.running) convertRemoteProcess.running = false
    _readmeLoading = true
    _readmeBlocks = []
    _readmeBuffer = ""
    _parseFailed = false

    if (!root._isValidPluginId(pluginId)) {
      _readmeLoading = false
      return
    }

    var localPath = PluginRegistry.pluginsDir + "/" + pluginId + "/README.md"
    readmeProcess.command = ["python3", root._mdScriptPath, localPath]
    readmeProcess.running = true
  }

  // Cleanup temp file
  Process {
    id: cleanupProcess
  }

  function _cleanupTmpFile() {
    cleanupProcess.command = ["rm", "-f", root._tmpFile]
    cleanupProcess.running = true
  }

  Component.onDestruction: {
    if (readmeProcess.running) readmeProcess.running = false
    if (curlProcess.running) curlProcess.running = false
    if (convertRemoteProcess.running) convertRemoteProcess.running = false
    _cleanupTmpFile()
  }

  // Escape HTML entities to prevent injection
  function _escapeHtml(text) {
    if (!text) return ""
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
  }

  // Format inline markup: **bold** and `code`
  function _formatInline(text) {
    if (!text) return ""
    if (text.length > 10000) return _escapeHtml(text)
    var result = _escapeHtml(text)
    // Bold: **text** → <b>text</b>
    result = result.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    // Inline code: `code` → styled span
    result = result.replace(/`([^`]+)`/g,
      '<code style="font-family:monospace;background-color:' + Color.mSurfaceVariant + ';color:' + Color.mOnSurfaceVariant + ';">$1</code>')
    // Links: [text](url) → clickable (http/https only)
    result = result.replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g,
      '<a href="$2" style="color:' + Color.mPrimary + ';">$1</a>')
    return result
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM
      visible: root.selectedPluginId !== ""

      NText {
        text: {
          var m = PluginRegistry.getPluginManifest(root.selectedPluginId)
          return m ? (m.name || root.selectedPluginId) : root.selectedPluginId
        }
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      NText {
        text: {
          var m = PluginRegistry.getPluginManifest(root.selectedPluginId)
          return m && m.version ? "v" + m.version : ""
        }
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }
    }

    NDivider {
      Layout.fillWidth: true
      visible: root.selectedPluginId !== ""
    }

    NScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      horizontalPolicy: ScrollBar.AlwaysOff
      gradientColor: Color.mSurface
      leftPadding: Style.marginL

      ColumnLayout {
        width: parent.width
        spacing: 0

        // No plugin selected
        Item {
          visible: root.selectedPluginId === ""
          Layout.fillWidth: true
          Layout.preferredHeight: Math.round(120 * Style.uiScaleRatio)
          NText {
            anchors.centerIn: parent
            text: I18n.tr("panels.plugins.readme-select-plugin")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
          }
        }

        // Loading
        Item {
          visible: root._readmeLoading
          Layout.fillWidth: true
          Layout.preferredHeight: Math.round(120 * Style.uiScaleRatio)
          NBusyIndicator {
            anchors.centerIn: parent
            running: root._readmeLoading
          }
        }

        // No README
        Item {
          visible: !root._readmeLoading && root.selectedPluginId !== "" && root._readmeBlocks.length === 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.round(120 * Style.uiScaleRatio)
          NText {
            anchors.centerIn: parent
            text: I18n.tr("panels.plugins.readme-not-available")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
          }
        }

        // Fallback: raw markdown (when markdown-it-py not available)
        NText {
          visible: root._parseFailed && root._readmeBlocks.length > 0
          width: parent.width
          text: root._readmeBlocks.length > 0 && root._readmeBlocks[0].type === "raw" ? root._readmeBlocks[0].text : ""
          markdownTextEnabled: true
          baseUrl: root._readmeBaseUrl
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          color: Color.mOnSurface
          pointSize: Style.fontSizeM
        }

        // Block renderer
        Repeater {
          model: root._parseFailed ? [] : root._readmeBlocks

          delegate: Loader {
            Layout.fillWidth: true
            Layout.topMargin: {
              if (!modelData) return 0
              if (modelData.type === "heading") return Style.marginL
              if (modelData.type === "hr") return Style.marginL
              return Style.marginS
            }
            Layout.bottomMargin: {
              if (!modelData) return 0
              if (modelData.type === "heading") return Style.marginS
              return 0
            }

            sourceComponent: {
              if (!modelData) return null
              switch (modelData.type) {
                case "heading": return headingComponent
                case "paragraph": return paragraphComponent
                case "code": return codeComponent
                case "list": return listComponent
                case "image": return imageComponent
                case "blockquote": return blockquoteComponent
                case "table": return tableComponent
                case "hr": return hrComponent
                default: return paragraphComponent
              }
            }

            property var blockData: modelData
          }
        }
      }
    }
  }

  // ── Block Components ──

  Component {
    id: headingComponent
    NText {
      width: parent ? parent.width : 0
      text: root._formatInline(blockData ? blockData.text : "")
      richTextEnabled: true
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      color: Color.mOnSurface
      font.weight: Style.fontWeightBold
      pointSize: {
        if (!blockData) return Style.fontSizeM
        switch (blockData.level) {
          case 1: return Style.fontSizeXXL
          case 2: return Style.fontSizeXL
          case 3: return Style.fontSizeL
          default: return Style.fontSizeM
        }
      }
      onLinkActivated: link => root._safeOpenUrl(link)
    }
  }

  Component {
    id: paragraphComponent
    NText {
      width: parent ? parent.width : 0
      text: root._formatInline(blockData ? blockData.text : "")
      richTextEnabled: true
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      color: Color.mOnSurface
      pointSize: Style.fontSizeM
      onLinkActivated: link => root._safeOpenUrl(link)
    }
  }

  Component {
    id: codeComponent
    Rectangle {
      width: parent ? parent.width : 0
      implicitHeight: codeText.implicitHeight + Style.margin2L
      radius: Style.radiusS
      color: Color.mSurfaceVariant
      border.color: Style.boxBorderColor
      border.width: Style.borderS

      NText {
        id: codeText
        anchors.fill: parent
        anchors.margins: Style.marginL
        text: blockData ? blockData.text : ""
        family: Settings.data.ui.fontFixed
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }
    }
  }

  Component {
    id: listComponent
    ColumnLayout {
      width: parent ? parent.width : 0
      spacing: Style.marginXS

      Repeater {
        model: blockData ? blockData.items : []

        delegate: RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            text: blockData && blockData.ordered ? (index + 1) + "." : "•"
            color: Color.mPrimary
            pointSize: Style.fontSizeM
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: blockData && blockData.ordered ? Math.round(20 * Style.uiScaleRatio) : Math.round(12 * Style.uiScaleRatio)
          }

          NText {
            text: root._formatInline(modelData)
            richTextEnabled: true
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            color: Color.mOnSurface
            pointSize: Style.fontSizeM
            Layout.fillWidth: true
            onLinkActivated: link => root._safeOpenUrl(link)
          }
        }
      }
    }
  }

  Component {
    id: imageComponent
    Item {
      width: parent ? parent.width : 0
      implicitHeight: readmeImage.implicitHeight

      Image {
        id: readmeImage
        readonly property real maxWidth: Math.round(parent.width * 0.8)
        width: Math.min(implicitWidth, maxWidth)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: {
          if (!blockData || !blockData.src) return ""
          var src = blockData.src
          if (src.indexOf("https://") === 0) {
            if (src.indexOf("https://raw.githubusercontent.com/") === 0
                || src.indexOf("https://github.com/") === 0
                || src.indexOf("https://user-images.githubusercontent.com/") === 0)
              return src
            return ""
          }
          if (src.indexOf("http") === 0) return ""
          return root._readmeBaseUrl + src
        }
        onStatusChanged: {
          if (status === Image.Error) {
            visible = false
          }
        }
      }
    }
  }

  Component {
    id: blockquoteComponent
    RowLayout {
      width: parent ? parent.width : 0
      spacing: Style.marginM

      Rectangle {
        Layout.preferredWidth: Math.round(3 * Style.uiScaleRatio)
        Layout.fillHeight: true
        color: Color.mPrimary
        radius: 1
      }

      NText {
        text: root._formatInline(blockData ? blockData.text : "")
        richTextEnabled: true
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeM
        font.italic: true
        Layout.fillWidth: true
        onLinkActivated: link => root._safeOpenUrl(link)
      }
    }
  }

  Component {
    id: tableComponent
    NText {
      width: parent ? parent.width : 0
      richTextEnabled: true
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      color: Color.mOnSurface
      pointSize: Style.fontSizeS
      onLinkActivated: link => root._safeOpenUrl(link)

      text: {
        if (!blockData) return ""
        var borderColor = Style.boxBorderColor.toString()
        var headerBg = Color.mSurfaceVariant.toString()
        var textColor = Color.mOnSurface.toString()
        var altBg = Qt.alpha(Color.mSurfaceVariant, 0.3).toString()

        var html = '<table cellpadding="6" cellspacing="0" border="1" bordercolor="' + borderColor + '">'

        // Header
        if (blockData.headers && blockData.headers.length > 0) {
          html += '<tr>'
          for (var h = 0; h < blockData.headers.length; h++) {
            html += '<th bgcolor="' + headerBg + '" style="color:' + textColor + ';">'
            html += root._formatInline(blockData.headers[h])
            html += '</th>'
          }
          html += '</tr>'
        }

        // Rows
        var rows = blockData.rows || []
        for (var r = 0; r < rows.length; r++) {
          var rowBg = r % 2 === 1 ? ' bgcolor="' + altBg + '"' : ''
          html += '<tr' + rowBg + '>'
          for (var c = 0; c < rows[r].length; c++) {
            html += '<td style="color:' + textColor + ';">'
            html += root._formatInline(rows[r][c])
            html += '</td>'
          }
          html += '</tr>'
        }

        html += '</table>'
        return html
      }
    }
  }

  Component {
    id: hrComponent
    NDivider {
      width: parent ? parent.width : 0
    }
  }
}
