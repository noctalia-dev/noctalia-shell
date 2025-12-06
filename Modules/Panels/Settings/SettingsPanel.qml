import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings.Tabs
import qs.Modules.Panels.Settings.Tabs.ColorScheme
import qs.Modules.Panels.Settings.Tabs.SessionMenu
import qs.Services.System
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(820 * Style.uiScaleRatio)
  preferredHeight: Math.round(910 * Style.uiScaleRatio)

  readonly property bool attachToBar: Settings.data.ui.settingsPanelAttachToBar
  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barFloating: Settings.data.bar.floating
  readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
  readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

  forceAttachToBar: attachToBar
  panelAnchorHorizontalCenter: attachToBar ? (barPosition === "top" || barPosition === "bottom") : true
  panelAnchorVerticalCenter: attachToBar ? (barPosition === "left" || barPosition === "right") : true
  panelAnchorTop: attachToBar && barPosition === "top"
  panelAnchorBottom: attachToBar && barPosition === "bottom"
  panelAnchorLeft: attachToBar && barPosition === "left"
  panelAnchorRight: attachToBar && barPosition === "right"

  onAttachToBarChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarPositionChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarFloatingChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarMarginHChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarMarginVChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  // Tabs enumeration, order is NOT relevant
  enum Tab {
    About,
    Audio,
    Bar,
    ColorScheme,
    LockScreen,
    ControlCenter,
    OSD,
    Display,
    Dock,
    General,
    Hooks,
    Launcher,
    Location,
    Network,
    Notifications,
    Plugins,
    ScreenRecorder,
    SessionMenu,
    SystemMonitor,
    UserInterface,
    Wallpaper
  }

  property int requestedTab: SettingsPanel.Tab.General
  property int currentTabIndex: 0
  property var tabsModel: []
  property var activeScrollView: null

  Component.onCompleted: {
    updateTabsModel();
  }

  Component {
    id: generalTab
    GeneralTab {}
  }
  Component {
    id: launcherTab
    LauncherTab {}
  }
  Component {
    id: barTab
    BarTab {}
  }
  Component {
    id: audioTab
    AudioTab {}
  }
  Component {
    id: displayTab
    DisplayTab {}
  }
  Component {
    id: osdTab
    OsdTab {}
  }
  Component {
    id: networkTab
    NetworkTab {}
  }
  Component {
    id: locationTab
    LocationTab {}
  }
  Component {
    id: colorSchemeTab
    ColorSchemeTab {}
  }
  Component {
    id: wallpaperTab
    WallpaperTab {}
  }
  Component {
    id: screenRecorderTab
    ScreenRecorderTab {}
  }
  Component {
    id: aboutTab
    AboutTab {}
  }
  Component {
    id: hooksTab
    HooksTab {}
  }
  Component {
    id: dockTab
    DockTab {}
  }
  Component {
    id: notificationsTab
    NotificationsTab {}
  }
  Component {
    id: controlCenterTab
    ControlCenterTab {}
  }
  Component {
    id: userInterfaceTab
    UserInterfaceTab {}
  }
  Component {
    id: lockScreenTab
    LockScreenTab {}
  }
  Component {
    id: sessionMenuTab
    SessionMenuTab {}
  }
  Component {
    id: systemMonitorTab
    SystemMonitorTab {}
  }
  Component {
    id: pluginsTab
    PluginsTab {}
  }

  // Order *DOES* matter
  function updateTabsModel() {
    let newTabs = [
          {
            "id": SettingsPanel.Tab.General,
            "label": "settings.general.title",
            "icon": "settings-general",
            "source": generalTab
          },
          {
            "id": SettingsPanel.Tab.UserInterface,
            "label": "settings.user-interface.title",
            "icon": "settings-user-interface",
            "source": userInterfaceTab
          },
          {
            "id": SettingsPanel.Tab.ColorScheme,
            "label": "settings.color-scheme.title",
            "icon": "settings-color-scheme",
            "source": colorSchemeTab
          },
          {
            "id": SettingsPanel.Tab.Wallpaper,
            "label": "settings.wallpaper.title",
            "icon": "settings-wallpaper",
            "source": wallpaperTab
          },
          {
            "id": SettingsPanel.Tab.Bar,
            "label": "settings.bar.title",
            "icon": "settings-bar",
            "source": barTab
          },
          {
            "id": SettingsPanel.Tab.Dock,
            "label": "settings.dock.title",
            "icon": "settings-dock",
            "source": dockTab
          },
          {
            "id": SettingsPanel.Tab.ControlCenter,
            "label": "settings.control-center.title",
            "icon": "settings-control-center",
            "source": controlCenterTab
          },
          {
            "id": SettingsPanel.Tab.Launcher,
            "label": "settings.launcher.title",
            "icon": "settings-launcher",
            "source": launcherTab
          },
          {
            "id": SettingsPanel.Tab.Notifications,
            "label": "settings.notifications.title",
            "icon": "settings-notifications",
            "source": notificationsTab
          },
          {
            "id": SettingsPanel.Tab.OSD,
            "label": "settings.osd.title",
            "icon": "settings-osd",
            "source": osdTab
          },
          {
            "id": SettingsPanel.Tab.LockScreen,
            "label": "settings.lock-screen.title",
            "icon": "settings-lock-screen",
            "source": lockScreenTab
          },
          {
            "id": SettingsPanel.Tab.SessionMenu,
            "label": "settings.session-menu.title",
            "icon": "settings-session-menu",
            "source": sessionMenuTab
          },
          {
            "id": SettingsPanel.Tab.Audio,
            "label": "settings.audio.title",
            "icon": "settings-audio",
            "source": audioTab
          },
          {
            "id": SettingsPanel.Tab.Display,
            "label": "settings.display.title",
            "icon": "settings-display",
            "source": displayTab
          },
          {
            "id": SettingsPanel.Tab.Network,
            "label": "settings.network.title",
            "icon": "settings-network",
            "source": networkTab
          },
          {
            "id": SettingsPanel.Tab.Location,
            "label": "settings.location.title",
            "icon": "settings-location",
            "source": locationTab
          },
          {
            "id": SettingsPanel.Tab.ScreenRecorder,
            "label": "settings.screen-recorder.title",
            "icon": "settings-screen-recorder",
            "source": screenRecorderTab
          },
          {
            "id": SettingsPanel.Tab.SystemMonitor,
            "label": "settings.system-monitor.title",
            "icon": "settings-system-monitor",
            "source": systemMonitorTab
          },
          {
            "id": SettingsPanel.Tab.Plugins,
            "label": "settings.plugins.title",
            "icon": "plugin",
            "source": pluginsTab
          },
          {
            "id": SettingsPanel.Tab.Hooks,
            "label": "settings.hooks.title",
            "icon": "settings-hooks",
            "source": hooksTab
          },
          {
            "id": SettingsPanel.Tab.About,
            "label": "settings.about.title",
            "icon": "settings-about",
            "source": aboutTab
          }
        ];

    root.tabsModel = newTabs; // Assign the generated list to the model
  }

  // When the panel opens, choose the appropriate tab
  onOpened: {
    // Run program availability checks every time settings opens
    ProgramCheckerService.checkAllPrograms();
    updateTabsModel();

    var initialIndex = SettingsPanel.Tab.General;
    if (root.requestedTab !== null) {
      for (var i = 0; i < root.tabsModel.length; i++) {
        if (root.tabsModel[i].id === root.requestedTab) {
          initialIndex = i;
          break;
        }
      }
    }

    // Now that the UI is settled, set the current tab index.
    root.currentTabIndex = initialIndex;
  }

  // Add scroll functions
  function scrollDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const stepSize = activeScrollView.height * 0.1; // Scroll 10% of viewport
      scrollBar.position = Math.min(scrollBar.position + stepSize / activeScrollView.contentHeight, 1.0 - scrollBar.size);
    }
  }

  function scrollUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const stepSize = activeScrollView.height * 0.1; // Scroll 10% of viewport
      scrollBar.position = Math.max(scrollBar.position - stepSize / activeScrollView.contentHeight, 0);
    }
  }

  function scrollPageDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const pageSize = activeScrollView.height * 0.9; // Scroll 90% of viewport
      scrollBar.position = Math.min(scrollBar.position + pageSize / activeScrollView.contentHeight, 1.0 - scrollBar.size);
    }
  }

  function scrollPageUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const pageSize = activeScrollView.height * 0.9; // Scroll 90% of viewport
      scrollBar.position = Math.max(scrollBar.position - pageSize / activeScrollView.contentHeight, 0);
    }
  }

  // Add navigation functions
  function selectNextTab() {
    if (tabsModel.length > 0) {
      currentTabIndex = (currentTabIndex + 1) % tabsModel.length;
    }
  }

  function selectPreviousTab() {
    if (tabsModel.length > 0) {
      currentTabIndex = (currentTabIndex - 1 + tabsModel.length) % tabsModel.length;
    }
  }

  // Override keyboard handlers from SmartPanel
  function onTabPressed() {
    selectNextTab();
  }

  function onBackTabPressed() {
    selectPreviousTab();
  }

  function onUpPressed() {
    scrollUp();
  }

  function onDownPressed() {
    scrollDown();
  }

  function onPageUpPressed() {
    scrollPageUp();
  }

  function onPageDownPressed() {
    scrollPageDown();
  }

  function onCtrlJPressed() {
    scrollDown();
  }

  function onCtrlKPressed() {
    scrollUp();
  }

  panelContent: Rectangle {
    color: Color.transparent

    // Main layout container that fills the panel
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: 0

      // Main content area
      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginL

        // Sidebar
        Rectangle {
          id: sidebar

          clip: true
          Layout.preferredWidth: 220 * Style.uiScaleRatio
          Layout.fillHeight: true
          Layout.alignment: Qt.AlignTop
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Style.borderS
          radius: Style.radiusM

          Item {
            anchors.fill: parent

            NListView {
              id: sidebarList
              anchors.fill: parent
              anchors.margins: Style.marginS
              model: root.tabsModel
              spacing: Style.marginXS
              currentIndex: root.currentTabIndex
              verticalPolicy: ScrollBar.AsNeeded

              delegate: Rectangle {
                id: tabItem
                width: sidebarList.verticalScrollBarActive ? sidebarList.width - sidebarList.scrollBarWidth - Style.marginXS : sidebarList.width
                height: tabEntryRow.implicitHeight + Style.marginS * 2
                radius: Style.radiusS
                color: selected ? Color.mPrimary : (tabItem.hovering ? Color.mHover : Color.transparent)
                readonly property bool selected: index === root.currentTabIndex
                property bool hovering: false
                property color tabTextColor: selected ? Color.mOnPrimary : (tabItem.hovering ? Color.mOnHover : Color.mOnSurface)

                Behavior on width {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                Behavior on tabTextColor {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                RowLayout {
                  id: tabEntryRow
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginS
                  anchors.rightMargin: Style.marginS
                  spacing: Style.marginM

                  // Tab icon
                  NIcon {
                    icon: modelData.icon
                    color: tabTextColor
                    pointSize: Style.fontSizeXL
                  }

                  // Tab label
                  NText {
                    text: I18n.tr(modelData.label)
                    color: tabTextColor
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightBold
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  onEntered: tabItem.hovering = true
                  onExited: tabItem.hovering = false
                  onCanceled: tabItem.hovering = false
                  onClicked: root.currentTabIndex = index
                }
              }

              onCurrentIndexChanged: {
                if (currentIndex !== root.currentTabIndex) {
                  root.currentTabIndex = currentIndex;
                }
              }

              Connections {
                target: root
                function onCurrentTabIndexChanged() {
                  if (sidebarList.currentIndex !== root.currentTabIndex) {
                    sidebarList.currentIndex = root.currentTabIndex;
                    sidebarList.positionViewAtIndex(root.currentTabIndex, ListView.Contain);
                  }
                }
              }
            }

            // Overlay gradient for sidebar scrolling (only visible when scrollable)
            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.borderS
              radius: Style.radiusM
              color: Color.transparent
              visible: sidebarList.verticalScrollBarActive
              gradient: Gradient {
                GradientStop {
                  position: 0.0
                  color: Color.transparent
                }
                GradientStop {
                  position: 0.95
                  color: Color.transparent
                }
                GradientStop {
                  position: 1.0
                  color: Color.mSurfaceVariant
                }
              }
            }
          }
        }

        // Content pane
        Rectangle {
          id: contentPane
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.alignment: Qt.AlignTop
          radius: Style.radiusM
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Style.borderS

          ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginS

            // Header row
            RowLayout {
              id: headerRow
              Layout.fillWidth: true
              spacing: Style.marginS

              // Main icon
              NIcon {
                icon: root.tabsModel[currentTabIndex]?.icon
                color: Color.mPrimary
                pointSize: Style.fontSizeXXL
              }

              // Main title
              NText {
                text: I18n.tr(root.tabsModel[currentTabIndex]?.label) || ""
                pointSize: Style.fontSizeXL
                font.weight: Style.fontWeightBold
                color: Color.mPrimary
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              // Close button
              NIconButton {
                icon: "close"
                tooltipText: I18n.tr("tooltips.close")
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.close()
              }
            }

            // Divider
            NDivider {
              Layout.fillWidth: true
            }

            // Tab content area
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              color: Color.transparent

              Repeater {
                model: root.tabsModel
                delegate: Loader {
                  anchors.fill: parent
                  active: index === root.currentTabIndex

                  onStatusChanged: {
                    if (status === Loader.Ready && item) {
                      // Find and store reference to the ScrollView
                      const scrollView = item.children[0];
                      if (scrollView && scrollView.toString().includes("ScrollView")) {
                        root.activeScrollView = scrollView;
                      }
                    }
                  }

                  sourceComponent: Flickable {
                    // Using a Flickable here with a pressDelay to fix conflict between
                    // ScrollView and NTextInput. This fixes the weird text selection issue.
                    id: flickable
                    anchors.fill: parent
                    pressDelay: 200

                    NScrollView {
                      id: scrollView
                      anchors.fill: parent
                      horizontalPolicy: ScrollBar.AlwaysOff
                      verticalPolicy: ScrollBar.AsNeeded
                      padding: Style.marginL
                      Component.onCompleted: {
                        root.activeScrollView = scrollView;
                      }

                      Loader {
                        active: true
                        sourceComponent: root.tabsModel[index]?.source
                        width: scrollView.availableWidth
                      }
                    }
                  }
                }
              }

              // Overlay gradient for content scrolling (only visible when scrollable)
              Rectangle {
                anchors.fill: parent
                color: Color.transparent
                visible: root.activeScrollView && root.activeScrollView.ScrollBar.vertical && root.activeScrollView.ScrollBar.vertical.size < 1.0
                gradient: Gradient {
                  GradientStop {
                    position: 0.0
                    color: Color.transparent
                  }
                  GradientStop {
                    position: 0.95
                    color: Color.transparent
                  }
                  GradientStop {
                    position: 1.0
                    color: Qt.alpha(Color.mSurfaceVariant, 0.95)
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
