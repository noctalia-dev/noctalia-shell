import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "Helpers/LauncherNavigation.js" as LauncherNav

import "Providers"
import qs.Commons
import qs.Services.Keyboard
import qs.Services.UI
import qs.Widgets

// Core launcher logic and UI - shared between SmartPanel (Launcher.qml) and overlay (LauncherOverlayWindow.qml)
Rectangle {
  id: root
  color: "transparent"

  // External interface - set by parent
  property var screen: null
  property bool isOpen: false
  signal requestClose
  signal requestCloseImmediately

  function closeImmediately() {
    requestCloseImmediately();
  }

  // Expose for preview panel positioning
  readonly property var resultsView: resultsViewLoader.item

  // State
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var providers: []
  property var activeProvider: null
  property bool resultsReady: false
  property var pluginProviderInstances: ({})
  property bool ignoreMouseHover: true // Transient flag, should always be true on init

  // Global mouse tracking for movement detection across delegates
  property real globalLastMouseX: 0
  property real globalLastMouseY: 0
  property bool globalMouseInitialized: false
  property bool mouseTrackingReady: false // Delay tracking until panel is settled

  readonly property bool animationsDisabled: Settings.data.general.animationDisabled

  Timer {
    id: mouseTrackingDelayTimer
    interval: root.animationsDisabled ? 0 : (Style.animationNormal + 50) // Wait for panel animation to complete + safety margin
    repeat: false
    onTriggered: {
      root.mouseTrackingReady = true;
      root.globalMouseInitialized = false; // Reset so we get fresh initial position
    }
  }

  readonly property var defaultProvider: appsProvider
  readonly property var currentProvider: activeProvider || defaultProvider

  readonly property string launcherDensity: (currentProvider && currentProvider.ignoreDensity === false) ? (Settings.data.appLauncher.density || "default") : "comfortable"
  readonly property int effectiveIconSize: launcherDensity === "comfortable" ? 48 : (launcherDensity === "default" ? 36 : 24)
  readonly property int badgeSize: Math.round(effectiveIconSize * Style.uiScaleRatio)
  readonly property int entryHeight: Math.round(badgeSize + (launcherDensity === "compact" ? (Style.marginL + Style.marginXXS) : (Style.marginXL + Style.marginS)))

  readonly property bool providerShowsCategories: currentProvider.showsCategories === true

  readonly property var providerCategories: {
    if (currentProvider.availableCategories && currentProvider.availableCategories.length > 0) {
      return currentProvider.availableCategories;
    }
    return currentProvider.categories || [];
  }

  readonly property bool showProviderCategories: {
    if (!providerShowsCategories || providerCategories.length === 0)
      return false;
    if (currentProvider === defaultProvider)
      return Settings.data.appLauncher.showCategories;
    return true;
  }

  readonly property bool providerHasDisplayString: results.length > 0 && !!results[0].displayString

  readonly property string providerSupportedLayouts: {
    if (activeProvider && activeProvider.supportedLayouts)
      return activeProvider.supportedLayouts;
    if (results.length > 0 && results[0].provider && results[0].provider.supportedLayouts)
      return results[0].provider.supportedLayouts;
    if (defaultProvider && defaultProvider.supportedLayouts)
      return defaultProvider.supportedLayouts;
    return "both";
  }

  readonly property bool showLayoutToggle: !providerHasDisplayString && providerSupportedLayouts === "both"

  readonly property string layoutMode: {
    if (searchText === ">")
      return "list";
    if (providerSupportedLayouts === "grid")
      return "grid";
    if (providerSupportedLayouts === "list")
      return "list";
    if (providerSupportedLayouts === "single")
      return "single";
    if (providerHasDisplayString)
      return "grid";
    return Settings.data.appLauncher.viewMode;
  }

  readonly property bool isGridView: layoutMode === "grid"
  readonly property bool isSingleView: layoutMode === "single"
  readonly property bool isCompactDensity: launcherDensity === "compact"

  readonly property int targetGridColumns: {
    let base = 5;
    if (launcherDensity === "comfortable")
      base = 4;
    else if (launcherDensity === "compact")
      base = 6;

    if (!activeProvider || activeProvider === defaultProvider)
      return base;

    if (activeProvider.preferredGridColumns) {
      let multiplier = base / 5.0;
      return Math.max(1, Math.round(activeProvider.preferredGridColumns * multiplier));
    }

    return base;
  }
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int gridContentWidth: listPanelWidth - (2 * Style.marginXS)
  readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

  readonly property int gridColumns: targetGridColumns

  // Check if current provider allows wrap navigation (default true)
  readonly property bool allowWrapNavigation: {
    var provider = activeProvider || currentProvider;
    return provider && provider.wrapNavigation !== undefined ? provider.wrapNavigation : true;
  }

  // Listen for plugin provider registry changes
  Connections {
    target: LauncherProviderRegistry
    function onPluginProviderRegistryUpdated() {
      root.syncPluginProviders();
    }
  }

  // Lifecycle
  onIsOpenChanged: {
    if (isOpen) {
      onOpened();
    } else {
      onClosed();
    }
  }

  onSearchTextChanged: {
    if (isOpen) {
      updateResults();
    }
  }

  function onOpened() {
    ignoreMouseHover = true;
    globalMouseInitialized = false;
    mouseTrackingReady = false;
    mouseTrackingDelayTimer.restart();

    // Show launcher immediately, results will populate asynchronously
    resultsReady = true;
    focusSearchInput();

    Qt.callLater(() => {
                   syncPluginProviders();
                   for (let provider of providers) {
                     if (provider.onOpened)
                     provider.onOpened();
                   }
                   updateResults();
                 });
  }

  function onClosed() {
    searchText = "";
    ignoreMouseHover = true;
    for (let provider of providers) {
      if (provider.onClosed)
        provider.onClosed();
    }
  }

  function close() {
    requestClose();
  }

  // Public API
  function setSearchText(text) {
    searchText = text;
  }

  function focusSearchInput() {
    if (searchInput.inputItem) {
      searchInput.inputItem.forceActiveFocus();
    }
  }

  // Provider registration
  function registerProvider(provider) {
    providers.push(provider);
    provider.launcher = root;
    if (provider.init)
      provider.init();
  }

  function syncPluginProviders() {
    var registeredIds = LauncherProviderRegistry.getPluginProviders();
    var changed = false;

    // Remove providers that are no longer registered
    for (var existingId in pluginProviderInstances) {
      if (registeredIds.indexOf(existingId) === -1) {
        var idx = providers.indexOf(pluginProviderInstances[existingId]);
        if (idx >= 0)
          providers.splice(idx, 1);
        delete pluginProviderInstances[existingId];
        Logger.d("Launcher", "Removed plugin provider:", existingId);
        changed = true;
      }
    }

    // Adopt persistent instances from the registry
    for (var i = 0; i < registeredIds.length; i++) {
      var providerId = registeredIds[i];
      if (!pluginProviderInstances[providerId]) {
        var instance = LauncherProviderRegistry.getProviderInstance(providerId);
        if (instance) {
          pluginProviderInstances[providerId] = instance;
          providers.push(instance);
          instance.launcher = root;
          Logger.d("Launcher", "Adopted plugin provider:", providerId);
          changed = true;
        }
      }
    }

    // Update results only if providers changed
    if (changed && root.isOpen) {
      updateResults();
    }
  }

  // Search handling
  function updateResults() {
    results = [];
    var newActiveProvider = null;

    // Check for command mode
    if (searchText.startsWith(">")) {
      for (let provider of providers) {
        if (provider.handleCommand && provider.handleCommand(searchText)) {
          newActiveProvider = provider;
          results = provider.getResults(searchText);
          break;
        }
      }

      // Show available commands if just ">" or filter commands if partial match
      if (!newActiveProvider) {
        let allCommands = [];
        for (let provider of providers) {
          if (provider.commands)
            allCommands = allCommands.concat(provider.commands());
        }
        if (searchText === ">") {
          results = allCommands;
        } else if (searchText.length > 1) {
          const query = searchText.substring(1);
          if (typeof FuzzySort !== 'undefined') {
            const fuzzyResults = FuzzySort.go(query, allCommands, {
                                                "keys": ["name"],
                                                "limit": 50
                                              });
            results = fuzzyResults.map(result => result.obj);
          } else {
            const queryLower = query.toLowerCase();
            results = allCommands.filter(cmd => (cmd.name || "").toLowerCase().includes(queryLower));
          }
        }
      }
    } else {
      // Regular search - let providers contribute results
      let allResults = [];
      for (let provider of providers) {
        if (provider.handleSearch) {
          const providerResults = provider.getResults(searchText);
          allResults = allResults.concat(providerResults);
        }
      }

      // Sort by _score (higher = better match), items without _score go first
      if (searchText.trim() !== "") {
        const boostByUsage = Settings.data.appLauncher.sortByMostUsed;

        allResults.sort((a, b) => {
                          let sa = a._score !== undefined ? a._score : 0;
                          let sb = b._score !== undefined ? b._score : 0;

                          // Boost scores for frequently used items from tracked providers
                          // _score is normalized 0–1, so boost is scaled to nudge, not overwhelm
                          if (boostByUsage) {
                            if (a.provider && a.provider.trackUsage && a.usageKey) {
                              sa += 0.1 * Math.log2(1 + ShellState.getLauncherUsageCount(a.usageKey));
                            }
                            if (b.provider && b.provider.trackUsage && b.usageKey) {
                              sb += 0.1 * Math.log2(1 + ShellState.getLauncherUsageCount(b.usageKey));
                            }
                          }

                          return sb - sa;
                        });
      }
      results = allResults;
    }

    // Update activeProvider only after computing new state to avoid UI flicker
    activeProvider = newActiveProvider;
    selectedIndex = 0;
  }

  // Navigation functions (delegated to LauncherNavigation.js)
  function selectNext() {
    selectedIndex = LauncherNav.selectNext(selectedIndex, results.length);
  }
  function selectPrevious() {
    selectedIndex = LauncherNav.selectPrevious(selectedIndex, results.length);
  }
  function selectNextWrapped() {
    selectedIndex = LauncherNav.selectNextWrapped(selectedIndex, results.length, allowWrapNavigation);
  }
  function selectPreviousWrapped() {
    selectedIndex = LauncherNav.selectPreviousWrapped(selectedIndex, results.length, allowWrapNavigation);
  }
  function selectFirst() {
    selectedIndex = LauncherNav.selectFirst();
  }
  function selectLast() {
    selectedIndex = LauncherNav.selectLast(results.length);
  }
  function selectNextPage() {
    selectedIndex = LauncherNav.selectNextPage(selectedIndex, results.length, entryHeight);
  }
  function selectPreviousPage() {
    selectedIndex = LauncherNav.selectPreviousPage(selectedIndex, results.length, entryHeight);
  }
  function selectPreviousRow() {
    selectedIndex = LauncherNav.selectPreviousRow(selectedIndex, results.length, gridColumns);
  }
  function selectNextRow() {
    selectedIndex = LauncherNav.selectNextRow(selectedIndex, results.length, gridColumns);
  }
  function selectPreviousColumn() {
    selectedIndex = LauncherNav.selectPreviousColumn(selectedIndex, results.length, gridColumns);
  }
  function selectNextColumn() {
    selectedIndex = LauncherNav.selectNextColumn(selectedIndex, results.length, gridColumns);
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex];
      const provider = item.provider || currentProvider;

      // Track usage for providers that opt in (cross-provider "most used" tracking)
      if (Settings.data.appLauncher.sortByMostUsed && provider && provider.trackUsage && item.usageKey) {
        ShellState.recordLauncherUsage(item.usageKey);
      }

      // Check if auto-paste is enabled and provider/item supports it
      if (Settings.data.appLauncher.autoPasteClipboard && provider && provider.supportsAutoPaste && item.autoPasteText) {
        if (item.onAutoPaste)
          item.onAutoPaste();
        closeImmediately();
        Qt.callLater(() => {
                       ClipboardService.pasteText(item.autoPasteText);
                     });
        return;
      }

      if (item.onActivate)
        item.onActivate();
    }
  }

  function checkKey(event, settingName) {
    return Keybinds.checkKey(event, settingName, Settings);
  }

  // Keyboard handler
  function handleKeyPress(event) {
    if (checkKey(event, 'escape')) {
      close();
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'enter')) {
      activate();
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'up')) {
      if (!isSingleView) {
        isGridView ? selectPreviousRow() : selectPreviousWrapped();
      }
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'down')) {
      if (!isSingleView) {
        isGridView ? selectNextRow() : selectNextWrapped();
      }
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'left')) {
      if (isGridView) {
        selectPreviousColumn();
        event.accepted = true;
        return;
      }
    }

    if (checkKey(event, 'right')) {
      if (isGridView) {
        selectNextColumn();
        event.accepted = true;
        return;
      }
    }

    // Static bindings
    switch (event.key) {
    case Qt.Key_Tab:
      if (showProviderCategories) {
        var cats = providerCategories;
        var idx = cats.indexOf(currentProvider.selectedCategory);
        var nextIdx = (idx + 1) % cats.length;
        currentProvider.selectCategory(cats[nextIdx]);
        categoryTabs.currentIndex = nextIdx;
      } else {
        selectNextWrapped();
      }
      event.accepted = true;
      break;
    case Qt.Key_Backtab:
      if (showProviderCategories) {
        var cats2 = providerCategories;
        var idx2 = cats2.indexOf(currentProvider.selectedCategory);
        var prevIdx = ((idx2 - 1) % cats2.length + cats2.length) % cats2.length;
        currentProvider.selectCategory(cats2[prevIdx]);
        categoryTabs.currentIndex = prevIdx;
      } else {
        selectPreviousWrapped();
      }
      event.accepted = true;
      break;
    case Qt.Key_Home:
      selectFirst();
      event.accepted = true;
      break;
    case Qt.Key_End:
      selectLast();
      event.accepted = true;
      break;
    case Qt.Key_PageUp:
      selectPreviousPage();
      event.accepted = true;
      break;
    case Qt.Key_PageDown:
      selectNextPage();
      event.accepted = true;
      break;
    case Qt.Key_Delete:
      if (selectedIndex >= 0 && results && results[selectedIndex]) {
        var item = results[selectedIndex];
        var provider = item.provider || currentProvider;
        if (provider && provider.canDeleteItem && provider.canDeleteItem(item))
          provider.deleteItem(item);
      }
      event.accepted = true;
      break;
    }
  }

  // -----------------------
  // Provider components
  // -----------------------
  ApplicationsProvider {
    id: appsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: ApplicationsProvider");
    }
  }

  ClipboardProvider {
    id: clipProvider
    Component.onCompleted: {
      if (Settings.data.appLauncher.enableClipboardHistory) {
        registerProvider(this);
        Logger.d("Launcher", "Registered: ClipboardProvider");
      }
    }
  }

  CommandProvider {
    id: cmdProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: CommandProvider");
    }
  }

  EmojiProvider {
    id: emojiProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: EmojiProvider");
    }
  }

  CalculatorProvider {
    id: calcProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: CalculatorProvider");
    }
  }

  SettingsProvider {
    id: settingsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SettingsProvider");
    }
  }

  SessionProvider {
    id: sessionProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SessionProvider");
    }
  }

  WindowsProvider {
    id: windowsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: WindowsProvider");
    }
  }

  // ==================== UI Content ====================

  opacity: resultsReady ? 1.0 : 0.0

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCirc
    }
  }

  HoverHandler {
    id: globalHoverHandler
    enabled: !Settings.data.appLauncher.ignoreMouseInput

    onPointChanged: {
      if (!root.mouseTrackingReady) {
        return;
      }

      if (!root.globalMouseInitialized) {
        root.globalLastMouseX = point.position.x;
        root.globalLastMouseY = point.position.y;
        root.globalMouseInitialized = true;
        return;
      }

      const deltaX = Math.abs(point.position.x - root.globalLastMouseX);
      const deltaY = Math.abs(point.position.y - root.globalLastMouseY);
      if (deltaX + deltaY >= 5) {
        root.ignoreMouseHover = false;
        root.globalLastMouseX = point.position.x;
        root.globalLastMouseY = point.position.y;
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: Style.marginL
    anchors.bottomMargin: Style.marginL
    spacing: Style.marginL

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      spacing: Style.marginS

      NTextInput {
        id: searchInput
        Layout.fillWidth: true
        radius: Style.iRadiusM
        text: root.searchText
        placeholderText: I18n.tr("placeholders.search-launcher")
        fontSize: Style.fontSizeM
        onTextChanged: root.searchText = text

        Component.onCompleted: {
          if (searchInput.inputItem) {
            searchInput.inputItem.forceActiveFocus();
            searchInput.inputItem.Keys.onPressed.connect(function (event) {
              root.handleKeyPress(event);
            });
          }
        }
      }

      NIconButton {
        visible: root.showLayoutToggle
        icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
        tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
        customRadius: Style.iRadiusM
        Layout.preferredWidth: searchInput.height
        Layout.preferredHeight: searchInput.height
        onClicked: Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid"
      }
    }

    // Unified category tabs (works with any provider that has categories)
    NTabBar {
      id: categoryTabs
      visible: root.showProviderCategories
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      margins: 0
      border.color: Style.boxBorderColor
      border.width: Style.borderS

      property int computedCurrentIndex: visible && root.providerCategories.length > 0 ? root.providerCategories.indexOf(root.currentProvider.selectedCategory) : 0
      currentIndex: computedCurrentIndex

      Repeater {
        model: root.providerCategories
        NTabButton {
          required property string modelData
          required property int index
          icon: root.currentProvider.categoryIcons ? (root.currentProvider.categoryIcons[modelData] || "star") : "star"
          tooltipText: root.currentProvider.getCategoryName ? root.currentProvider.getCategoryName(modelData) : modelData
          tabIndex: index
          checked: categoryTabs.currentIndex === index
          onClicked: root.currentProvider.selectCategory(modelData)
        }
      }
    }

    // Results view
    Loader {
      id: resultsViewLoader
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      Layout.fillHeight: true
      sourceComponent: root.isSingleView ? singleViewComponent : (root.isGridView ? gridViewComponent : listViewComponent)
    }

    // --------------------------
    // LIST VIEW
    Component {
      id: listViewComponent
      NListView {
        id: resultsList

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Settings.data.ui.panelBackgroundOpacity < 1 ? "transparent" : Color.mSurface
        wheelScrollMultiplier: 4.0

        width: parent.width
        height: parent.height
        spacing: Style.marginS
        model: root.results
        currentIndex: root.selectedIndex
        cacheBuffer: resultsList.height * 2
        interactive: !Settings.data.appLauncher.ignoreMouseInput
        onCurrentIndexChanged: {
          cancelFlick();
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain);
          }
        }
        onModelChanged: {}

        delegate: LauncherListDelegate {
          launcher: root
        }
      }
    }

    // --------------------------
    // SINGLE ITEM VIEW
    Component {
      id: singleViewComponent

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NBox {
          anchors.fill: parent
          color: Color.mSurfaceVariant
          forceOpaque: true
          Layout.fillWidth: true
          Layout.fillHeight: true

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              NText {
                text: root.results.length > 0 ? root.results[0].name : ""
                pointSize: Style.fontSizeL
                font.weight: Font.Bold
                color: Color.mPrimary
              }
            }

            NScrollView {
              id: descriptionScrollView
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              Layout.topMargin: Style.fontSizeL + Style.marginXL
              Layout.fillWidth: true
              Layout.fillHeight: true
              horizontalPolicy: ScrollBar.AlwaysOff
              reserveScrollbarSpace: false

              NText {
                width: descriptionScrollView.availableWidth
                text: root.results.length > 0 ? root.results[0].description : ""
                pointSize: Style.fontSizeM
                font.weight: Font.Bold
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHLeft
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                markdownTextEnabled: true
              }
            }
          }
        }
      }
    }

    // // --------------------------
    // GRID VIEW
    Component {
      id: gridViewComponent
      NGridView {
        id: resultsGrid

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Settings.data.ui.panelBackgroundOpacity < 1 ? "transparent" : Color.mSurface
        wheelScrollMultiplier: 4.0
        trackedSelectionIndex: root.selectedIndex

        width: parent.width
        height: parent.height
        cellWidth: parent.width / root.targetGridColumns
        cellHeight: {
          var cellWidth = parent.width / root.targetGridColumns;
          // Use provider's preferred ratio if available
          if (root.currentProvider && root.currentProvider.preferredGridCellRatio) {
            return cellWidth * root.currentProvider.preferredGridCellRatio;
          }
          return cellWidth;
        }
        leftMargin: 0
        rightMargin: 0
        topMargin: 0
        bottomMargin: 0
        model: root.results
        cacheBuffer: resultsGrid.height * 2
        keyNavigationEnabled: false
        focus: false
        interactive: !Settings.data.appLauncher.ignoreMouseInput

        // Completely disable GridView key handling
        Keys.enabled: false

        // Handle scrolling to show selected item when it changes
        Connections {
          target: root
          enabled: root.isGridView
          function onSelectedIndexChanged() {
            if (!root.isGridView || root.selectedIndex < 0 || !resultsGrid) {
              return;
            }

            Qt.callLater(() => {
                           if (root.isGridView && resultsGrid && resultsGrid.cancelFlick) {
                             resultsGrid.cancelFlick();
                             resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                           }
                         });
          }
        }

        delegate: LauncherGridDelegate {
          launcher: root
        }
      }
    }

    ColumnLayout {
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL

      NDivider {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
      }

      NText {
        Layout.fillWidth: true
        text: {
          if (root.results.length === 0) {
            if (root.searchText) {
              return I18n.tr("common.no-results");
            }
            // Use provider's empty browsing message if available
            var provider = root.currentProvider;
            if (provider && provider.emptyBrowsingMessage) {
              return provider.emptyBrowsingMessage;
            }
            return "";
          }
          var prefix = root.activeProvider && root.activeProvider.name ? root.activeProvider.name + ": " : "";
          return prefix + I18n.trp("common.result-count", root.results.length);
        }
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
