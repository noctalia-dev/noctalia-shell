import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings
import qs.Services.Theming
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: 800 * Style.uiScaleRatio
  preferredHeight: 600 * Style.uiScaleRatio
  preferredWidthRatio: 0.5
  preferredHeightRatio: 0.45

  // Positioning
  readonly property string screenBarPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property string panelPosition: {
    if (Settings.data.wallpaper.panelPosition === "follow_bar") {
      if (screenBarPosition === "left" || screenBarPosition === "right") {
        return `center_${screenBarPosition}`;
      } else {
        return `${screenBarPosition}_center`;
      }
    } else {
      return Settings.data.wallpaper.panelPosition;
    }
  }
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  // Store direct reference to content for instant access
  property var contentItem: null

  // Override keyboard handlers to enable grid navigation
  function onDownPressed() {
    if (!contentItem)
      return;
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex);
    if (view?.gridView) {
      if (!view.gridView.hasActiveFocus) {
        view.gridView.forceActiveFocus();
        if (view.gridView.currentIndex < 0 && view.gridView.model.length > 0) {
          view.gridView.currentIndex = 0;
        }
      } else {
        if (view.gridView.currentIndex < 0 && view.gridView.model.length > 0) {
          view.gridView.currentIndex = 0;
        } else {
          view.gridView.moveCurrentIndexDown();
        }
      }
    }
  }

  function onUpPressed() {
    if (!contentItem)
      return;
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex);
    if (view?.gridView?.hasActiveFocus) {
      if (view.gridView.currentIndex < 0 && view.gridView.model.length > 0) {
        view.gridView.currentIndex = 0;
      } else {
        view.gridView.moveCurrentIndexUp();
      }
    }
  }

  function onLeftPressed() {
    if (!contentItem)
      return;
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex);
    if (view?.gridView?.hasActiveFocus) {
      if (view.gridView.currentIndex < 0 && view.gridView.model.length > 0) {
        view.gridView.currentIndex = 0;
      } else {
        view.gridView.moveCurrentIndexLeft();
      }
    }
  }

  function onRightPressed() {
    if (!contentItem)
      return;
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex);
    if (view?.gridView?.hasActiveFocus) {
      if (view.gridView.currentIndex < 0 && view.gridView.model.length > 0) {
        view.gridView.currentIndex = 0;
      } else {
        view.gridView.moveCurrentIndexRight();
      }
    }
  }

  function onReturnPressed() {
    if (!contentItem)
      return;
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex);
    if (view?.gridView?.hasActiveFocus) {
      let gridView = view.gridView;
      if (gridView.currentIndex >= 0 && gridView.currentIndex < gridView.model.length) {
        view.selectItem(gridView.model[gridView.currentIndex]);
      }
    }
  }

  function onEnterPressed() {
    onReturnPressed();
  }

  panelContent: Rectangle {
    id: panelContent

    property int currentScreenIndex: {
      if (screen !== null) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
          if (Quickshell.screens[i].name == screen.name) {
            return i;
          }
        }
      }
      return 0;
    }
    property var currentScreen: Quickshell.screens[currentScreenIndex]
    property string filterText: ""
    property alias screenRepeater: screenRepeater

    Component.onCompleted: {
      root.contentItem = panelContent;
    }

    // Function to update Wallhaven resolution filter
    function updateWallhavenResolution() {
      if (typeof WallhavenService === "undefined") {
        return;
      }

      var width = Settings.data.wallpaper.wallhavenResolutionWidth || "";
      var height = Settings.data.wallpaper.wallhavenResolutionHeight || "";
      var mode = Settings.data.wallpaper.wallhavenResolutionMode || "atleast";

      if (width && height) {
        var resolution = width + "x" + height;
        if (mode === "atleast") {
          WallhavenService.minResolution = resolution;
          WallhavenService.resolutions = "";
        } else {
          WallhavenService.minResolution = "";
          WallhavenService.resolutions = resolution;
        }
      } else {
        WallhavenService.minResolution = "";
        WallhavenService.resolutions = "";
      }

      // Trigger new search with updated resolution
      if (Settings.data.wallpaper.useWallhaven) {
        if (wallhavenView) {
          wallhavenView.loading = true;
        }
        WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);
      }
    }

    color: "transparent"

    // Wallhaven settings popup
    Loader {
      id: wallhavenSettingsPopup
      source: "WallhavenSettingsPopup.qml"
      onLoaded: {
        if (item) {
          item.screen = screen;
        }
      }
    }

    // Solid color picker dialog
    NColorPickerDialog {
      id: solidColorPicker
      screen: root.screen
      selectedColor: Settings.data.wallpaper.solidColor
      onColorSelected: color => WallpaperService.setSolidColor(color.toString())
    }

    // Focus management
    Connections {
      target: root
      function onOpened() {
        // Ensure contentItem is set
        if (!root.contentItem) {
          root.contentItem = panelContent;
        }
        // Reset grid view selections
        for (var i = 0; i < screenRepeater.count; i++) {
          let item = screenRepeater.itemAt(i);
          if (item && item.gridView) {
            item.gridView.currentIndex = -1;
          }
        }
        if (wallhavenView && wallhavenView.gridView) {
          wallhavenView.gridView.currentIndex = -1;
        }
        // Give initial focus to search input
        Qt.callLater(() => {
                       if (searchInput.inputItem) {
                         searchInput.inputItem.forceActiveFocus();
                       }
                     });
      }
    }

    // Debounce timer for search
    Timer {
      id: searchDebounceTimer
      interval: 150
      onTriggered: {
        panelContent.filterText = searchInput.text;
        // Trigger update on all screen views
        for (var i = 0; i < screenRepeater.count; i++) {
          let item = screenRepeater.itemAt(i);
          if (item && item.updateFiltered) {
            item.updateFiltered();
          }
        }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Debounce timer for Wallhaven search
      Timer {
        id: wallhavenSearchDebounceTimer
        interval: 500
        onTriggered: {
          Settings.data.wallpaper.wallhavenQuery = searchInput.text;
          if (typeof WallhavenService !== "undefined") {
            wallhavenView.loading = true;
            WallhavenService.search(searchInput.text, 1);
          }
        }
      }

      // Header
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerColumn.implicitHeight + Style.marginL * 2
        color: Color.mSurfaceVariant

        ColumnLayout {
          id: headerColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NIcon {
              icon: "settings-wallpaper-selector"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("wallpaper.panel.title")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "palette"
              tooltipText: I18n.tr("wallpaper.panel.solid-color-tooltip")
              baseSize: Style.baseWidgetSize * 0.8
              colorBg: Settings.data.wallpaper.useSolidColor ? Color.mPrimary : Color.mSurfaceVariant
              colorFg: Settings.data.wallpaper.useSolidColor ? Color.mOnPrimary : Color.mPrimary
              onClicked: solidColorPicker.open()
            }

            NIconButton {
              icon: "settings"
              tooltipText: I18n.tr("panels.wallpaper.settings-title")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                var settingsPanel = PanelService.getPanel("settingsPanel", screen);
                settingsPanel.requestedTab = SettingsPanel.Tab.Wallpaper;
                settingsPanel.open();
              }
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }

          NDivider {
            Layout.fillWidth: true
          }

          NToggle {
            label: I18n.tr("wallpaper.panel.apply-all-monitors-label")
            description: I18n.tr("wallpaper.panel.apply-all-monitors-description")
            checked: Settings.data.wallpaper.setWallpaperOnAllMonitors
            onToggled: checked => Settings.data.wallpaper.setWallpaperOnAllMonitors = checked
            Layout.fillWidth: true
          }

          // Monitor tabs
          NTabBar {
            id: screenTabBar
            visible: (!Settings.data.wallpaper.setWallpaperOnAllMonitors || Settings.data.wallpaper.enableMultiMonitorDirectories)
            Layout.fillWidth: true
            currentIndex: currentScreenIndex
            onCurrentIndexChanged: currentScreenIndex = currentIndex
            spacing: Style.marginM
            distributeEvenly: true

            Repeater {
              model: Quickshell.screens
              NTabButton {
                required property var modelData
                required property int index
                text: modelData.name || `Screen ${index + 1}`
                tabIndex: index
                checked: {
                  screenTabBar.currentIndex === index;
                }
              }
            }
          }

          // Unified search input and source
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NTextInput {
              id: searchInput
              placeholderText: Settings.data.wallpaper.useWallhaven ? I18n.tr("placeholders.search-wallhaven") : I18n.tr("placeholders.search-wallpapers")
              fontSize: Style.fontSizeM
              Layout.fillWidth: true

              property bool initializing: true
              Component.onCompleted: {
                // Initialize text based on current mode
                if (Settings.data.wallpaper.useWallhaven) {
                  searchInput.text = Settings.data.wallpaper.wallhavenQuery || "";
                } else {
                  searchInput.text = panelContent.filterText || "";
                }
                // Give focus to search input
                if (searchInput.inputItem && searchInput.inputItem.visible) {
                  searchInput.inputItem.forceActiveFocus();
                }
                // Mark initialization as complete after a short delay
                Qt.callLater(function () {
                  searchInput.initializing = false;
                });
              }

              Connections {
                target: Settings.data.wallpaper
                function onUseWallhavenChanged() {
                  // Update text when mode changes
                  if (Settings.data.wallpaper.useWallhaven) {
                    searchInput.text = Settings.data.wallpaper.wallhavenQuery || "";
                  } else {
                    searchInput.text = panelContent.filterText || "";
                  }
                }
              }

              onTextChanged: {
                // Don't trigger search during initialization - Component.onCompleted will handle initial search
                if (initializing) {
                  return;
                }
                if (Settings.data.wallpaper.useWallhaven) {
                  wallhavenSearchDebounceTimer.restart();
                } else {
                  searchDebounceTimer.restart();
                }
              }

              onEditingFinished: {
                if (Settings.data.wallpaper.useWallhaven) {
                  wallhavenSearchDebounceTimer.stop();
                  // Only search if the query actually changed
                  if (typeof WallhavenService !== "undefined" && text !== WallhavenService.currentQuery) {
                    Settings.data.wallpaper.wallhavenQuery = text;
                    wallhavenView.loading = true;
                    WallhavenService.search(text, 1);
                  }
                }
              }

              Keys.onDownPressed: {
                if (Settings.data.wallpaper.useWallhaven) {
                  if (wallhavenView && wallhavenView.gridView) {
                    wallhavenView.gridView.forceActiveFocus();
                  }
                } else {
                  let currentView = screenRepeater.itemAt(currentScreenIndex);
                  if (currentView && currentView.gridView) {
                    currentView.gridView.forceActiveFocus();
                  }
                }
              }
            }

            NComboBox {
              id: sourceComboBox
              Layout.fillWidth: false

              model: [
                {
                  "key": "local",
                  "name": I18n.tr("common.local")
                },
                {
                  "key": "wallhaven",
                  "name": I18n.tr("wallpaper.panel.source-wallhaven")
                }
              ]
              currentKey: Settings.data.wallpaper.useWallhaven ? "wallhaven" : "local"
              property bool skipNextSelected: false
              Component.onCompleted: {
                // Skip the first onSelected if it fires during initialization
                skipNextSelected = true;
                Qt.callLater(function () {
                  skipNextSelected = false;
                });
              }
              onSelected: key => {
                            if (skipNextSelected) {
                              return;
                            }
                            var useWallhaven = (key === "wallhaven");
                            Settings.data.wallpaper.useWallhaven = useWallhaven;
                            // Update search input text based on mode
                            if (useWallhaven) {
                              searchInput.text = Settings.data.wallpaper.wallhavenQuery || "";
                            } else {
                              searchInput.text = panelContent.filterText || "";
                            }
                            if (useWallhaven && typeof WallhavenService !== "undefined") {
                              // Update service properties when switching to Wallhaven
                              // Don't search here - Component.onCompleted will handle it when the component is created
                              // This prevents duplicate searches
                              WallhavenService.categories = Settings.data.wallpaper.wallhavenCategories;
                              WallhavenService.purity = Settings.data.wallpaper.wallhavenPurity;
                              WallhavenService.sorting = Settings.data.wallpaper.wallhavenSorting;
                              WallhavenService.order = Settings.data.wallpaper.wallhavenOrder;

                              // Update resolution settings
                              panelContent.updateWallhavenResolution();

                              // If the view is already initialized, trigger a new search when switching to it
                              // Preserve current page when switching back to Wallhaven source
                              if (wallhavenView && wallhavenView.initialized && !WallhavenService.fetching) {
                                wallhavenView.loading = true;
                                WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", WallhavenService.currentPage);
                              }
                            }
                          }
            }

            // Settings button (only visible for Wallhaven)
            NIconButton {
              id: wallhavenSettingsButton
              icon: "settings"
              tooltipText: I18n.tr("wallpaper.panel.wallhaven-settings-title")
              baseSize: Style.baseWidgetSize * 0.8
              visible: Settings.data.wallpaper.useWallhaven
              onClicked: {
                if (searchInput.inputItem) {
                  searchInput.inputItem.focus = false;
                }
                if (wallhavenSettingsPopup.item) {
                  wallhavenSettingsPopup.item.showAt(wallhavenSettingsButton);
                }
              }
            }
          }
        }
      }

      // Content stack: Wallhaven or Local
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant

        StackLayout {
          id: contentStack
          anchors.fill: parent
          anchors.margins: Style.marginL

          currentIndex: Settings.data.wallpaper.useWallhaven ? 1 : 0

          // Local wallpapers
          StackLayout {
            id: screenStack
            currentIndex: currentScreenIndex

            Repeater {
              id: screenRepeater
              model: Quickshell.screens
              delegate: WallpaperScreenView {
                targetScreen: modelData
              }
            }
          }

          // Wallhaven wallpapers
          WallhavenView {
            id: wallhavenView
          }
        }
      }
    }
  }

  // Component for each screen's wallpaper view
  component WallpaperScreenView: Item {
    property var targetScreen
    property alias gridView: wallpaperGridView

    // Local reactive state for this screen
    property list<string> wallpapersList: []
    property string currentWallpaper: ""
    property var filteredItems: [] // Combined list of { path, name, isDirectory }
    property var wallpapersWithNames: [] // Cached basenames for files
    property var directoriesList: [] // List of directories in browse mode

    // Browse mode properties
    property string currentBrowsePath: WallpaperService.getCurrentBrowsePath(targetScreen?.name ?? "")
    property bool isBrowseMode: Settings.data.wallpaper.viewMode === "browse"

    // Expose updateFiltered as a proper function property
    function updateFiltered() {
      var combinedItems = [];

      // In browse mode, add directories first
      if (isBrowseMode) {
        for (var i = 0; i < directoriesList.length; i++) {
          var dirPath = directoriesList[i];
          combinedItems.push({
                               "path": dirPath,
                               "name": dirPath.split('/').pop(),
                               "isDirectory": true
                             });
        }
      }

      // Add files
      for (var i = 0; i < wallpapersList.length; i++) {
        combinedItems.push({
                             "path": wallpapersList[i],
                             "name": wallpapersList[i].split('/').pop(),
                             "isDirectory": false
                           });
      }

      // Apply filter if text is present
      if (!panelContent.filterText || panelContent.filterText.trim().length === 0) {
        filteredItems = combinedItems;
        return;
      }

      const results = FuzzySort.go(panelContent.filterText.trim(), combinedItems, {
                                     "key": 'name',
                                     "limit": 200
                                   });
      // Map back to item list
      filteredItems = results.map(function (r) {
        return r.obj;
      });
    }

    Component.onCompleted: {
      refreshWallpaperScreenData();
    }

    Connections {
      target: WallpaperService
      function onWallpaperChanged(screenName, path) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          currentWallpaper = WallpaperService.getWallpaper(targetScreen.name);
        }
      }
      function onWallpaperDirectoryChanged(screenName, directory) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          // Reset browse path when root directory changes
          if (isBrowseMode) {
            WallpaperService.navigateToRoot(targetScreen.name);
          }
          refreshWallpaperScreenData();
        }
      }
      function onWallpaperListChanged(screenName, count) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          refreshWallpaperScreenData();
        }
      }
      function onBrowsePathChanged(screenName, path) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          currentBrowsePath = path;
          refreshWallpaperScreenData();
        }
      }
    }

    function refreshWallpaperScreenData() {
      if (targetScreen === null) {
        return;
      }

      currentWallpaper = WallpaperService.getWallpaper(targetScreen.name);

      if (isBrowseMode) {
        // In browse mode, scan current directory for both files and directories
        var browsePath = WallpaperService.getCurrentBrowsePath(targetScreen.name);
        currentBrowsePath = browsePath;

        WallpaperService.scanDirectoryWithDirs(targetScreen.name, browsePath, function (result) {
          wallpapersList = result.files;
          directoriesList = result.directories;
          Logger.d("WallpaperPanel", "Browse mode: Got", wallpapersList.length, "files and", directoriesList.length, "directories for screen", targetScreen.name);
          updateFiltered();
        });
      } else {
        // Normal mode: just use the wallpaper list from service
        wallpapersList = WallpaperService.getWallpapersList(targetScreen.name);
        directoriesList = [];
        Logger.d("WallpaperPanel", "Got", wallpapersList.length, "wallpapers for screen", targetScreen.name);
        updateFiltered();
      }
    }

    function selectItem(item) {
      if (item.isDirectory) {
        WallpaperService.setBrowsePath(targetScreen.name, item.path);
      } else if (Settings.data.wallpaper.setWallpaperOnAllMonitors) {
        WallpaperService.changeWallpaper(item.path, undefined);
      } else {
        WallpaperService.changeWallpaper(item.path, targetScreen.name);
      }
    }

    // Helper function to cycle view modes
    function cycleViewMode() {
      var mode = Settings.data.wallpaper.viewMode;
      if (mode === "single") {
        Settings.data.wallpaper.viewMode = "recursive";
      } else if (mode === "recursive") {
        Settings.data.wallpaper.viewMode = "browse";
      } else {
        Settings.data.wallpaper.viewMode = "single";
      }
    }

    // Helper function to get icon for current view mode
    function getViewModeIcon() {
      var mode = Settings.data.wallpaper.viewMode;
      if (mode === "single")
        return "folder";
      if (mode === "recursive")
        return "folders";
      return "folder-open";
    }

    // Helper function to get tooltip for current view mode
    function getViewModeTooltip() {
      var mode = Settings.data.wallpaper.viewMode;
      var modeName;
      if (mode === "single")
        modeName = I18n.tr("panels.wallpaper.view-mode-single");
      else if (mode === "recursive")
        modeName = I18n.tr("panels.wallpaper.view-mode-recursive");
      else
        modeName = I18n.tr("panels.wallpaper.view-mode-browse");
      return I18n.tr("panels.wallpaper.view-mode-cycle-tooltip").replace("{mode}", modeName);
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.marginM

      // Combined toolbar: navigation (left) + actions (right)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        // Left side: navigation (back, home, path)
        NIconButton {
          icon: "arrow-left"
          tooltipText: I18n.tr("wallpaper.browse.go-up")
          enabled: isBrowseMode && currentBrowsePath !== WallpaperService.getMonitorDirectory(targetScreen?.name ?? "")
          onClicked: WallpaperService.navigateUp(targetScreen?.name ?? "")
          baseSize: Style.baseWidgetSize * 0.8
        }

        NIconButton {
          icon: "home"
          tooltipText: I18n.tr("wallpaper.browse.go-root")
          enabled: isBrowseMode && currentBrowsePath !== WallpaperService.getMonitorDirectory(targetScreen?.name ?? "")
          onClicked: WallpaperService.navigateToRoot(targetScreen?.name ?? "")
          baseSize: Style.baseWidgetSize * 0.8
        }

        NScrollText {
          text: isBrowseMode ? currentBrowsePath : WallpaperService.getMonitorDirectory(targetScreen?.name ?? "")
          Layout.fillWidth: true
          scrollMode: NScrollText.ScrollMode.Hover
          NText {
            text: isBrowseMode ? currentBrowsePath : WallpaperService.getMonitorDirectory(targetScreen?.name ?? "")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
        }

        // Right side: actions (view mode, hide filenames, refresh)
        NComboBox {
          visible: Settings.data.colorSchemes.useWallpaperColors
          baseSize: 0.8
          Layout.minimumWidth: 200
          minimumWidth: 200
          //tooltip: I18n.tr("panels.color-scheme.wallpaper-method-label")
          model: TemplateProcessor.schemeTypes
          currentKey: Settings.data.colorSchemes.generationMethod
          onSelected: key => {
                        Settings.data.colorSchemes.generationMethod = key;
                        AppThemeService.generate();
                      }
        }

        NIconButton {
          property string sortOrder: Settings.data.wallpaper.sortOrder || "name"
          icon: {
            if (sortOrder === "date_desc")
              return "clock";
            if (sortOrder === "date_asc")
              return "history";
            if (sortOrder === "name_desc")
              return "sort-descending";
            if (sortOrder === "random")
              return "arrows-shuffle";
            return "sort-ascending";
          }
          tooltipText: {
            if (sortOrder === "date_desc")
              return "Sort: Newest First";
            if (sortOrder === "date_asc")
              return "Sort: Oldest First";
            if (sortOrder === "name_desc")
              return "Sort: Name (Z-A)";
            if (sortOrder === "random")
              return "Sort: Random";
            return "Sort: Name (A-Z)";
          }
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            var next = "name";
            if (sortOrder === "name")
              next = "date_desc";
            else if (sortOrder === "date_desc")
              next = "name"; // Toggle simpler: Name -> Newest -> Name
            // Expanded cycle: Name -> Newest -> Oldest -> Z-A -> Random -> Name
            // User just asked for "newest first", so let's make it easy to reach.
            // Let's do: Name (A-Z) -> Newest -> Oldest -> Name (Z-A) -> ...

            if (sortOrder === "name")
              next = "date_desc";
            else if (sortOrder === "date_desc")
              next = "date_asc";
            else if (sortOrder === "date_asc")
              next = "name_desc";
            else if (sortOrder === "name_desc")
              next = "random";
            else
              next = "name";

            Settings.data.wallpaper.sortOrder = next;
          }
        }

        NIconButton {
          icon: getViewModeIcon()
          tooltipText: getViewModeTooltip()
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: cycleViewMode()
        }

        NIconButton {
          icon: Settings.data.wallpaper.hideWallpaperFilenames ? "id-off" : "id"
          tooltipText: Settings.data.wallpaper.hideWallpaperFilenames ? I18n.tr("panels.wallpaper.settings-hide-wallpaper-filenames-tooltip-show") : I18n.tr("panels.wallpaper.settings-hide-wallpaper-filenames-tooltip-hide")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: Settings.data.wallpaper.hideWallpaperFilenames = !Settings.data.wallpaper.hideWallpaperFilenames
        }

        NIconButton {
          icon: Settings.data.wallpaper.showHiddenFiles ? "eye" : "eye-closed"
          tooltipText: Settings.data.wallpaper.showHiddenFiles ? I18n.tr("panels.wallpaper.settings-show-hidden-files-tooltip-hide") : I18n.tr("panels.wallpaper.settings-show-hidden-files-tooltip-show")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: Settings.data.wallpaper.showHiddenFiles = !Settings.data.wallpaper.showHiddenFiles
        }

        NIconButton {
          icon: "refresh"
          tooltipText: I18n.tr("tooltips.refresh-wallpaper-list")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            if (isBrowseMode) {
              refreshWallpaperScreenData();
            } else {
              WallpaperService.refreshWallpapersList();
            }
          }
        }
      }

      NGridView {
        id: wallpaperGridView

        Layout.fillWidth: true
        Layout.fillHeight: true

        visible: !WallpaperService.scanning
        interactive: true
        keyNavigationEnabled: true
        keyNavigationWraps: false
        highlightFollowsCurrentItem: false
        currentIndex: -1

        model: filteredItems

        onModelChanged: {
          // Reset selection and scroll position when model changes
          currentIndex = -1;
          positionViewAtBeginning();
        }

        Component.onCompleted: {
          positionViewAtBeginning();
        }

        property int columns: (screen.width > 1920) ? 5 : 4
        property int itemSize: cellWidth

        cellWidth: Math.floor((availableWidth - leftMargin - rightMargin) / columns)
        cellHeight: Math.floor(itemSize * 0.7) + Style.marginXS + Style.fontSizeXS + Style.marginM

        leftMargin: Style.marginS
        rightMargin: Style.marginS
        topMargin: Style.marginS
        bottomMargin: Style.marginS

        onCurrentIndexChanged: {
          // Synchronize scroll with current item position
          if (currentIndex >= 0) {
            let row = Math.floor(currentIndex / columns);
            let itemY = row * cellHeight;
            let viewportTop = contentY;
            let viewportBottom = viewportTop + height;

            // If item is out of view, scroll
            if (itemY < viewportTop) {
              contentY = Math.max(0, itemY - cellHeight);
            } else if (itemY + cellHeight > viewportBottom) {
              contentY = itemY + cellHeight - height + cellHeight;
            }
          }
        }

        onKeyPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                          if (currentIndex >= 0 && currentIndex < filteredItems.length) {
                            selectItem(filteredItems[currentIndex]);
                          }
                          event.accepted = true;
                        }
                      }

        delegate: Item {
          id: wallpaperItemWrapper
          width: wallpaperGridView.cellWidth
          height: wallpaperGridView.cellHeight

          ColumnLayout {
            id: wallpaperItem
            anchors.fill: parent
            anchors.margins: Style.marginXS

            property string wallpaperPath: modelData.path ?? ""
            property bool isDirectory: modelData.isDirectory ?? false
            property bool isSelected: !isDirectory && (wallpaperPath === currentWallpaper)
            property string filename: modelData.name ?? wallpaperPath.split('/').pop()
            property string cachedPath: ""

            spacing: Style.marginXS

            Component.onCompleted: {
              if (!isDirectory && ImageCacheService.initialized) {
                ImageCacheService.getThumbnail(wallpaperPath, function (path, success) {
                  if (wallpaperItem)
                    wallpaperItem.cachedPath = success ? path : wallpaperPath;
                });
              } else if (!isDirectory) {
                cachedPath = wallpaperPath;
              }
            }

            Item {
              id: imageContainer
              Layout.fillWidth: true
              Layout.fillHeight: true

              property real imageHeight: Math.round(wallpaperGridView.itemSize * 0.67)

              // Directory display
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: imageContainer.imageHeight
                color: Color.mSurfaceVariant
                radius: Style.radiusM
                visible: wallpaperItem.isDirectory
                border.color: wallpaperGridView.currentIndex === index ? Color.mHover : Color.mSurface
                border.width: Math.max(1, Style.borderL * 1.5)

                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: Style.marginS

                  NIcon {
                    icon: "folder"
                    pointSize: Style.fontSizeXXXL
                    color: Color.mPrimary
                    Layout.alignment: Qt.AlignHCenter
                  }
                }
              }

              // Image display (for non-directories)
              NImageRounded {
                id: img
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: imageContainer.imageHeight
                visible: !wallpaperItem.isDirectory
                imagePath: wallpaperItem.cachedPath
                radius: Style.radiusM
                borderColor: {
                  if (wallpaperItem.isSelected) {
                    return Color.mSecondary;
                  }
                  if (wallpaperGridView.currentIndex === index) {
                    return Color.mHover;
                  }
                  return Color.mSurface;
                }
                borderWidth: Math.max(1, Style.borderL * 1.5)
                imageFillMode: Image.PreserveAspectCrop
              }

              // Loading/error state background (for non-directories)
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: imageContainer.imageHeight
                color: Color.mSurfaceVariant
                radius: Style.radiusM
                visible: !wallpaperItem.isDirectory && (img.status === Image.Loading || img.status === Image.Error || wallpaperItem.cachedPath === "")

                NIcon {
                  icon: "image"
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurfaceVariant
                  anchors.centerIn: parent
                }
              }

              NBusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                y: (imageContainer.imageHeight - height) / 2
                visible: !wallpaperItem.isDirectory && (img.status === Image.Loading || wallpaperItem.cachedPath === "")
                running: visible
                size: 18
              }

              Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.marginS
                width: 28
                height: 28
                radius: width / 2
                color: Color.mSecondary
                border.color: Color.mOutline
                border.width: Style.borderS
                visible: wallpaperItem.isSelected

                NIcon {
                  icon: "check"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSecondary
                  anchors.centerIn: parent
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: imageContainer.imageHeight
                color: Color.mSurface
                radius: Style.radiusM
                opacity: (hoverHandler.hovered || wallpaperItem.isSelected || wallpaperGridView.currentIndex === index) ? 0 : 0.3
                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              HoverHandler {
                id: hoverHandler
              }

              TapHandler {
                onTapped: {
                  wallpaperGridView.forceActiveFocus();
                  wallpaperGridView.currentIndex = index;
                  selectItem(modelData);
                }
              }
            }

            NText {
              text: wallpaperItem.filename
              visible: !Settings.data.wallpaper.hideWallpaperFilenames
              color: (hoverHandler.hovered || wallpaperItem.isSelected || wallpaperGridView.currentIndex === index) ? Color.mOnSurface : Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              Layout.fillWidth: true
              Layout.leftMargin: Style.marginS
              Layout.rightMargin: Style.marginS
              Layout.alignment: Qt.AlignHCenter
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }
      }

      // Empty / scanning state
      Rectangle {
        color: Color.mSurface
        radius: Style.radiusM
        border.color: Color.mOutline
        border.width: Style.borderS
        visible: (filteredItems.length === 0 && !WallpaperService.scanning) || WallpaperService.scanning
        Layout.fillWidth: true
        Layout.preferredHeight: 130

        ColumnLayout {
          anchors.fill: parent
          visible: WallpaperService.scanning
          NBusyIndicator {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
          }
        }

        ColumnLayout {
          anchors.fill: parent
          visible: filteredItems.length === 0 && !WallpaperService.scanning
          Item {
            Layout.fillHeight: true
          }
          NIcon {
            icon: "folder-open"
            pointSize: Style.fontSizeXXL
            color: Color.mOnSurface
            Layout.alignment: Qt.AlignHCenter
          }
          NText {
            text: (panelContent.filterText && panelContent.filterText.length > 0) ? I18n.tr("wallpaper.no-match") : (isBrowseMode ? I18n.tr("wallpaper.browse.empty-directory") : I18n.tr("wallpaper.no-wallpaper"))
            color: Color.mOnSurface
            font.weight: Style.fontWeightBold
            Layout.alignment: Qt.AlignHCenter
          }
          NText {
            text: (panelContent.filterText && panelContent.filterText.length > 0) ? I18n.tr("wallpaper.try-different-search") : (isBrowseMode ? I18n.tr("wallpaper.browse.go-up-hint") : I18n.tr("wallpaper.configure-directory"))
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter
          }
          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }

  // Component for Wallhaven wallpapers view
  component WallhavenView: Item {
    id: wallhavenViewRoot
    property alias gridView: wallhavenGridView

    property var wallpapers: []
    property bool loading: false
    property string errorMessage: ""
    property bool initialized: false
    property bool searchScheduled: false

    Connections {
      target: typeof WallhavenService !== "undefined" ? WallhavenService : null
      function onSearchCompleted(results, meta) {
        wallhavenViewRoot.wallpapers = results || [];
        wallhavenViewRoot.loading = false;
        wallhavenViewRoot.errorMessage = "";
        wallhavenViewRoot.searchScheduled = false;
      }
      function onSearchFailed(error) {
        wallhavenViewRoot.loading = false;
        wallhavenViewRoot.errorMessage = error || "";
        wallhavenViewRoot.searchScheduled = false;
      }
    }

    Component.onCompleted: {
      // Initialize service properties and perform initial search if Wallhaven is active
      if (typeof WallhavenService !== "undefined" && Settings.data.wallpaper.useWallhaven && !initialized) {
        // Set flags immediately to prevent race conditions
        if (WallhavenService.initialSearchScheduled) {
          // Another instance already scheduled the search, just initialize properties
          initialized = true;
          return;
        }

        // We're the first one - claim the search
        initialized = true;
        WallhavenService.initialSearchScheduled = true;
        WallhavenService.categories = Settings.data.wallpaper.wallhavenCategories;
        WallhavenService.purity = Settings.data.wallpaper.wallhavenPurity;
        WallhavenService.sorting = Settings.data.wallpaper.wallhavenSorting;
        WallhavenService.order = Settings.data.wallpaper.wallhavenOrder;

        // Initialize resolution settings
        var width = Settings.data.wallpaper.wallhavenResolutionWidth || "";
        var height = Settings.data.wallpaper.wallhavenResolutionHeight || "";
        var mode = Settings.data.wallpaper.wallhavenResolutionMode || "atleast";
        if (width && height) {
          var resolution = width + "x" + height;
          if (mode === "atleast") {
            WallhavenService.minResolution = resolution;
            WallhavenService.resolutions = "";
          } else {
            WallhavenService.minResolution = "";
            WallhavenService.resolutions = resolution;
          }
        } else {
          WallhavenService.minResolution = "";
          WallhavenService.resolutions = "";
        }

        // Now check if we can actually search (fetching check is in WallhavenService.search)
        // Use persisted currentPage to maintain state across window reopening
        loading = true;
        WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", WallhavenService.currentPage);
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.marginM

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NGridView {
          id: wallhavenGridView

          anchors.fill: parent

          visible: !loading && errorMessage === "" && (wallpapers && wallpapers.length > 0)
          interactive: true
          keyNavigationEnabled: true
          keyNavigationWraps: false
          highlightFollowsCurrentItem: false
          currentIndex: -1

          model: wallpapers || []

          onModelChanged: {
            // Reset selection and scroll position when model changes
            currentIndex = -1;
            positionViewAtBeginning();
          }

          Component.onCompleted: {
            positionViewAtBeginning();
          }

          property int columns: (screen.width > 1920) ? 5 : 4
          property int itemSize: cellWidth

          cellWidth: Math.floor((availableWidth - leftMargin - rightMargin) / columns)
          cellHeight: Math.floor(itemSize * 0.7) + Style.marginXS + Style.fontSizeXS + Style.marginM

          leftMargin: Style.marginS
          rightMargin: Style.marginS
          topMargin: Style.marginS
          bottomMargin: Style.marginS

          onCurrentIndexChanged: {
            if (currentIndex >= 0) {
              let row = Math.floor(currentIndex / columns);
              let itemY = row * cellHeight;
              let viewportTop = contentY;
              let viewportBottom = viewportTop + height;

              if (itemY < viewportTop) {
                contentY = Math.max(0, itemY - cellHeight);
              } else if (itemY + cellHeight > viewportBottom) {
                contentY = itemY + cellHeight - height + cellHeight;
              }
            }
          }

          onKeyPressed: event => {
                          if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                            if (currentIndex >= 0 && currentIndex < wallpapers.length) {
                              let wallpaper = wallpapers[currentIndex];
                              wallhavenDownloadAndApply(wallpaper);
                            }
                            event.accepted = true;
                          }
                        }

          delegate: Item {
            id: wallhavenItemWrapper
            width: wallhavenGridView.cellWidth
            height: wallhavenGridView.cellHeight

            ColumnLayout {
              id: wallhavenItem
              anchors.fill: parent
              anchors.margins: Style.marginXS

              property string thumbnailUrl: (modelData && typeof WallhavenService !== "undefined") ? WallhavenService.getThumbnailUrl(modelData, "large") : ""
              property string wallpaperId: (modelData && modelData.id) ? modelData.id : ""

              spacing: Style.marginXS

              Item {
                id: imageContainer
                Layout.fillWidth: true
                Layout.fillHeight: true

                property real imageHeight: Math.round(wallhavenGridView.itemSize * 0.67)

                NImageRounded {
                  id: img
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: imageContainer.imageHeight
                  imagePath: wallhavenItem.thumbnailUrl
                  radius: Style.radiusM
                  borderColor: {
                    if (wallhavenGridView.currentIndex === index) {
                      return Color.mHover;
                    }
                    return Color.mSurface;
                  }
                  borderWidth: Math.max(1, Style.borderL * 1.5)
                  imageFillMode: Image.PreserveAspectCrop
                }

                // Loading/error state background
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: imageContainer.imageHeight
                  color: Color.mSurfaceVariant
                  radius: Style.radiusM
                  visible: img.status === Image.Loading || img.status === Image.Error || wallhavenItem.thumbnailUrl === ""

                  NIcon {
                    icon: "image"
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurfaceVariant
                    anchors.centerIn: parent
                  }
                }

                NBusyIndicator {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: (imageContainer.imageHeight - height) / 2
                  visible: img.status === Image.Loading
                  running: visible
                  size: 18
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: imageContainer.imageHeight
                  color: Color.mSurface
                  radius: Style.radiusM
                  opacity: (hoverHandler.hovered || wallhavenGridView.currentIndex === index) ? 0 : 0.3
                  Behavior on opacity {
                    NumberAnimation {
                      duration: Style.animationFast
                    }
                  }
                }

                HoverHandler {
                  id: hoverHandler
                }

                TapHandler {
                  onTapped: {
                    wallhavenGridView.forceActiveFocus();
                    wallhavenGridView.currentIndex = index;
                    wallhavenDownloadAndApply(modelData);
                  }
                }
              }

              NText {
                text: wallhavenItem.wallpaperId || I18n.tr("common.unknown")
                visible: !Settings.data.wallpaper.hideWallpaperFilenames
                color: (hoverHandler.hovered || wallhavenGridView.currentIndex === index) ? Color.mOnSurface : Color.mOnSurfaceVariant
                pointSize: Style.fontSizeXS
                Layout.fillWidth: true
                Layout.leftMargin: Style.marginS
                Layout.rightMargin: Style.marginS
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
            }
          }
        }

        // Loading overlay - fills same space as GridView to prevent jumping
        Rectangle {
          anchors.fill: parent
          color: Color.mSurface
          radius: Style.radiusM
          border.color: Color.mOutline
          border.width: Style.borderS
          visible: loading
          z: 10

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            Item {
              Layout.fillHeight: true
            }

            NBusyIndicator {
              size: Style.baseWidgetSize * 1.5
              color: Color.mPrimary
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: I18n.tr("wallpaper.wallhaven.loading")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              Layout.alignment: Qt.AlignHCenter
            }

            Item {
              Layout.fillHeight: true
            }
          }
        }

        // Error overlay
        Rectangle {
          anchors.fill: parent
          color: Color.mSurface
          radius: Style.radiusM
          border.color: Color.mOutline
          border.width: Style.borderS
          visible: errorMessage !== "" && !loading
          z: 10

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            Item {
              Layout.fillHeight: true
            }

            NIcon {
              icon: "alert-circle"
              pointSize: Style.fontSizeXXL
              color: Color.mError
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: errorMessage
              color: Color.mOnSurface
              wrapMode: Text.WordWrap
              Layout.alignment: Qt.AlignHCenter
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
            }

            Item {
              Layout.fillHeight: true
            }
          }
        }

        // Empty state overlay
        Rectangle {
          anchors.fill: parent
          color: Color.mSurface
          radius: Style.radiusM
          border.color: Color.mOutline
          border.width: Style.borderS
          visible: (!wallpapers || wallpapers.length === 0) && !loading && errorMessage === ""
          z: 10

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            Item {
              Layout.fillHeight: true
            }

            NIcon {
              icon: "image"
              pointSize: Style.fontSizeXXL
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: I18n.tr("wallpaper.wallhaven.no-results")
              color: Color.mOnSurface
              wrapMode: Text.WordWrap
              Layout.alignment: Qt.AlignHCenter
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
            }

            Item {
              Layout.fillHeight: true
            }
          }
        }
      }

      // Pagination
      RowLayout {
        Layout.fillWidth: true
        visible: !loading && errorMessage === "" && typeof WallhavenService !== "undefined"
        spacing: Style.marginS

        Item {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "chevron-left"
          enabled: WallhavenService.currentPage > 1 && !WallhavenService.fetching
          onClicked: WallhavenService.previousPage()
        }

        NText {
          text: I18n.tr("wallpaper.wallhaven.page").replace("{current}", WallhavenService.currentPage).replace("{total}", WallhavenService.lastPage)
          color: Color.mOnSurface
          horizontalAlignment: Text.AlignHCenter
        }

        NIconButton {
          icon: "chevron-right"
          enabled: WallhavenService.currentPage < WallhavenService.lastPage && !WallhavenService.fetching
          onClicked: WallhavenService.nextPage()
        }

        Item {
          Layout.fillWidth: true
        }
      }
    }

    // -------------------------------
    function wallhavenDownloadAndApply(wallpaper, targetScreen) {
      if (typeof WallhavenService !== "undefined") {
        WallhavenService.downloadWallpaper(wallpaper, function (success, localPath) {
          if (success) {
            if (!Settings.data.wallpaper.setWallpaperOnAllMonitors && currentScreenIndex < Quickshell.screens.length) {
              WallpaperService.changeWallpaper(localPath, Quickshell.screens[currentScreenIndex].name);
            } else {
              WallpaperService.changeWallpaper(localPath, undefined);
            }
          }
        });
      }
    }
  }
}
