import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.Tabs
import qs.Modules.Panels.Settings.Tabs.About
import qs.Modules.Panels.Settings.Tabs.Audio
import qs.Modules.Panels.Settings.Tabs.Bar
import qs.Modules.Panels.Settings.Tabs.ColorScheme
import qs.Modules.Panels.Settings.Tabs.ControlCenter
import qs.Modules.Panels.Settings.Tabs.Display
import qs.Modules.Panels.Settings.Tabs.Dock
import qs.Modules.Panels.Settings.Tabs.Hooks
import qs.Modules.Panels.Settings.Tabs.Launcher
import qs.Modules.Panels.Settings.Tabs.LockScreen
import qs.Modules.Panels.Settings.Tabs.Notifications
import qs.Modules.Panels.Settings.Tabs.Osd
import qs.Modules.Panels.Settings.Tabs.Plugins
import qs.Modules.Panels.Settings.Tabs.Region
import qs.Modules.Panels.Settings.Tabs.SessionMenu
import qs.Modules.Panels.Settings.Tabs.SystemMonitor
import qs.Modules.Panels.Settings.Tabs.UserInterface
import qs.Modules.Panels.Settings.Tabs.Wallpaper
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // Screen reference for child components
  property var screen

  // Input: which tab to show initially
  property int requestedTab: 0

  // Exposed state for parent to access
  property int currentTabIndex: 0
  property var tabsModel: []
  property var activeScrollView: null
  property var activeTabContent: null
  property bool sidebarExpanded: true
  // Track if sidebar was collapsed before searching started
  property bool wasCollapsedBeforeSearch: false

  // Search state
  property string searchText: ""
  property var searchIndex: []
  property var searchResults: []
  property int searchSelectedIndex: 0
  property string highlightLabelKey: ""
  property bool navigatingFromSearch: false

  // Mouse hover suppression during keyboard navigation
  property bool ignoreMouseHover: false
  property real _lastMouseX: 0
  property real _lastMouseY: 0
  property bool _mouseInitialized: false

  readonly property bool panelVeryTransparent: Settings.data.ui.panelBackgroundOpacity <= 0.75

  onSearchResultsChanged: {
    searchSelectedIndex = 0;
    ignoreMouseHover = true;
    _mouseInitialized = false;
  }

  // Signal when close button is clicked
  signal closeRequested

  // Load search index
  FileView {
    id: searchIndexFile
    path: Quickshell.shellDir + "/Assets/settings-search-index.json"
    watchChanges: false
    printErrors: false

    onLoaded: {
      try {
        root.searchIndex = JSON.parse(text());
      } catch (e) {
        root.searchIndex = [];
      }
    }
  }

  // Search function
  onSearchTextChanged: {
    if (searchText.trim() === "") {
      searchResults = [];
      if (wasCollapsedBeforeSearch) {
        root.sidebarExpanded = false;
        wasCollapsedBeforeSearch = false;
      }
      return;
    }

    // Auto-expand sidebar when searching
    if (!root.sidebarExpanded) {
      if (root.activeFocus) {
        // If we are typing and the sidebar is collapsed and focused, we assume the user is typing to search
        wasCollapsedBeforeSearch = true;
      }
      root.sidebarExpanded = true;
    }

    if (searchIndex.length === 0)
      return;

    // Build searchable items with resolved translations
    let items = [];
    for (let j = 0; j < searchIndex.length; j++) {
      const entry = searchIndex[j];
      items.push({
                   "labelKey": entry.labelKey,
                   "descriptionKey": entry.descriptionKey,
                   "widget": entry.widget,
                   "tab": entry.tab,
                   "tabLabel": entry.tabLabel,
                   "subTab": entry.subTab,
                   "subTabLabel": entry.subTabLabel || null,
                   "label": I18n.tr(entry.labelKey),
                   "description": entry.descriptionKey ? I18n.tr(entry.descriptionKey) : "",
                   "subTabName": entry.subTabLabel ? I18n.tr(entry.subTabLabel) : ""
                 });
    }

    const results = FuzzySort.go(searchText.trim(), items, {
                                   "keys": ["label", "subTabName", "description"],
                                   "limit": 20,
                                   "scoreFn": function (r) {
                                     // r[0]=label, r[1]=subTabName, r[2]=description
                                     // Boost subTabName matches by 1.5x
                                     const labelScore = r[0].score;
                                     const subTabScore = r[1].score * 1.5;
                                     const descScore = r[2].score;
                                     return Math.max(labelScore, subTabScore, descScore);
                                   }
                                 });

    let extracted = [];
    for (let i = 0; i < results.length; i++) {
      extracted.push(results[i].obj);
    }
    searchResults = extracted;
  }

  // Navigate to a search result
  property int _pendingSubTab: -1

  function navigateToResult(entry) {
    if (entry.tab < 0 || entry.tab >= tabsModel.length)
      return;

    highlightLabelKey = entry.labelKey;
    _pendingSubTab = (entry.subTab !== null && entry.subTab !== undefined) ? entry.subTab : -1;

    const alreadyOnTab = (currentTabIndex === entry.tab);
    navigatingFromSearch = true;
    currentTabIndex = entry.tab;
    navigatingFromSearch = false;

    if (alreadyOnTab && activeTabContent) {
      if (_pendingSubTab >= 0) {
        navigatingFromSearch = true;
        setSubTabIndex(_pendingSubTab);
        navigatingFromSearch = false;
        _pendingSubTab = -1;
      }
      highlightScrollTimer.targetKey = highlightLabelKey;
      highlightScrollTimer.restart();
    }

    // Clear highlight after a delay
    highlightClearTimer.restart();
  }

  // Navigate to a tab and optionally a subtab (simpler than navigateToResult, no highlighting)
  function navigateToTab(tabId, subTabIndex) {
    // Find the tab index by tab ID
    let tabIndex = -1;
    for (let i = 0; i < tabsModel.length; i++) {
      if (tabsModel[i].id === tabId) {
        tabIndex = i;
        break;
      }
    }

    if (tabIndex < 0)
      return;

    const hasSubTab = subTabIndex !== null && subTabIndex !== undefined && subTabIndex >= 0;
    _pendingSubTab = hasSubTab ? subTabIndex : -1;

    // Check if we're already on this tab
    const alreadyOnTab = (currentTabIndex === tabIndex);

    currentTabIndex = tabIndex;

    if (alreadyOnTab && activeTabContent && hasSubTab) {
      // Tab is already loaded, apply subtab directly
      setSubTabIndex(subTabIndex);
      _pendingSubTab = -1;
    }
  }

  function searchSelectNext() {
    if (searchResults.length === 0)
      return;
    ignoreMouseHover = true;
    _mouseInitialized = false;
    searchSelectedIndex = Math.min(searchSelectedIndex + 1, searchResults.length - 1);
    searchResultsList.positionViewAtIndex(searchSelectedIndex, ListView.Contain);
  }

  function searchSelectPrevious() {
    if (searchResults.length === 0)
      return;
    ignoreMouseHover = true;
    _mouseInitialized = false;
    searchSelectedIndex = Math.max(searchSelectedIndex - 1, 0);
    searchResultsList.positionViewAtIndex(searchSelectedIndex, ListView.Contain);
  }

  function searchActivate() {
    if (searchSelectedIndex >= 0 && searchSelectedIndex < searchResults.length) {
      navigateToResult(searchResults[searchSelectedIndex]);
      searchInput.text = "";
    }
  }

  // Set sub-tab on the currently loaded tab content. Returns true if an NTabBar was found.
  function setSubTabIndex(subTabIndex) {
    if (activeTabContent) {
      return setSubTabRecursive(activeTabContent, subTabIndex);
    }
    return false;
  }

  function setSubTabRecursive(item, subTabIndex) {
    if (!item)
      return false;

    if (item.objectName === "NTabBar") {
      // Prepare the sibling NTabView so the index change doesn't animate
      if (item.parent) {
        for (let j = 0; j < item.parent.children.length; j++) {
          const sibling = item.parent.children[j];
          if (sibling.objectName === "NTabView" && sibling.setIndexWithoutAnimation) {
            sibling.setIndexWithoutAnimation(subTabIndex);
            break;
          }
        }
      }
      item.currentIndex = subTabIndex;
      return true;
    }

    const childCount = item.children ? item.children.length : 0;
    for (let i = 0; i < childCount; i++) {
      if (setSubTabRecursive(item.children[i], subTabIndex))
        return true;
    }
    return false;
  }

  onCurrentTabIndexChanged: {
    if (!navigatingFromSearch) {
      clearHighlightImmediately();
    }
  }

  property var currentSubTabBar: null

  onActiveTabContentChanged: {
    if (currentSubTabBar) {
      try {
        currentSubTabBar.currentIndexChanged.disconnect(onSubTabChanged);
      } catch (e) {}
      currentSubTabBar = null;
    }

    if (activeTabContent) {
      const tabBar = findNTabBar(activeTabContent);
      if (tabBar) {
        currentSubTabBar = tabBar;
        currentSubTabBar.currentIndexChanged.connect(onSubTabChanged);
      }
    }
  }

  function onSubTabChanged() {
    if (!navigatingFromSearch) {
      clearHighlightImmediately();
    }
  }

  function findNTabBar(item) {
    if (!item)
      return null;

    if (item.objectName === "NTabBar") {
      return item;
    }

    const childCount = item.children ? item.children.length : 0;
    for (let i = 0; i < childCount; i++) {
      const found = findNTabBar(item.children[i]);
      if (found)
        return found;
    }
    return null;
  }

  function clearHighlightImmediately() {
    highlightClearTimer.stop();
    highlightScrollTimer.stop();
    highlightAnimation.stop();
    highlightLabelKey = "";
    highlightOverlay.opacity = 0;
  }

  // Find and highlight a widget by its label key
  function findAndHighlightWidget(item, labelKey) {
    if (!item)
      return null;

    // Check if this item has a matching label
    if (item.hasOwnProperty("label") && item.label === I18n.tr(labelKey)) {
      return item;
    }

    // Recursively search children
    if (item.children) {
      for (let i = 0; i < item.children.length; i++) {
        const found = findAndHighlightWidget(item.children[i], labelKey);
        if (found)
          return found;
      }
    }
    return null;
  }

  Timer {
    id: highlightClearTimer
    interval: 3000
    onTriggered: root.highlightLabelKey = ""
  }

  Timer {
    id: highlightScrollTimer
    interval: 333
    property string targetKey: ""
    onTriggered: {
      if (root.activeTabContent && targetKey) {
        const widget = root.findAndHighlightWidget(root.activeTabContent, targetKey);
        if (widget && root.activeScrollView) {
          // Scroll widget into view using the Flickable directly
          const flickable = root.activeScrollView.contentItem;
          const mapped = widget.mapToItem(flickable.contentItem, 0, 0);
          const targetY = mapped.y - flickable.height / 3;
          flickable.contentY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));

          // Position highlight overlay after scroll layout has settled
          Qt.callLater(function () {
            const overlayPos = widget.mapToItem(tabContentArea, 0, 0);
            highlightOverlay.x = overlayPos.x - Style.marginM;
            highlightOverlay.y = overlayPos.y - Style.marginM;
            highlightOverlay.width = widget.width + Style.marginM * 2;
            highlightOverlay.height = widget.height + Style.marginM * 2;
            highlightAnimation.restart();
          });
        }
      }
      targetKey = "";
    }
  }

  // Save sidebar state when it changes
  onSidebarExpandedChanged: {
    ShellState.setSettingsSidebarExpanded(sidebarExpanded);
    if (!sidebarExpanded) {
      root.searchText = "";
      searchInput.text = "";
      root.forceActiveFocus();
    }
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
    id: regionTab
    RegionTab {}
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
            "label": "common.general",
            "icon": "settings-general",
            "source": generalTab
          },
          {
            "id": SettingsPanel.Tab.UserInterface,
            "label": "panels.user-interface.title",
            "icon": "settings-user-interface",
            "source": userInterfaceTab
          },
          {
            "id": SettingsPanel.Tab.ColorScheme,
            "label": "panels.color-scheme.title",
            "icon": "settings-color-scheme",
            "source": colorSchemeTab
          },
          {
            "id": SettingsPanel.Tab.Wallpaper,
            "label": "common.wallpaper",
            "icon": "settings-wallpaper",
            "source": wallpaperTab
          },
          {
            "id": SettingsPanel.Tab.Bar,
            "label": "panels.bar.title",
            "icon": "settings-bar",
            "source": barTab
          },
          {
            "id": SettingsPanel.Tab.Dock,
            "label": "panels.dock.title",
            "icon": "settings-dock",
            "source": dockTab
          },
          {
            "id": SettingsPanel.Tab.DesktopWidgets,
            "label": "panels.desktop-widgets.title",
            "icon": "clock",
            "source": desktopWidgetsTab
          },
          {
            "id": SettingsPanel.Tab.ControlCenter,
            "label": "panels.control-center.title",
            "icon": "settings-control-center",
            "source": controlCenterTab
          },
          {
            "id": SettingsPanel.Tab.Launcher,
            "label": "panels.launcher.title",
            "icon": "settings-launcher",
            "source": launcherTab
          },
          {
            "id": SettingsPanel.Tab.Notifications,
            "label": "common.notifications",
            "icon": "settings-notifications",
            "source": notificationsTab
          },
          {
            "id": SettingsPanel.Tab.OSD,
            "label": "panels.osd.title",
            "icon": "settings-osd",
            "source": osdTab
          },
          {
            "id": SettingsPanel.Tab.LockScreen,
            "label": "panels.lock-screen.title",
            "icon": "settings-lock-screen",
            "source": lockScreenTab
          },
          {
            "id": SettingsPanel.Tab.SessionMenu,
            "label": "session-menu.title",
            "icon": "settings-session-menu",
            "source": sessionMenuTab
          },
          {
            "id": SettingsPanel.Tab.Audio,
            "label": "panels.audio.title",
            "icon": "settings-audio",
            "source": audioTab
          },
          {
            "id": SettingsPanel.Tab.Display,
            "label": "panels.display.title",
            "icon": "settings-display",
            "source": displayTab
          },
          {
            "id": SettingsPanel.Tab.Network,
            "label": "common.network",
            "icon": "settings-network",
            "source": networkTab
          },
          {
            "id": SettingsPanel.Tab.Location,
            "label": "panels.region.title",
            "icon": "settings-location",
            "source": regionTab
          },
          {
            "id": SettingsPanel.Tab.SystemMonitor,
            "label": "system-monitor.title",
            "icon": "settings-system-monitor",
            "source": systemMonitorTab
          },
          {
            "id": SettingsPanel.Tab.Plugins,
            "label": "panels.plugins.title",
            "icon": "plugin",
            "source": pluginsTab
          },
          {
            "id": SettingsPanel.Tab.Hooks,
            "label": "panels.hooks.title",
            "icon": "settings-hooks",
            "source": hooksTab
          },
          {
            "id": SettingsPanel.Tab.About,
            "label": "panels.about.title",
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
    // Skip auto-focus on Nvidia GPUs - cursor blink causes UI choppiness
    const isNvidia = SystemStatService.gpuType === "nvidia";
    if (sidebarExpanded && !isNvidia) {
      Qt.callLater(() => {
                     if (searchInput.inputItem)
                     searchInput.inputItem.forceActiveFocus();
                   });
    } else {
      // Ensure root has focus so it can catch typing
      Qt.callLater(() => root.forceActiveFocus());
    }
  }

  // Handle typing when sidebar is collapsed
  focus: true
  Keys.onPressed: event => {
                    if (!sidebarExpanded && event.text.length > 0 && event.text.trim() !== "") {
                      // Only capture if it looks like visible text
                      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                      return;

                      // Explicitly ignore backspace and similar keys that might have text but shouldn't trigger search
                      if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete || event.key === Qt.Key_Escape)
                      return;

                      wasCollapsedBeforeSearch = true;
                      sidebarExpanded = true;
                      searchInput.text = event.text;
                      Qt.callLater(() => {
                                     if (searchInput.inputItem) {
                                       searchInput.inputItem.forceActiveFocus();
                                       // Cursor moves to end automatically usually, but let's be safe
                                       searchInput.inputItem.cursorPosition = 1;
                                     }
                                   });
                      event.accepted = true;
                    }
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
      NBox {
        id: sidebar

        clip: true
        Layout.preferredWidth: Math.round(root.sidebarExpanded ? 200 * Style.uiScaleRatio : sidebarToggle.width + (root.panelVeryTransparent ? Style.marginXL : 0) + (sidebarList.verticalScrollBarActive ? Style.marginM : 0))
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop

        radius: root.panelVeryTransparent ? Style.radiusM : 0
        color: root.panelVeryTransparent ? Color.mSurfaceVariant : "transparent"
        border.color: root.panelVeryTransparent ? Style.boxBorderColor : "transparent"

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
          anchors.margins: root.panelVeryTransparent ? Style.marginM : 0

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
              color: toggleMouseArea.containsMouse ? Color.mHover : "transparent"

              Behavior on color {
                enabled: !Color.isTransitioning
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

          // Search container wrapper to prevent layout jumps
          Item {
            id: searchContainerWrapper
            Layout.fillWidth: true
            Layout.preferredHeight: searchInput.implicitHeight > 0 ? searchInput.implicitHeight : (Style.fontSizeXL + Style.marginM * 2)

            // Search input
            NTextInput {
              id: searchInput
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: I18n.tr("common.search")
              inputIconName: "search"
              visible: opacity > 0
              opacity: root.sidebarExpanded ? 1.0 : 0.0

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

              onTextChanged: root.searchText = text
              onEditingFinished: {
                if (root.searchText.trim() !== "")
                  root.searchActivate();
              }
            }

            // Search button for collapsed sidebar
            Item {
              id: searchCollapsedContainer
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Math.round(searchCollapsedRow.implicitHeight + Style.marginS * 2)
              visible: opacity > 0
              opacity: !root.sidebarExpanded ? 1.0 : 0.0

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

              Rectangle {
                id: searchCollapsedButton
                width: Math.round(searchCollapsedRow.implicitWidth + Style.marginS * 2)
                height: parent.height
                anchors.left: parent.left
                radius: Style.radiusS
                color: searchCollapsedMouseArea.containsMouse ? Color.mHover : "transparent"

                Behavior on color {
                  enabled: !Color.isTransitioning
                  ColorAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.InOutQuad
                  }
                }

                RowLayout {
                  id: searchCollapsedRow
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.marginS
                  spacing: 0

                  NIcon {
                    icon: "search"
                    color: searchCollapsedMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                    pointSize: Style.fontSizeXL
                  }
                }

                MouseArea {
                  id: searchCollapsedMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.sidebarExpanded = true;
                    root.wasCollapsedBeforeSearch = false; // Expanding manually resets this
                    Qt.callLater(() => searchInput.inputItem.forceActiveFocus());
                  }
                  onEntered: {
                    TooltipService.show(searchCollapsedButton, I18n.tr("common.search"));
                  }
                  onExited: {
                    TooltipService.hide();
                  }
                }
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: Style.marginXL

            // Search results list
            NListView {
              id: searchResultsList
              anchors.fill: parent
              model: root.searchResults
              spacing: Style.marginXS
              visible: root.searchText.trim() !== ""
              verticalPolicy: ScrollBar.AsNeeded
              gradientColor: "transparent"
              reserveScrollbarSpace: false

              HoverHandler {
                onPointChanged: {
                  if (!root._mouseInitialized) {
                    root._lastMouseX = point.position.x;
                    root._lastMouseY = point.position.y;
                    root._mouseInitialized = true;
                    return;
                  }

                  const deltaX = Math.abs(point.position.x - root._lastMouseX);
                  const deltaY = Math.abs(point.position.y - root._lastMouseY);
                  if (deltaX + deltaY >= 5) {
                    root.ignoreMouseHover = false;
                    root._lastMouseX = point.position.x;
                    root._lastMouseY = point.position.y;
                  }
                }
              }

              delegate: Rectangle {
                id: resultItem
                width: searchResultsList.width - (searchResultsList.verticalScrollBarActive ? Style.marginM : 0)
                height: resultColumn.implicitHeight + Style.marginS * 2
                radius: Style.iRadiusS
                readonly property bool selected: index === root.searchSelectedIndex
                readonly property bool effectiveHover: !root.ignoreMouseHover && resultMouseArea.containsMouse
                color: (effectiveHover || selected) ? Color.mHover : "transparent"

                Behavior on color {
                  enabled: !Color.isTransitioning
                  ColorAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.InOutQuad
                  }
                }

                ColumnLayout {
                  id: resultColumn
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginS
                  anchors.rightMargin: Style.marginS
                  anchors.topMargin: Style.marginXS
                  anchors.bottomMargin: Style.marginXS
                  spacing: 0

                  NText {
                    text: I18n.tr(modelData.labelKey)
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: (resultItem.effectiveHover || resultItem.selected) ? Color.mOnHover : Color.mOnSurface
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  NText {
                    text: {
                      let t = I18n.tr(modelData.tabLabel);
                      if (modelData.subTabLabel)
                        t += " › " + I18n.tr(modelData.subTabLabel);
                      return t;
                    }
                    pointSize: Style.fontSizeXS
                    color: (resultItem.effectiveHover || resultItem.selected) ? Color.mOnHover : Color.mOnSurfaceVariant
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                MouseArea {
                  id: resultMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    if (!root.ignoreMouseHover)
                      root.searchSelectedIndex = index;
                  }
                  onClicked: {
                    root.searchSelectedIndex = index;
                    root.navigateToResult(modelData);
                    searchInput.text = "";
                  }
                }
              }
            }

            // Tab list
            NListView {
              id: sidebarList
              visible: root.searchText.trim() === ""
              anchors.fill: parent
              model: root.tabsModel
              spacing: Style.marginXS
              currentIndex: root.currentTabIndex
              horizontalPolicy: ScrollBar.AlwaysOff
              verticalPolicy: ScrollBar.AlwaysOff
              gradientColor: "transparent"
              reserveScrollbarSpace: false

              delegate: Rectangle {
                id: tabItem
                width: sidebarList.width
                height: tabEntryRow.implicitHeight + Style.marginS * 2
                radius: Style.iRadiusS
                color: selected ? Color.mPrimary : (tabItem.hovering ? Color.mHover : "transparent")
                readonly property bool selected: index === root.currentTabIndex
                property bool hovering: false
                property color tabTextColor: selected ? Color.mOnPrimary : (tabItem.hovering ? Color.mOnHover : Color.mOnSurface)

                Behavior on color {
                  enabled: !Color.isTransitioning
                  ColorAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.InOutQuad
                  }
                }

                Behavior on tabTextColor {
                  enabled: !Color.isTransitioning
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
      }

      // Content pane
      NBox {
        id: contentPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop
        radius: Style.radiusM
        color: Color.mSurfaceVariant

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
              tooltipText: I18n.tr("common.close")
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.closeRequested()
            }
          }

          // Tab content area
          Rectangle {
            id: tabContentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: -Style.marginM
            Layout.rightMargin: -Style.marginL
            color: "transparent"

            Repeater {
              id: contentRepeater
              model: root.tabsModel
              delegate: Loader {
                anchors.fill: parent
                active: index === root.currentTabIndex
                opacity: 0

                NumberAnimation on opacity {
                  id: fadeInAnim
                  from: 0
                  to: 1
                  duration: Style.animationSlowest
                  easing.type: Easing.OutCubic
                  running: false
                }

                onStatusChanged: {
                  if (status === Loader.Ready && item) {
                    fadeInAnim.start();
                    const scrollView = item.children[0];
                    if (scrollView && scrollView.toString().includes("ScrollView")) {
                      root.activeScrollView = scrollView;
                    }
                  }
                }

                sourceComponent: NScrollView {
                  id: scrollView
                  anchors.fill: parent
                  horizontalPolicy: ScrollBar.AlwaysOff
                  verticalPolicy: ScrollBar.AsNeeded
                  leftPadding: Style.marginL
                  topPadding: Style.marginL
                  bottomPadding: Style.marginL
                  userRightPadding: Style.marginL
                  reserveScrollbarSpace: false

                  Component.onCompleted: {
                    root.activeScrollView = scrollView;
                  }

                  Loader {
                    active: true
                    sourceComponent: root.tabsModel[index]?.source
                    width: scrollView.availableWidth
                    onLoaded: {
                      if (item && item.hasOwnProperty("screen")) {
                        item.screen = root.screen;
                      }
                      root.activeTabContent = item;
                      if (root._pendingSubTab >= 0) {
                        root.navigatingFromSearch = true;
                        if (root.setSubTabIndex(root._pendingSubTab))
                          root._pendingSubTab = -1;
                        root.navigatingFromSearch = false;
                      }
                      if (root.highlightLabelKey) {
                        highlightScrollTimer.targetKey = root.highlightLabelKey;
                        highlightScrollTimer.restart();
                      }
                    }
                  }
                }
              }
            }

            // Highlight overlay for search results
            Rectangle {
              id: highlightOverlay
              visible: opacity > 0
              opacity: 0
              color: Qt.alpha(Color.mSecondary, 0.2)
              border.color: Qt.alpha(Color.mSecondary, 0.6)
              border.width: Style.borderM
              radius: Style.radiusS
              z: 100

              SequentialAnimation {
                id: highlightAnimation

                NumberAnimation {
                  target: highlightOverlay
                  property: "opacity"
                  to: 1.0
                  duration: Style.animationSlow
                  easing.type: Easing.OutQuad
                }

                PauseAnimation {
                  duration: 2000
                }

                NumberAnimation {
                  target: highlightOverlay
                  property: "opacity"
                  to: 0
                  duration: Style.animationSlowest
                  easing.type: Easing.InQuad
                }
              }
            }
          }
        }
      }
    }
  }
}
