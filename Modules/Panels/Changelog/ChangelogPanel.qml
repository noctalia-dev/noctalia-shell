import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(820 * Style.uiScaleRatio)
  preferredHeight: Math.round(620 * Style.uiScaleRatio)
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  panelContent: Rectangle {
    id: panelContent
    color: Color.mSurfaceVariant
    radius: Style.radiusM
    border.color: Color.mOutline
    border.width: Style.borderS

    readonly property string currentVersion: UpdateService.currentVersion
    readonly property string previousVersion: UpdateService.previousVersion
    readonly property bool hasPreviousVersion: previousVersion && previousVersion.length > 0
    readonly property string releaseContent: UpdateService.releaseContent || ""

    function colorizeHeaders(text) {
      if (!text)
        return "";
      const color = Color.mPrimary;
      return text.replace(/^# (.*)$/gm, `<br/><h1 style="color:${color}">$1</h1><br/>`).replace(/^## (.*)$/gm, `<br/><h2 style="color:${color}">$1</h2><br/>`);
    }
    readonly property string subtitleText: hasPreviousVersion ? I18n.tr("changelog.panel.subtitle-updated", {
                                                                          "previousVersion": previousVersion
                                                                        }) : I18n.tr("changelog.panel.subtitle-fresh")

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "sparkles"
          color: Color.mPrimary
          pointSize: Style.fontSizeXXL
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: I18n.tr("changelog.panel.title", {
                            "version": currentVersion || UpdateService.currentVersion
                          })
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightBold
            color: Color.mPrimary
            wrapMode: Text.WordWrap
          }

          NText {
            text: subtitleText
            color: Color.mOnSurface
            opacity: Style.opacityMedium
            wrapMode: Text.WordWrap
          }
        }

        Item {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("common.close")
          onClicked: root.close()
          Layout.alignment: Qt.AlignTop | Qt.AlignRight
          Layout.preferredHeight: Style.baseWidgetSize
          Layout.preferredWidth: Style.baseWidgetSize
        }
      }

      Rectangle {
        clip: true
        Layout.fillWidth: true
        color: Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Color.mPrimary
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            text: hasPreviousVersion ? previousVersion : I18n.tr("changelog.panel.version-new-user")
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }

          NIcon {
            icon: "arrow-right"
            color: Color.mPrimary
          }

          NText {
            text: currentVersion || UpdateService.currentVersion
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NScrollView {
        id: changelogScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        padding: 0

        ColumnLayout {
          width: changelogScrollView.availableWidth
          spacing: Style.marginM

          NText {
            visible: UpdateService.fetchError !== ""
            text: UpdateService.fetchError
            color: Color.mError
            wrapMode: Text.WordWrap
          }

          NText {
            Layout.fillWidth: true
            visible: releaseContent.length > 0
            text: panelContent.colorizeHeaders(releaseContent)
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            textFormat: Text.MarkdownText
            color: Color.mOnSurface
          }

          NText {
            visible: releaseContent.length === 0
            text: I18n.tr("changelog.panel.empty")
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NButton {
          Layout.fillWidth: true
          icon: "brand-discord"
          text: I18n.tr("changelog.panel.buttons-discord")
          outlined: true
          onClicked: UpdateService.openDiscord()
        }

        NButton {
          Layout.fillWidth: true
          visible: UpdateService.feedbackUrl !== ""
          icon: "forms"
          text: I18n.tr("changelog.panel.buttons-feedback")
          outlined: true
          onClicked: UpdateService.openFeedbackForm()
        }

        NButton {
          Layout.fillWidth: true
          icon: "check"
          text: I18n.tr("changelog.panel.buttons-dismiss")
          onClicked: root.close()
        }
      }
    }
  }

  onClosed: {
    if (UpdateService && UpdateService.changelogCurrentVersion) {
      UpdateService.markChangelogSeen(UpdateService.changelogCurrentVersion);
    }
  }
}
