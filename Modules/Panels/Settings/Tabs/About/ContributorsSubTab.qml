import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Widgets

ColumnLayout {
  id: root

  property var contributors: GitHubService.contributors
  property int avatarCacheVersion: 0

  readonly property int topContributorsCount: 20

  Connections {
    target: GitHubService
    function onCachedAvatarsChanged() {
      root.avatarCacheVersion++;
    }
  }

  spacing: Style.marginL

  NHeader {
    description: root.contributors.length === 1 ? I18n.tr("panels.about.contributors-desc", {
                                                            "count": root.contributors.length
                                                          }) : I18n.tr("panels.about.contributors-description-plural", {
                                                                         "count": root.contributors.length
                                                                       })
    enableDescriptionRichText: true
  }

  // Top 20 contributors with full cards (avoids GridView shader crashes on Qt 6.8)
  Flow {
    id: topContributorsFlow
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    spacing: Style.marginM

    Repeater {
      model: Math.min(root.contributors.length, root.topContributorsCount)

      delegate: Rectangle {
        width: Math.max(Math.round(topContributorsFlow.width / 2 - Style.marginM - 1), Math.round(Style.baseWidgetSize * 4))
        height: Math.round(Style.baseWidgetSize * 2.3)
        radius: Style.radiusM
        color: contributorArea.containsMouse ? Color.mHover : "transparent"
        border.width: 1
        border.color: contributorArea.containsMouse ? Color.mPrimary : Color.mOutline

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

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Avatar container with rectangular design (modern, no shader issues)
          Item {
            id: wrapper
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Style.baseWidgetSize * 1.8
            Layout.preferredHeight: Style.baseWidgetSize * 1.8

            property bool isRounded: false

            // Background and image container
            Item {
              anchors.fill: parent

              // Simple circular image (pre-rendered, no shaders)
              Image {
                anchors.fill: parent
                source: {
                  // Depend on avatarCacheVersion to trigger re-evaluation
                  var _ = root.avatarCacheVersion;
                  // Try cached circular version first
                  var username = root.contributors[index].login;
                  var cached = GitHubService.getAvatarPath(username);
                  if (cached) {
                    wrapper.isRounded = true;
                    return cached;
                  }

                  // Fall back to original avatar URL
                  return root.contributors[index].avatar_url || "";
                }
                fillMode: Image.PreserveAspectFit // Fit since image is already circular with transparency
                mipmap: true
                smooth: true
                asynchronous: true
                visible: root.contributors[index].avatar_url !== undefined && root.contributors[index].avatar_url !== ""
                opacity: status === Image.Ready ? 1.0 : 0.0

                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              // Fallback icon
              NIcon {
                anchors.centerIn: parent
                visible: !root.contributors[index].avatar_url || root.contributors[index].avatar_url === ""
                icon: "person"
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }
            }

            Rectangle {
              visible: wrapper.isRounded
              anchors.fill: parent
              color: "transparent"
              radius: width * 0.5
              border.width: Style.borderM
              border.color: Color.mPrimary
            }
          }

          // Info column
          ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            NText {
              text: root.contributors[index].login || "Unknown"
              font.weight: Style.fontWeightBold
              color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
              pointSize: Style.fontSizeS
            }

            RowLayout {
              spacing: Style.marginXS
              Layout.fillWidth: true

              NIcon {
                icon: "git-commit"
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }

              NText {
                text: `${(root.contributors[index].contributions || 0).toString()} commits`
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }
            }
          }

          // Hover indicator
          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: "arrow-right"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
            opacity: contributorArea.containsMouse ? 1.0 : 0.0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        MouseArea {
          id: contributorArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index].html_url]);
          }
        }
      }
    }
  }

  // Remaining contributors (simple text links)
  Flow {
    id: remainingContributorsFlow
    visible: root.contributors.length > root.topContributorsCount
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    spacing: Style.marginS

    Repeater {
      model: Math.max(0, root.contributors.length - root.topContributorsCount)

      delegate: Rectangle {
        width: nameText.implicitWidth + Style.marginM * 2
        height: nameText.implicitHeight + Style.marginS * 2
        radius: Style.radiusS
        color: nameArea.containsMouse ? Color.mHover : "transparent"
        border.width: Style.borderS
        border.color: nameArea.containsMouse ? Color.mPrimary : Color.mOutline

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

        NText {
          id: nameText
          anchors.centerIn: parent
          text: root.contributors[index + root.topContributorsCount].login || "Unknown"
          pointSize: Style.fontSizeXS
          color: nameArea.containsMouse ? Color.mOnHover : Color.mOnSurface
          font.weight: Style.fontWeightMedium

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        MouseArea {
          id: nameArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index + root.topContributorsCount].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index + root.topContributorsCount].html_url]);
          }
        }
      }
    }
  }
}
