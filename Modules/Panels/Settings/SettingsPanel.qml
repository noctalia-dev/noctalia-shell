import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(840 * Style.uiScaleRatio)
  preferredHeight: Math.round(910 * Style.uiScaleRatio)

  // Settings panel mode: "centered", "attached", "window"
  readonly property string settingsPanelMode: Settings.data.ui.settingsPanelMode
  readonly property bool isWindowMode: settingsPanelMode === "window"
  readonly property bool attachToBar: settingsPanelMode === "attached"

  readonly property string barDensity: Settings.data.bar.density
  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool barFloating: Settings.data.bar.floating
  readonly property bool barIsland: Settings.data.bar.island || false
  readonly property real barMarginH: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginHorizontal) : 0
  readonly property real barMarginV: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginVertical) : 0

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

  onBarDensityChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarFloatingChanged: {
    if (isPanelOpen) {
      Qt.callLater(root.setPosition);
    }
  }

  onBarIslandChanged: {
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
    DesktopWidgets,
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
    SessionMenu,
    SystemMonitor,
    UserInterface,
    Wallpaper
  }

  property int requestedTab: SettingsPanel.Tab.General
  property int requestedSubTab: -1
  property var requestedEntry: null

  // Content state - these are synced with SettingsContent when panel opens
  property int currentTabIndex: 0
  property var tabsModel: []
  property var activeScrollView: null

  // Internal reference to the content (set when panel content loads)
  property var _settingsContent: null

  // Override toggle to handle window mode
  function toggle(buttonItem, buttonName) {
    if (isWindowMode) {
      SettingsPanelService.toggleWindow(requestedTab);
      return;
    }
    // Call parent toggle
    if (isPanelOpen) {
      close();
    } else {
      open(buttonItem, buttonName);
    }
  }

  // Override open to handle window mode
  function open(buttonItem, buttonName) {
    if (isWindowMode) {
      SettingsPanelService.openWindow(requestedTab);
      return;
    }

    // Panel mode: replicate SmartPanel.open() logic
    if (!buttonItem && buttonName) {
      buttonItem = BarService.lookupWidget(buttonName, screen.name);
    }

    if (buttonItem) {
      root.buttonItem = buttonItem;
      var buttonPos = buttonItem.mapToItem(null, 0, 0);
      root.buttonPosition = Qt.point(buttonPos.x, buttonPos.y);
      root.buttonWidth = buttonItem.width;
      root.buttonHeight = buttonItem.height;
      root.useButtonPosition = true;
    } else {
      root.buttonItem = null;
      root.useButtonPosition = false;
    }

    isPanelOpen = true;
    PanelService.willOpenPanel(root);
  }

  // Open to a specific tab and optionally a subtab
  function openToTab(tab, subTab, buttonItem, buttonName) {
    requestedTab = tab !== undefined ? tab : SettingsPanel.Tab.General;
    requestedSubTab = subTab !== undefined ? subTab : -1;
    open(buttonItem, buttonName);
  }

  // When the panel opens, initialize content
  onOpened: {
    if (_settingsContent) {
      if (requestedEntry) {
        _settingsContent.requestedTab = requestedEntry.tab;
        _settingsContent.initialize();
        const entry = requestedEntry;
        requestedEntry = null;
        Qt.callLater(() => _settingsContent.navigateToResult(entry));
      } else {
        _settingsContent.requestedTab = requestedTab;
        _settingsContent.initialize();
        if (requestedSubTab >= 0) {
          const subTab = requestedSubTab;
          requestedSubTab = -1;
          Qt.callLater(() => _settingsContent.navigateToTab(requestedTab, subTab));
        }
      }
    }
  }

  // Scroll functions - delegate to content
  function scrollDown() {
    if (_settingsContent)
      _settingsContent.scrollDown();
  }

  function scrollUp() {
    if (_settingsContent)
      _settingsContent.scrollUp();
  }

  function scrollPageDown() {
    if (_settingsContent)
      _settingsContent.scrollPageDown();
  }

  function scrollPageUp() {
    if (_settingsContent)
      _settingsContent.scrollPageUp();
  }

  // Navigation functions - delegate to content
  function selectNextTab() {
    if (_settingsContent)
      _settingsContent.selectNextTab();
  }

  function selectPreviousTab() {
    if (_settingsContent)
      _settingsContent.selectPreviousTab();
  }

  // Override keyboard handlers from SmartPanel
  function onTabPressed() {
    selectNextTab();
  }

  function onBackTabPressed() {
    selectPreviousTab();
  }

  function onUpPressed() {
    if (_settingsContent && _settingsContent.searchText.trim() !== "") {
      _settingsContent.searchSelectPrevious();
    } else {
      scrollUp();
    }
  }

  function onDownPressed() {
    if (_settingsContent && _settingsContent.searchText.trim() !== "") {
      _settingsContent.searchSelectNext();
    } else {
      scrollDown();
    }
  }

  function onPageUpPressed() {
    scrollPageUp();
  }

  function onPageDownPressed() {
    scrollPageDown();
  }

  function onCtrlJPressed() {
    if (_settingsContent && _settingsContent.searchText.trim() !== "") {
      _settingsContent.searchSelectNext();
    } else {
      scrollDown();
    }
  }

  function onCtrlKPressed() {
    if (_settingsContent && _settingsContent.searchText.trim() !== "") {
      _settingsContent.searchSelectPrevious();
    } else {
      scrollUp();
    }
  }

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"

    SettingsContent {
      id: settingsContent
      anchors.fill: parent
      screen: root.screen
      onCloseRequested: root.close()
      Component.onCompleted: {
        root._settingsContent = settingsContent;
        root.tabsModel = Qt.binding(function () {
          return settingsContent.tabsModel;
        });
        root.currentTabIndex = Qt.binding(function () {
          return settingsContent.currentTabIndex;
        });
        root.activeScrollView = Qt.binding(function () {
          return settingsContent.activeScrollView;
        });
      }
    }
  }
}
