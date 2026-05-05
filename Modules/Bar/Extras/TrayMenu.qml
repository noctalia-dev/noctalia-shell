import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

PopupWindow {
  id: root

  property ShellScreen screen

  property var trayItem: null
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property string widgetSection: ""
  property int widgetIndex: -1

  // Derive menu from trayItem (only used for non-submenus)
  readonly property QsMenuHandle menu: isSubMenu ? null : (trayItem ? trayItem.menu : null)

  // Compute if current tray item is pinned
  readonly property bool isPinned: {
    if (!trayItem || widgetSection === "" || widgetIndex < 0)
      return false;
    var widgets = Settings.getBarWidgetsForScreen(root.screen?.name)[widgetSection];
    if (!widgets || widgetIndex >= widgets.length)
      return false;
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray")
      return false;
    var pinnedList = widgetSettings.pinned || [];
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] === itemName)
        return true;
    }
    return false;
  }

  readonly property int menuWidth: 220

  implicitWidth: menuWidth

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(screen?.height * 0.9, flickable.contentHeight + Style.margin2S)

  // When implicitHeight changes (menu content loads), force anchor recalculation
  onImplicitHeightChanged: {
    if (visible && anchorItem) {
      Qt.callLater(() => {
                     anchor.updateAnchor();
                   });
    }
  }

  visible: false
  onVisibleChanged: PanelService.childrenVisible(visible)

  color: "transparent"
  anchor.item: anchorItem
  anchor.rect.x: {
    if (anchorItem && screen) {
      let baseX = anchorX;

      // Calculate position relative to current screen
      let menuScreenX;
      if (isSubMenu && anchorItem.Window && anchorItem.Window.window) {
        const posInPopup = anchorItem.mapToItem(null, 0, 0);
        const parentWindow = anchorItem.Window.window;
        const windowXOnScreen = parentWindow.x - screen.x;
        menuScreenX = windowXOnScreen + posInPopup.x + baseX;
      } else {
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        const anchorScreenX = anchorGlobalPos.x;
        menuScreenX = anchorScreenX + baseX;
      }

      const menuRight = menuScreenX + implicitWidth;
      const screenRight = screen.width;
      const menuLeft = menuScreenX;

      // Only adjust if menu would clip off screen boundaries
      // Don't adjust if the positioning is intentional (e.g., negative offset for right bar)
      if (menuRight > screenRight && menuLeft < screenRight) {
        // Clipping on right edge - shift left
        const overflow = menuRight - screenRight;
        return baseX - overflow - Style.marginS;
      } else if (menuLeft < 0 && menuRight > 0) {
        // Clipping on left edge - shift right
        return baseX - menuLeft + Style.marginS;
      }

      return baseX;
    }
    return anchorX;
  }
  anchor.rect.y: {
    if (anchorItem && screen) {
      const barPosition = Settings.getBarPositionForScreen(root.screen?.name);

      let baseY = anchorY;

      // Only apply bottom bar special positioning if:
      // 1. Not a submenu
      // 2. Bar is at bottom
      // 3. anchorY is not already negative (if negative, it's pre-calculated from drawer)
      const shouldApplyBottomBarLogic = !isSubMenu && barPosition === "bottom" && anchorY >= 0;

      if (shouldApplyBottomBarLogic) {
        // For bottom bar from the bar itself, position menu above the anchor with margin
        baseY = -(implicitHeight + Style.marginS);
      } else if (barPosition === "top" && !isSubMenu && anchorY >= 0) {
        // For top bar: position menu below bar with margin
        const barHeight = Style.getBarHeightForScreen(root.screen?.name);
        baseY = barHeight + Style.marginS;
      }

      // Use a robust way to get screen coordinates
      const posInWindow = anchorItem.mapToItem(null, 0, 0);
      const parentWindow = anchorItem.Window.window;

      // Calculate screen-relative Y of the window
      let windowYOnScreen = (parentWindow && screen) ? (parentWindow.y - screen.y) : 0;

      // If window reported 0 but bar is at bottom, assume it's at screen bottom
      if (windowYOnScreen === 0 && barPosition === "bottom" && screen) {
        windowYOnScreen = screen.height - (parentWindow ? parentWindow.height : Style.getBarHeightForScreen(screen.name));
      }

      // Calculate the screen Y of the menu top
      // Use a small guess for height if implicitHeight is 0 to avoid covering the bar on the first frame
      const effectiveHeight = implicitHeight > 0 ? implicitHeight : 200;
      const effectiveBaseY = shouldApplyBottomBarLogic ? -(effectiveHeight + Style.marginS) : baseY;

      const menuScreenY = windowYOnScreen + posInWindow.y + effectiveBaseY;
      const menuBottom = menuScreenY + (implicitHeight > 0 ? implicitHeight : effectiveHeight);
      const screenHeight = screen ? screen.height : 1080;

      // Adjust the final baseY (the actual value returned to anchor.rect.y)
      let finalBaseY = shouldApplyBottomBarLogic ? -(implicitHeight + Style.marginS) : baseY;

      // Adjust if menu would clip off the bottom
      if (menuBottom > screenHeight) {
        const overflow = menuBottom - screenHeight;
        finalBaseY -= (overflow + Style.marginS);
      }

      // Adjust if menu would clip off the top
      // menuScreenY < 0 means it's above the screen edge
      if (menuScreenY < 0) {
        finalBaseY -= (menuScreenY - Style.marginS);
      }

      return finalBaseY;
    }

    // Fallback if no anchor/screen
    if (isSubMenu) {
      return anchorY;
    }
    return anchorY + (Settings.getBarPositionForScreen(root.screen?.name) === "bottom" ? -implicitHeight : Style.getBarHeightForScreen(root.screen?.name));
  }

  function showAt(item, x, y) {
    if (!item) {
      Logger.w("TrayMenu", "anchorItem is undefined, won't show menu.");
      return;
    }

    if (!opener.children || opener.children.values.length === 0) {
      //Logger.w("TrayMenu", "Menu not ready, delaying show")
      Qt.callLater(() => showAt(item, x, y));
      return;
    }

    anchorItem = item;
    anchorX = x;
    anchorY = y;

    visible = true;
    forceActiveFocus();

    // Force update after showing.
    Qt.callLater(() => {
                   root.anchor.updateAnchor();
                 });
  }

  function hideMenu() {
    visible = false;

    // Clean up all submenus recursively
    for (var i = 0; i < columnLayout.children.length; i++) {
      const child = columnLayout.children[i];
      if (child?.subMenu) {
        child.subMenu.hideMenu();
        child.subMenu.destroy();
        child.subMenu = null;
      }
    }
  }

  Item {
    anchors.fill: parent
    Keys.onEscapePressed: root.hideMenu()
  }

  QsMenuOpener {
    id: opener
    menu: root.menu
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS)
    radius: Style.radiusM

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }

    // Use a ColumnLayout to handle menu item arrangement
    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        model: opener.children ? [...opener.children.values] : []

        delegate: Rectangle {
          id: entry
          required property var modelData

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: {
            if (modelData?.isSeparator) {
              return 8;
            } else {
              // Calculate based on text content
              const textHeight = text.contentHeight || (Style.fontSizeS * 1.2);
              return Math.max(28, textHeight + Style.margin2S);
            }
          }

          color: "transparent"
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - Style.margin2M
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mHover : "transparent"
            radius: Style.radiusS
            visible: !(modelData?.isSeparator ?? false)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginS

              // Indicator Container
              Item {
                visible: (modelData?.buttonType ?? QsMenuButtonType.None) !== QsMenuButtonType.None

                implicitWidth: Math.round(Style.baseWidgetSize * 0.5)
                implicitHeight: Math.round(Style.baseWidgetSize * 0.5)
                Layout.alignment: Qt.AlignVCenter

                // Helper properties
                readonly property int type: modelData?.buttonType ?? QsMenuButtonType.None
                readonly property bool isRadio: type === QsMenuButtonType.RadioButton
                readonly property bool isChecked: modelData?.checkState === Qt.Checked || (modelData?.checked ?? false)

                // Color Logic
                readonly property color activeColor: mouseArea.containsMouse ? Color.mOnHover : Color.mPrimary
                readonly property color checkMarkColor: mouseArea.containsMouse ? Color.mHover : Color.mOnPrimary
                readonly property color borderColor: isChecked ? activeColor : (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)

                // Checkbox Visuals
                Rectangle {
                  visible: !parent.isRadio
                  anchors.centerIn: parent
                  width: Math.round(Style.baseWidgetSize * 0.5)
                  height: Math.round(Style.baseWidgetSize * 0.5)
                  radius: Style.iRadiusXS
                  color: "transparent" // Transparent to match RadioButton style
                  border.color: parent.borderColor
                  border.width: Style.borderM

                  Behavior on border.color {
                    ColorAnimation {
                      duration: Style.animationFast
                    }
                  }

                  NIcon {
                    visible: parent.parent.isChecked
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    icon: "check"
                    color: parent.parent.activeColor
                    pointSize: Math.max(Style.fontSizeXXS, parent.width * 0.6)
                  }
                }

                // RadioButton Visuals
                Rectangle {
                  visible: parent.isRadio
                  anchors.centerIn: parent
                  width: Style.toOdd(Style.baseWidgetSize * 0.5)
                  height: Style.toOdd(Style.baseWidgetSize * 0.5)
                  radius: width / 2
                  color: "transparent"
                  border.color: parent.borderColor
                  border.width: Style.borderM // Slightly thicker for radio look

                  Behavior on border.color {
                    ColorAnimation {
                      duration: Style.animationFast
                    }
                  }

                  Rectangle {
                    visible: parent.parent.isChecked
                    anchors.centerIn: parent
                    width: Style.toOdd(parent.width * 0.5)
                    height: Style.toOdd(parent.height * 0.5)
                    radius: width / 2
                    color: parent.parent.activeColor

                    Behavior on color {
                      ColorAnimation {
                        duration: Style.animationFast
                      }
                    }
                  }
                }
              }

              NText {
                id: text
                Layout.fillWidth: true
                color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface) : Color.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                pointSize: Style.fontSizeS
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
              }

              Image {
                Layout.preferredWidth: Style.marginL
                Layout.preferredHeight: Style.marginL
                source: modelData?.icon ?? ""
                visible: (modelData?.icon ?? "") !== ""
                fillMode: Image.PreserveAspectFit
              }

              NIcon {
                icon: modelData?.hasChildren ? "menu" : ""
                pointSize: Style.fontSizeS
                applyUiScale: false
                verticalAlignment: Text.AlignVCenter
                visible: modelData?.hasChildren ?? false
                color: (mouseArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false) && root.visible
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                           if (modelData && !modelData.isSeparator) {
                             if (modelData.hasChildren) {
                               // Click on items with children toggles submenu
                               if (entry.subMenu) {
                                 // Close existing submenu
                                 entry.subMenu.hideMenu();
                                 entry.subMenu.destroy();
                                 entry.subMenu = null;
                               } else {
                                 // Close any other open submenus first
                                 for (var i = 0; i < columnLayout.children.length; i++) {
                                   const sibling = columnLayout.children[i];
                                   if (sibling !== entry && sibling.subMenu) {
                                     sibling.subMenu.hideMenu();
                                     sibling.subMenu.destroy();
                                     sibling.subMenu = null;
                                   }
                                 }

                                 // Determine submenu opening direction
                                 let openLeft = false;
                                 const barPosition = Settings.getBarPositionForScreen(root.screen?.name);
                                 const globalPos = entry.mapToItem(null, 0, 0);

                                 if (barPosition === "right") {
                                   openLeft = true;
                                 } else if (barPosition === "left") {
                                   openLeft = false;
                                 } else {
                                   openLeft = (root.widgetSection === "right");
                                 }

                                 // Open new submenu
                                 entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                                   "menu": modelData,
                                                                                                   "isSubMenu": true,
                                                                                                   "screen": root.screen
                                                                                                 });

                                 if (entry.subMenu) {
                                   const overlap = 60;
                                   entry.subMenu.anchorItem = entry;
                                   entry.subMenu.anchorX = openLeft ? -overlap : overlap;
                                   entry.subMenu.anchorY = 0;
                                   entry.subMenu.visible = true;
                                   // Force anchor update with new position
                                   Qt.callLater(() => {
                                                  entry.subMenu.anchor.updateAnchor();
                                                });
                                 }
                               }
                             } else {
                               // Click on regular items triggers them
                               modelData.triggered();
                               root.hideMenu();

                               // Close the drawer if it's open
                               if (root.screen) {
                                 const panel = PanelService.getPanel("trayDrawerPanel", root.screen);
                                 if (panel && panel.visible) {
                                   panel.close();
                                 }
                               }
                             }
                           }
                         }
            }
          }

          Component.onDestruction: {
            if (subMenu) {
              subMenu.destroy();
              subMenu = null;
            }
          }
        }
      }

      // PIN / UNPIN
      Rectangle {
        visible: {
          if (widgetSection === "" || widgetIndex < 0)
            return false;
          var widgets = Settings.getBarWidgetsForScreen(root.screen?.name)[widgetSection];
          if (!widgets || widgetIndex >= widgets.length)
            return false;
          var widgetSettings = widgets[widgetIndex];
          if (!widgetSettings)
            return false;
          return widgetSettings.drawerEnabled ?? false;
        }
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: 28
        color: pinUnpinMouseArea.containsMouse ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Qt.alpha(Color.mPrimary, pinUnpinMouseArea.containsMouse ? 0.4 : 0.2)
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: root.isPinned ? "unpin" : "pin"
            pointSize: Style.fontSizeS
            applyUiScale: false
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }

          NText {
            Layout.fillWidth: true
            color: Color.mPrimary
            text: root.isPinned ? I18n.tr("panels.bar.tray-unpin-application") : I18n.tr("panels.bar.tray-pin-application")
            pointSize: Style.fontSizeS
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: pinUnpinMouseArea
          anchors.fill: parent
          hoverEnabled: true

          onClicked: {
            if (root.isPinned) {
              root.removeFromPinned();
            } else {
              root.addToPinned();
            }
          }
        }
      }
    }
  }

  function addToPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot pin: missing tray item or widget info");
      return;
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot pin: tray item has no name");
      return;
    }
    var screenName = root.screen?.name || "";
    var widgets = Settings.getBarWidgetsForScreen(screenName)[widgetSection];
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot pin: invalid widget index");
      return;
    }
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot pin: widget is not a Tray widget");
      return;
    }
    var pinnedList = widgetSettings.pinned || [];
    var newPinned = pinnedList.slice();
    newPinned.push(itemName);
    var newSettings = Object.assign({}, widgetSettings);
    newSettings.pinned = newPinned;
    widgets[widgetIndex] = newSettings;

    // Write to the correct location: screen override or global
    if (Settings.hasScreenOverride(screenName, "widgets")) {
      var overrideWidgets = Settings.getBarWidgetsForScreen(screenName);
      overrideWidgets[widgetSection] = widgets;
      Settings.setScreenOverride(screenName, "widgets", overrideWidgets);
    } else {
      Settings.data.bar.widgets[widgetSection] = widgets;
    }
    Settings.saveImmediate();

    // Close drawer when pinning (drawer needs to resize)
    if (screen) {
      const panel = PanelService.getPanel("trayDrawerPanel", screen);
      if (panel)
        panel.close();
    }
  }

  function removeFromPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot unpin: missing tray item or widget info");
      return;
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || "";
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot unpin: tray item has no name");
      return;
    }
    var screenName = root.screen?.name || "";
    var widgets = Settings.getBarWidgetsForScreen(screenName)[widgetSection];
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot unpin: invalid widget index");
      return;
    }
    var widgetSettings = widgets[widgetIndex];
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot unpin: widget is not a Tray widget");
      return;
    }
    var pinnedList = widgetSettings.pinned || [];
    var newPinned = [];
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] !== itemName) {
        newPinned.push(pinnedList[i]);
      }
    }
    var newSettings = Object.assign({}, widgetSettings);
    newSettings.pinned = newPinned;
    widgets[widgetIndex] = newSettings;

    // Write to the correct location: screen override or global
    if (Settings.hasScreenOverride(screenName, "widgets")) {
      var overrideWidgets = Settings.getBarWidgetsForScreen(screenName);
      overrideWidgets[widgetSection] = widgets;
      Settings.setScreenOverride(screenName, "widgets", overrideWidgets);
    } else {
      Settings.data.bar.widgets[widgetSection] = widgets;
    }
    Settings.saveImmediate();
  }
}
