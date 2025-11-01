import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property var contributors: GitHubService.contributors

  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.about.noctalia.section.label")
    description: I18n.tr("settings.about.noctalia.section.description")
  }

  RowLayout {
    spacing: Style.marginXL

    // Versions
    GridLayout {
      columns: 2
      rowSpacing: Style.marginXS
      columnSpacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.noctalia.latest-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.latestVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        text: I18n.tr("settings.about.noctalia.installed-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.currentVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }
    }

    // Update button
    NButton {
      visible: {
        if (root.latestVersion === "Unknown")
          return false

        const latest = root.latestVersion.replace("v", "").split(".")
        const current = root.currentVersion.replace("v", "").split(".")
        for (var i = 0; i < Math.max(latest.length, current.length); i++) {
          const l = parseInt(latest[i] || "0")
          const c = parseInt(current[i] || "0")
          if (l > c)
            return true

          if (l < c)
            return false
        }
        return false
      }
      icon: "download"
      text: I18n.tr("settings.about.noctalia.download-latest")
      outlined: !hovered
      fontSize: Style.fontSizeXS
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://github.com/Ly-sec/Noctalia/releases/latest"])
      }
    }
  }

  // Ko-fi support button
  Rectangle {
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
    width: supportRow.implicitWidth + Style.marginXL
    height: supportRow.implicitHeight + Style.marginM
    radius: Style.radiusS
    color: supportArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : Color.transparent
    border.width: 0

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    RowLayout {
      id: supportRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.support")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }

      NIcon {
        icon: supportArea.containsMouse ? "heart-filled" : "heart"
        pointSize: 14
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }
    }

    MouseArea {
      id: supportArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://ko-fi.com/lysec"])
        ToastService.showNotice(I18n.tr("settings.about.support"), I18n.tr("toast.kofi.opened"))
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXXXL
    Layout.bottomMargin: Style.marginXL
  }

  // Contributors
  NHeader {
    label: I18n.tr("settings.about.contributors.section.label")
    description: root.contributors.length === 1 ? I18n.tr("settings.about.contributors.section.description", {
                                                            "count": root.contributors.length
                                                          }) : I18n.tr("settings.about.contributors.section.description_plural", {
                                                                         "count": root.contributors.length
                                                                       })
  }

  GridView {
    id: contributorsGrid

    readonly property int columnsCount: 2

    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: cellWidth * columnsCount
    Layout.preferredHeight: {
      if (root.contributors.length === 0)
        return 0

      const rows = Math.ceil(root.contributors.length / columnsCount)
      return rows * cellHeight
    }
    cellWidth: Math.round(Style.baseWidgetSize * 7)
    cellHeight: Math.round(Style.baseWidgetSize * 2.5)
    model: root.contributors

    delegate: Rectangle {
      width: contributorsGrid.cellWidth - Style.marginM
      height: contributorsGrid.cellHeight - Style.marginM
      radius: Style.radiusL
      color: contributorArea.containsMouse ? Color.mHover : Color.transparent

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginM

        Item {
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredWidth: Style.baseWidgetSize * 2 * Style.uiScaleRatio
          Layout.preferredHeight: Style.baseWidgetSize * 2 * Style.uiScaleRatio

          NImageCircled {
            imagePath: modelData.avatar_url || ""
            anchors.fill: parent
            anchors.margins: Style.marginXS
            fallbackIcon: "person"
            borderColor: contributorArea.containsMouse ? Color.mOnHover : Color.mPrimary
            borderWidth: Style.borderM

            Behavior on borderColor {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        ColumnLayout {
          spacing: Style.marginXS
          Layout.alignment: Qt.AlignVCenter
          Layout.fillWidth: true

          NText {
            text: modelData.login || "Unknown"
            font.weight: Style.fontWeightBold
            color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurface
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          NText {
            text: (modelData.contributions || 0) + " " + ((modelData.contributions || 0) === 1 ? "commit" : "commits")
            pointSize: Style.fontSizeXS
            color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
          }
        }
      }

      MouseArea {
        id: contributorArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (modelData.html_url)
            Quickshell.execDetached(["xdg-open", modelData.html_url])
        }
      }
    }
  }
}
