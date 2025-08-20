import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

import "../../Helpers/FuzzySort.js" as Fuzzysort

NLoader {
  id: appLauncher
  isLoaded: false
  // Clipboard state is persisted in Services/ClipboardService.qml
  content: Component {
    NPanel {
      id: appLauncherPanel

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      // No local timer/processes; use persistent Clipboard service

      // Removed local clipboard processes; handled by Clipboard service

      // Copy helpers via simple exec; avoid keeping processes alive locally
      function copyImageBase64(mime, base64) {
        Quickshell.execDetached(["sh", "-lc", `printf %s ${base64} | base64 -d | wl-copy -t '${mime}'`])
      }

      function copyText(text) {
        Quickshell.execDetached(["sh", "-lc", `printf %s ${text} | wl-copy -t text/plain;charset=utf-8`])
      }

      function updateClipboardHistory() {
        ClipboardService.refresh()
      }

      function selectNext() {
        if (filteredEntries.length > 0) {
          selectedIndex = Math.min(selectedIndex + 1, filteredEntries.length - 1)
        }
      }

      function selectPrev() {
        if (filteredEntries.length > 0) {
          selectedIndex = Math.max(selectedIndex - 1, 0)
        }
      }

      function activateSelected() {
        if (filteredEntries.length === 0)
          return

        var modelData = filteredEntries[selectedIndex]
        if (modelData && modelData.execute) {
          if (modelData.isCommand) {
            modelData.execute()
            return
          } else {
            modelData.execute()
          }
          appLauncherPanel.hide()
        }
      }

      property var desktopEntries: DesktopEntries.applications.values
      property string searchText: ""
      property int selectedIndex: 0

      // Refresh clipboard when user starts typing clipboard commands
      onSearchTextChanged: {
        if (searchText.startsWith(">clip")) {
          ClipboardService.refresh()
        }
      }
      property var filteredEntries: {
        Logger.log("AppLauncher", "Total desktop entries:", desktopEntries ? desktopEntries.length : 0)
        if (!desktopEntries || desktopEntries.length === 0) {
          Logger.log("AppLauncher", "No desktop entries available")
          return []
        }

        // Filter out entries that shouldn't be displayed
        var visibleEntries = desktopEntries.filter(entry => {
                                                     if (!entry || entry.noDisplay) {
                                                       return false
                                                     }
                                                     return true
                                                   })

        Logger.log("AppLauncher", "Visible entries:", visibleEntries.length)

        var query = searchText ? searchText.toLowerCase() : ""
        var results = []

        // Handle special commands
        if (query === ">") {
          results.push({
                         "isCommand": true,
                         "name": ">calc",
                         "content": "Calculator - evaluate mathematical expressions",
                         "icon": "tag",
                         "execute": function () {
                           searchText = ">calc "
                           searchInput.cursorPosition = searchText.length
                         }
                       })

          results.push({
                         "isCommand": true,
                         "name": ">clip",
                         "content": "Clipboard history - browse and restore clipboard items",
                         "icon": "content_paste",
                         "execute": function () {
                           searchText = ">clip "
                           searchInput.cursorPosition = searchText.length
                         }
                       })

          return results
        }

        // Handle clipboard history
        if (query.startsWith(">clip")) {
          const searchTerm = query.slice(5).trim()

          ClipboardService.history.forEach(function (clip, index) {
            let searchContent = clip.type === 'image' ? clip.mimeType : clip.content || clip

            if (!searchTerm || searchContent.toLowerCase().includes(searchTerm)) {
              let entry
              if (clip.type === 'image') {
                entry = {
                  "isClipboard": true,
                  "name": "Image from " + new Date(clip.timestamp).toLocaleTimeString(),
                  "content": "Image: " + clip.mimeType,
                  "icon": "image",
                  "type": 'image',
                  "data": clip.data,
                  "execute": function () {
                    const base64Data = clip.data.split(',')[1]
                    copyImageBase64(clip.mimeType, base64Data)
                    Quickshell.execDetached(["notify-send", "Clipboard", "Image copied: " + clip.mimeType])
                  }
                }
              } else {
                const textContent = clip.content || clip
                let displayContent = textContent
                let previewContent = ""

                displayContent = displayContent.replace(/\s+/g, ' ').trim()

                if (displayContent.length > 50) {
                  previewContent = displayContent
                  displayContent = displayContent.split('\n')[0].substring(0, 50) + "..."
                }

                entry = {
                  "isClipboard": true,
                  "name": displayContent,
                  "content": previewContent || textContent,
                  "icon": "content_paste",
                  "execute": function () {
                    Quickshell.clipboardText = String(textContent)
                    copyText(String(textContent))
                    var preview = (textContent.length > 50) ? textContent.slice(0, 50) + "…" : textContent
                    Quickshell.execDetached(["notify-send", "Clipboard", "Text copied: " + preview])
                  }
                }
              }
              results.push(entry)
            }
          })

          if (results.length === 0) {
            results.push({
                           "isClipboard": true,
                           "name": "No clipboard history",
                           "content": "No matching clipboard entries found",
                           "icon": "content_paste_off"
                         })
          }

          return results
        }

        // Handle direct math expressions after ">"
        if (query.startsWith(">") && query.length > 1 && !query.startsWith(">clip") && !query.startsWith(">calc")) {
          var mathExpr = query.slice(1).trim()
          // Check if it looks like a math expression (contains numbers and math operators)
          if (mathExpr && /[0-9+\-*/().]/.test(mathExpr)) {
            try {
              var sanitizedExpr = mathExpr.replace(/[^0-9+\-*/().\s]/g, '')
              var result = eval(sanitizedExpr)
              
              if (isFinite(result) && !isNaN(result)) {
                var displayResult = Number.isInteger(result) ? result.toString() : result.toFixed(6).replace(/\.?0+$/, '')
                results.push({
                               "isCalculator": true,
                               "name": `${mathExpr} = ${displayResult}`,
                               "result": result,
                               "expr": mathExpr,
                               "icon": "tag",
                               "execute": function () {
                                 Quickshell.clipboardText = displayResult
                                 copyText(displayResult)
                                 Quickshell.execDetached(
                                       ["notify-send", "Calculator", `${mathExpr} = ${displayResult} (copied to clipboard)`])
                               }
                             })
                return results
              }
            } catch (error) {
              // If math evaluation fails, fall through to regular search
            }
          }
        }

        // Handle calculator
        if (query.startsWith(">calc")) {
          var expr = searchText.slice(5).trim()
          if (expr && expr !== "") {
            try {
              // Simple evaluation - only allow basic math operations
              var sanitizedExpr = expr.replace(/[^0-9+\-*/().\s]/g, '')
              var result = eval(sanitizedExpr)

              if (isFinite(result) && !isNaN(result)) {
                var displayResult = Number.isInteger(result) ? result.toString() : result.toFixed(6).replace(/\.?0+$/,
                                                                                                             '')
                results.push({
                               "isCalculator": true,
                               "name": `${expr} = ${displayResult}`,
                               "result": result,
                               "expr": expr,
                               "icon": "tag",
                               "execute": function () {
                                 Quickshell.clipboardText = displayResult
                                 copyText(displayResult)
                                 Quickshell.execDetached(
                                       ["notify-send", "Calculator", `${expr} = ${displayResult} (copied to clipboard)`])
                               }
                             })
              } else {
                results.push({
                               "isCalculator": true,
                               "name": "Invalid expression",
                               "content": "Please enter a valid mathematical expression",
                               "icon": "tag",
                               "execute": function () {}
                             })
              }
            } catch (error) {
              results.push({
                             "isCalculator": true,
                             "name": "Invalid expression",
                             "content": "Please enter a valid mathematical expression",
                             "icon": "tag",
                             "execute": function () {}
                           })
            }
          } else {
            // Show placeholder when just ">calc" is entered
            results.push({
                           "isCalculator": true,
                           "name": "Calculator",
                           "content": "Enter a mathematical expression (e.g., 5+5, 2*3, 10/2)",
                           "icon": "tag",
                           "execute": function () {}
                         })
          }
          return results
        }

        // Regular app search
        if (!query) {
          results = results.concat(visibleEntries.sort(function (a, b) {
            return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
          }))
        } else {
          var fuzzyResults = Fuzzysort.go(query, visibleEntries, {
                                            "keys": ["name", "comment", "genericName"]
                                          })
          results = results.concat(fuzzyResults.map(function (r) {
            return r.obj
          }))
        }

        Logger.log("AppLauncher", "Filtered entries:", results.length)
        return results
      }

      Component.onCompleted: {
        Logger.log("AppLauncher", "Component completed")
        Logger.log("AppLauncher", "DesktopEntries available:", typeof DesktopEntries !== 'undefined')
        if (typeof DesktopEntries !== 'undefined') {
          Logger.log("AppLauncher", "DesktopEntries.entries:",
                     DesktopEntries.entries ? DesktopEntries.entries.length : 'undefined')
        }
        // Start clipboard refresh immediately on open
        updateClipboardHistory()
      }

      // Main content container
      Rectangle {
        anchors.centerIn: parent
        width: Math.min(700 * scaling, parent.width * 0.75)
        height: Math.min(550 * scaling, parent.height * 0.8)
        radius: Style.radiusL * scaling
        color: Color.mSurface
        border.color: Color.mOutline
        border.width: Style.borderS * scaling

        // Subtle gradient background
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: Qt.lighter(Color.mSurface, 1.02)
          }
          GradientStop {
            position: 1.0
            color: Qt.darker(Color.mSurface, 1.1)
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginL * scaling
          spacing: Style.marginM * scaling

          // Search bar
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.barHeight * scaling
            Layout.bottomMargin: Style.marginM * scaling
            radius: Style.radiusM * scaling
            color: Color.mSurface
            border.color: searchInput.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: Math.max(1, searchInput.activeFocus ? Style.borderM * scaling : Style.borderS * scaling)

            Item {
              anchors.fill: parent
              anchors.margins: Style.marginM * scaling

              NIcon {
                id: searchIcon
                text: "search"
                font.pointSize: Style.fontSizeXL * scaling
                color: searchInput.activeFocus ? Color.mPrimary : Color.mOnSurface
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              TextField {
                id: searchInput
                placeholderText: searchText === "" ? "Search applications... (use > to view commands)" : "Search applications..."
                color: Color.mOnSurface
                placeholderTextColor: Color.mOnSurfaceVariant
                background: null
                font.pointSize: Style.fontSizeL * scaling
                anchors.left: searchIcon.right
                anchors.leftMargin: Style.marginS * scaling
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onTextChanged: {
                  searchText = text
                  selectedIndex = 0 // Reset selection when search changes
                }
                selectedTextColor: Color.mOnSurface
                selectionColor: Color.mPrimary
                padding: 0
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0
                font.family: Settings.data.ui.fontFamily
                font.bold: true
                Component.onCompleted: {
                  contentItem.cursorColor = Color.mOnSurface
                  contentItem.verticalAlignment = TextInput.AlignVCenter
                  // Focus the search bar by default
                  Qt.callLater(() => {
                                 searchInput.forceActiveFocus()
                               })
                }
                onActiveFocusChanged: contentItem.cursorColor = Color.mOnSurface

                Keys.onDownPressed: selectNext()
                Keys.onUpPressed: selectPrev()
                Keys.onEnterPressed: activateSelected()
                Keys.onReturnPressed: activateSelected()
                Keys.onEscapePressed: appLauncherPanel.hide()
              }
            }

            Behavior on border.color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            Behavior on border.width {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }

          // Applications list
          ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ListView {
              id: appsList
              anchors.fill: parent
              spacing: Style.marginXXS * scaling
              model: filteredEntries
              currentIndex: selectedIndex

              delegate: Rectangle {
                width: appsList.width - Style.marginS * scaling
                height: 65 * scaling
                radius: Style.radiusM * scaling
                property bool isSelected: index === selectedIndex
                color: (appCardArea.containsMouse || isSelected) ? Qt.darker(Color.mPrimary, 1.1) : Color.mSurface
                border.color: (appCardArea.containsMouse || isSelected) ? Color.mPrimary : Color.transparent
                border.width: Math.max(1, (appCardArea.containsMouse || isSelected) ? Style.borderM * scaling : 0)

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                Behavior on border.color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                Behavior on border.width {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.marginM * scaling
                  spacing: Style.marginM * scaling

                  // App icon with background
                  Rectangle {
                    Layout.preferredWidth: Style.baseWidgetSize * 1.25 * scaling
                    Layout.preferredHeight: Style.baseWidgetSize * 1.25 * scaling
                    radius: Style.radiusS * scaling
                    color: appCardArea.containsMouse ? Qt.darker(Color.mPrimary, 1.1) : Color.mSurfaceVariant
                    property bool iconLoaded: (modelData.isCalculator || modelData.isClipboard || modelData.isCommand)
                                              || (iconImg.status === Image.Ready && iconImg.source !== ""
                                                  && iconImg.status !== Image.Error && iconImg.source !== "")
                    visible: !searchText.startsWith(">calc") // Hide icon when in calculator mode

                    // Clipboard image display
                    Image {
                      id: clipboardImage
                      anchors.fill: parent
                      anchors.margins: Style.marginXS * scaling
                      visible: modelData.type === 'image'
                      source: modelData.data || ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: true
                    }

                    IconImage {
                      id: iconImg
                      anchors.fill: parent
                      anchors.margins: Style.marginXS * scaling
                      asynchronous: true
                      source: modelData.isCalculator ? "" : modelData.isClipboard ? "" : modelData.isCommand ? modelData.icon : (modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : "")
                      visible: (modelData.isCalculator || modelData.isClipboard || modelData.isCommand
                                || parent.iconLoaded) && modelData.type !== 'image'
                    }

                    // Fallback icon container
                    Rectangle {
                      anchors.fill: parent
                      anchors.margins: Style.marginXS * scaling
                      radius: Style.radiusXS * scaling
                      color: Color.mPrimary
                      opacity: Style.opacityMedium
                      visible: !parent.iconLoaded
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: !parent.iconLoaded && !(modelData.isCalculator || modelData.isClipboard
                                                       || modelData.isCommand)
                      text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                      font.pointSize: Style.fontSizeXXL * scaling
                      font.weight: Font.Bold
                      color: Color.mPrimary
                    }

                    Behavior on color {
                      ColorAnimation {
                        duration: Style.animationFast
                      }
                    }
                  }

                  // App info
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXXS * scaling

                    NText {
                      text: modelData.name || "Unknown"
                      font.pointSize: Style.fontSizeL * scaling
                      font.weight: Font.Bold
                      color: (appCardArea.containsMouse || isSelected) ? Color.mOnPrimary : Color.mOnSurface
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    NText {
                      text: modelData.isCalculator ? (modelData.expr + " = " + modelData.result) : modelData.isClipboard ? modelData.content : modelData.isCommand ? modelData.content : (modelData.genericName || modelData.comment || "")
                      font.pointSize: Style.fontSizeM * scaling
                      color: (appCardArea.containsMouse || isSelected) ? Color.mOnPrimary : Color.mOnSurface
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                      visible: text !== ""
                    }
                  }
                }

                MouseArea {
                  id: appCardArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor

                  onClicked: {
                    selectedIndex = index
                    activateSelected()
                  }
                }
              }
            }
          }

          // No results message
          NText {
            text: searchText.trim() !== "" ? "No applications found" : "No applications available"
            font.pointSize: Style.fontSizeL * scaling
            color: Color.mOnSurface
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            visible: filteredEntries.length === 0
          }

          // Results count
          NText {
            text: searchText.startsWith(
                    ">clip") ? `${filteredEntries.length} clipboard item${filteredEntries.length
                               !== 1 ? 's' : ''}` : searchText.startsWith(
                                         ">calc") ? `${filteredEntries.length} result${filteredEntries.length
                                                    !== 1 ? 's' : ''}` : `${filteredEntries.length} application${filteredEntries.length
                                                            !== 1 ? 's' : ''}`
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurface
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            visible: searchText.trim() !== ""
          }
        }
      }
    }
  }
}
