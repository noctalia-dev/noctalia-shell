import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

// Button that shows a dropdown menu for selecting Bluetooth audio profiles (A2DP, HSP/HFP, etc.)
// Located in: Audio Panel → Devices tab → next to Bluetooth audio devices
Item {
  id: root

  property PwNode device: null
  property ShellScreen screen: null

  // Reactivity trigger for profile cache updates
  property int _cacheVersion: 0

  readonly property string cardName: device ? AudioService.getBluetoothCardName(device) : ""
  readonly property bool isBluetooth: cardName !== ""
  readonly property var profileData: {
    var _ = _cacheVersion;
    return cardName ? AudioService.getCachedBluetoothProfiles(cardName) : null;
  }
  readonly property bool hasProfiles: profileData && profileData.profiles && profileData.profiles.length > 1

  visible: isBluetooth && hasProfiles
  implicitWidth: visible ? Style.toOdd(Style.baseWidgetSize * 0.7 * Style.uiScaleRatio) : 0
  implicitHeight: implicitWidth

  // Query profiles on load
  Component.onCompleted: {
    if (isBluetooth) {
      AudioService.queryBluetoothProfiles(cardName);
    }
  }

  onCardNameChanged: {
    if (cardName) {
      AudioService.queryBluetoothProfiles(cardName);
    }
  }

  Connections {
    target: AudioService
    function onBluetoothProfilesChanged(changedCard) {
      if (changedCard === root.cardName) {
        root._cacheVersion++;
      }
    }
  }

  // Context menu for profile selection - positioned to the right of the button
  NPopupContextMenu {
    id: profileMenu
    screen: root.screen
    positionHint: "left"  // Position menu to the right of anchor (like left-bar behavior)

    model: {
      if (!root.profileData || !root.profileData.profiles)
        return [];
      var active = root.profileData.activeProfile || "";
      return root.profileData.profiles.map(function (p) {
        return {
          label: p.displayName,
          action: p.name,
          icon: p.name === active ? "check" : undefined
        };
      });
    }

    onTriggered: function (action, item) {
      profileMenu.close();
      PanelService.closeContextMenu(root.screen);
      if (action && root.cardName) {
        AudioService.setBluetoothProfile(root.cardName, action);
      }
    }
  }

  NIconButton {
    anchors.fill: parent
    icon: "bluetooth"
    baseSize: parent.width
    applyUiScale: false
    tooltipText: {
      if (!root.profileData)
        return "";
      var active = root.profileData.activeProfile || "";
      var profiles = root.profileData.profiles || [];
      var entry = profiles.find(function (p) {
        return p.name === active;
      });
      return I18n.tr("panels.audio.bluetooth-profile-tooltip", {
                       profile: entry ? entry.displayName : active
                     });
    }

    onClicked: {
      if (root.hasProfiles) {
        PanelService.showContextMenu(profileMenu, root, root.screen);
      }
    }
  }
}
