import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var supporters: SupporterService.supporters
  property int avatarCacheVersion: 0

  Connections {
    target: SupporterService
    function onCachedAvatarsChanged() {
      root.avatarCacheVersion++;
    }
  }

  spacing: Style.marginL

  NHeader {
    description: root.supporters.length === 0 ? I18n.tr("panels.about.supporters-loading") : I18n.trp("panels.about.supporters-desc", root.supporters.length)
    enableDescriptionRichText: true
  }

  NButton {
    Layout.alignment: Qt.AlignHCenter
    icon: "heart"
    text: I18n.tr("panels.about.become-supporter")
    outlined: true
    onClicked: {
      Quickshell.execDetached(["xdg-open", "https://buymeacoffee.com/noctalia"]);
      ToastService.showNotice(I18n.tr("panels.about.support"), I18n.tr("toast.donation-opened"));
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
  }

  // Supporter cards
  Flow {
    id: supportersFlow
    visible: root.supporters.length > 0
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    spacing: Style.marginL

    Repeater {
      model: root.supporters.length

      delegate: Rectangle {
        id: supporterCard

        property bool hasGithub: !!root.supporters[index].github_username

        width: Math.max(Math.round(supportersFlow.width / 2 - Style.marginL - 1), Math.round(Style.baseWidgetSize * 4.5))
        height: Math.round(Style.baseWidgetSize * 2.6)
        radius: Style.radiusM
        color: supporterArea.containsMouse && hasGithub ? Color.mHover : Qt.alpha(Color.mPrimary, 0.05)
        border.width: Style.borderM
        border.color: supporterArea.containsMouse && hasGithub ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)

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

          // Avatar with heart badge
          Item {
            id: avatarWrapper
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Style.baseWidgetSize * 2.0
            Layout.preferredHeight: Style.baseWidgetSize * 2.0

            property bool isRounded: false

            Item {
              anchors.fill: parent

              Image {
                anchors.fill: parent
                visible: supporterCard.hasGithub
                source: {
                  if (!supporterCard.hasGithub)
                    return "";
                  var _ = root.avatarCacheVersion;
                  var username = root.supporters[index].github_username;
                  var cached = SupporterService.getAvatarPath(username);
                  if (cached) {
                    avatarWrapper.isRounded = true;
                    return cached;
                  }
                  return "https://github.com/" + username + ".png?size=256";
                }
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
                asynchronous: true
                opacity: status === Image.Ready ? 1.0 : 0.0

                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              // Fallback logo for supporters without GitHub
              Rectangle {
                anchors.fill: parent
                visible: !supporterCard.hasGithub
                radius: width * 0.5
                color: Qt.alpha(Color.mPrimary, 0.15)

                Image {
                  anchors.centerIn: parent
                  source: "../../../../../Assets/noctalia.svg"
                  width: parent.width * 0.75
                  height: width
                  fillMode: Image.PreserveAspectFit
                  mipmap: true
                  smooth: true
                }
              }
            }

            Rectangle {
              visible: avatarWrapper.isRounded || !supporterCard.hasGithub
              anchors.fill: parent
              color: "transparent"
              radius: width * 0.5
              border.width: Style.borderM
              border.color: Color.mPrimary
            }

            // Heart badge
            Rectangle {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.rightMargin: -2
              anchors.bottomMargin: -2
              width: Style.fontSizeM + Style.marginS
              height: width
              radius: width * 0.5
              color: Color.mPrimary

              NIcon {
                anchors.centerIn: parent
                icon: "heart-filled"
                pointSize: Style.fontSizeXS
                color: Color.mOnPrimary
              }
            }
          }

          // Info column
          ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            NText {
              text: root.supporters[index].name || root.supporters[index].github_username || "Unknown"
              font.weight: Style.fontWeightBold
              color: supporterArea.containsMouse && supporterCard.hasGithub ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
              pointSize: Style.fontSizeS
            }

            NText {
              text: I18n.tr("panels.about.supporter-badge")
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
              font.weight: Style.fontWeightMedium
            }
          }

          // Hover indicator (only for supporters with GitHub)
          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: "arrow-right"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
            visible: supporterCard.hasGithub
            opacity: supporterArea.containsMouse ? 1.0 : 0.0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        MouseArea {
          id: supporterArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: supporterCard.hasGithub ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            var username = root.supporters[index].github_username;
            if (username) {
              Quickshell.execDetached(["xdg-open", "https://github.com/" + username]);
            }
          }
        }
      }
    }
  }
}
