import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings.Tabs
import qs.Modules.Panels.Settings.Tabs.ColorScheme
import qs.Modules.Panels.Settings.Tabs.SessionMenu
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // Input: which tab to show initially
  property int requestedTab: 0

  // Exposed state for parent to access
  property int currentTabIndex: 0
  property var tabsModel: []
  property var activeScrollView: null
  property bool sidebarExpanded: true

  // Signal when close button is clicked
  signal closeRequested

  // Save sidebar state when it changes
  onSidebarExpandedChanged: {
    ShellState.setSettingsSidebarExpanded(sidebarExpanded);
  }

  Component.onCompleted: {
    // Restore sidebar state
    sidebarExpanded = ShellState.getSettingsSidebarExpanded();
  }

  // Tab components
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
  Component {
    id: desktopWidgetsTab
    DesktopWidgetsTab {}
  }

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
            "id": SettingsPanel.Tab.DesktopWidgets,
            "label": "settings.desktop-widgets.title",
            "icon": "clock",
            "source": desktopWidgetsTab
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

    root.tabsModel = newTabs;
  }

  function selectTabById(tabId) {
    for (var i = 0; i < tabsModel.length; i++) {
      if (tabsModel[i].id === tabId) {
        currentTabIndex = i;
        return;
      }
    }
    currentTabIndex = 0;
  }

  function initialize() {
    ProgramCheckerService.checkAllPrograms();
    updateTabsModel();
    selectTabById(requestedTab);
  }

  // Scroll functions
  function scrollDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const stepSize = activeScrollView.height * 0.1;
      scrollBar.position = Math.min(scrollBar.position + stepSize / activeScrollView.contentHeight, 1.0 - scrollBar.size);
    }
  }

  function scrollUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const stepSize = activeScrollView.height * 0.1;
      scrollBar.position = Math.max(scrollBar.position - stepSize / activeScrollView.contentHeight, 0);
    }
  }

  function scrollPageDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const pageSize = activeScrollView.height * 0.9;
      scrollBar.position = Math.min(scrollBar.position + pageSize / activeScrollView.contentHeight, 1.0 - scrollBar.size);
    }
  }

  function scrollPageUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical;
      const pageSize = activeScrollView.height * 0.9;
      scrollBar.position = Math.max(scrollBar.position - pageSize / activeScrollView.contentHeight, 0);
    }
  }

  // Tab navigation functions
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

  // Main UI
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginL

      // Sidebar
      Rectangle {
        id: sidebar

        readonly property bool panelVeryTransparent: Settings.data.ui.panelBackgroundOpacity <= 0.75

        clip: true
        Layout.preferredWidth: Math.round(root.sidebarExpanded ? 200 * Style.uiScaleRatio : sidebarToggle.width + (panelVeryTransparent ? Style.marginM * 2 : 0) + (sidebarList.verticalScrollBarActive ? Style.marginM : 0))
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop

        radius: sidebar.panelVeryTransparent ? Style.radiusM : 0
        color: sidebar.panelVeryTransparent ? Color.mSurfaceVariant : Color.transparent
        border.width: sidebar.panelVeryTransparent ? Style.borderS : 0
        border.color: sidebar.panelVeryTransparent ? Color.mOutline : Color.transparent

        Behavior on Layout.preferredWidth {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutQuad
          }
        }

        // Sidebar content
        ColumnLayout {
          anchors.fill: parent
          spacing: Style.marginS
          anchors.margins: sidebar.panelVeryTransparent ? Style.marginM : 0

          // Sidebar toggle button
          Item {
            id: toggleContainer
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(toggleRow.implicitHeight + Style.marginS * 2)

            Rectangle {
              id: sidebarToggle
              width: Math.round(toggleRow.implicitWidth + Style.marginS * 2)
              height: parent.height
              anchors.left: parent.left
              radius: Style.radiusS
              color: toggleMouseArea.containsMouse ? Color.mHover : Color.transparent

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

              RowLayout {
                id: toggleRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.marginS
                spacing: 0

                NIcon {
                  icon: root.sidebarExpanded ? "layout-sidebar-right-expand" : "layout-sidebar-left-expand"
                  color: toggleMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                  pointSize: Style.fontSizeXL
                }
              }

              MouseArea {
                id: toggleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  TooltipService.show(sidebarToggle, root.sidebarExpanded ? I18n.tr("tooltips.collapse") : I18n.tr("tooltips.expand"));
                }
                onExited: {
                  TooltipService.hide();
                }
                onClicked: {
                  TooltipService.hide();
                  root.sidebarExpanded = !root.sidebarExpanded;
                }
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: Style.marginXL

            NListView {
              id: sidebarList
              anchors.fill: parent
              model: root.tabsModel
              spacing: Style.marginXS
              currentIndex: root.currentTabIndex
              verticalPolicy: ScrollBar.AsNeeded

              delegate: Rectangle {
                id: tabItem
                width: sidebarList.width - (sidebarList.verticalScrollBarActive ? Style.marginM : 0)
                height: tabEntryRow.implicitHeight + Style.marginS * 2
                radius: Style.radiusS
                color: selected ? Color.mPrimary : (tabItem.hovering ? Color.mHover : Color.transparent)
                readonly property bool selected: index === root.currentTabIndex
                property bool hovering: false
                property color tabTextColor: selected ? Color.mOnPrimary : (tabItem.hovering ? Color.mOnHover : Color.mOnSurface)

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.InOutQuad
                  }
                }

                Behavior on tabTextColor {
                  ColorAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.InOutQuad
                  }
                }

                RowLayout {
                  id: tabEntryRow
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginS
                  anchors.rightMargin: Style.marginS
                  spacing: Style.marginM

                  NIcon {
                    icon: modelData.icon
                    color: tabTextColor
                    pointSize: Style.fontSizeXL
                    Layout.alignment: Qt.AlignVCenter
                  }

                  NText {
                    text: I18n.tr(modelData.label)
                    color: tabTextColor
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.sidebarExpanded
                    opacity: root.sidebarExpanded ? 1.0 : 0.0

                    Behavior on opacity {
                      NumberAnimation {
                        duration: Style.animationFast
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    tabItem.hovering = true;
                    // Show tooltip when sidebar is collapsed
                    if (!root.sidebarExpanded) {
                      TooltipService.show(tabItem, I18n.tr(modelData.label));
                    }
                  }
                  onExited: {
                    tabItem.hovering = false;
                    // Hide tooltip when sidebar is collapsed
                    if (!root.sidebarExpanded) {
                      TooltipService.hide();
                    }
                  }
                  onCanceled: {
                    tabItem.hovering = false;
                    if (!root.sidebarExpanded) {
                      TooltipService.hide();
                    }
                  }
                  onClicked: {
                    root.currentTabIndex = index;
                    // Hide tooltip on click
                    if (!root.sidebarExpanded) {
                      TooltipService.hide();
                    }
                  }
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
          }
        }

        // Overlay gradient for sidebar scrolling
        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.borderS
          radius: Style.radiusM
          color: Color.transparent
          visible: sidebarList.verticalScrollBarActive
          opacity: (sidebarList.contentY + sidebarList.height >= sidebarList.contentHeight - 10) ? 0 : 1

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutQuad
            }
          }

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

            NIcon {
              icon: root.tabsModel[currentTabIndex]?.icon ?? ""
              color: Color.mPrimary
              pointSize: Style.fontSizeXXL
            }

            NText {
              text: root.tabsModel[root.currentTabIndex]?.label ? I18n.tr(root.tabsModel[root.currentTabIndex].label) : ""
              pointSize: Style.fontSizeXL
              font.weight: Style.fontWeightBold
              color: Color.mPrimary
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("tooltips.close")
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.closeRequested()
            }
          }

          NDivider {
            Layout.fillWidth: true
          }

          // Tab content area
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: -Style.marginM
            Layout.rightMargin: -Style.marginL
            color: Color.transparent

            Repeater {
              model: root.tabsModel
              delegate: Loader {
                anchors.fill: parent
                active: index === root.currentTabIndex

                onStatusChanged: {
                  if (status === Loader.Ready && item) {
                    const scrollView = item.children[0];
                    if (scrollView && scrollView.toString().includes("ScrollView")) {
                      root.activeScrollView = scrollView;
                    }
                  }
                }

                sourceComponent: Flickable {
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

            // Overlay gradient for content scrolling
            Rectangle {
              anchors.fill: parent
              color: Color.transparent
              visible: root.activeScrollView && root.activeScrollView.ScrollBar.vertical && root.activeScrollView.ScrollBar.vertical.size < 1.0
              opacity: {
                if (!root.activeScrollView)
                  return 1;
                const scrollBar = root.activeScrollView.ScrollBar.vertical;
                return (scrollBar.position + scrollBar.size >= 0.99) ? 0 : 1;
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

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
