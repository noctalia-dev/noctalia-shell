import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  // Build a combined list of all available templates from TemplateRegistry, sorted alphabetically
  readonly property var allTemplates: {
    var templates = [];

    // Helper to format path description
    function getDesc(fallbackPath) {
      return I18n.tr("panels.color-scheme.templates-write-path", {
                       "filepath": fallbackPath
                     });
    }

    // Add terminals with category "terminal"
    for (var i = 0; i < TemplateRegistry.terminals.length; i++) {
      var t = TemplateRegistry.terminals[i];
      templates.push({
                       "id": t.id,
                       "name": t.name,
                       "category": "terminal",
                       "tooltip": getDesc(t.outputPath)
                     });
    }

    // Add applications
    for (var j = 0; j < TemplateRegistry.applications.length; j++) {
      var app = TemplateRegistry.applications[j];
      var path = "";

      // Determine path to show
      if (app.outputs && app.outputs.length > 0) {
        var paths = [];
        for (var k = 0; k < app.outputs.length; k++) {
          paths.push(app.outputs[k].path);
        }
        path = paths.join("\n");
      } else if (app.clients && app.clients.length > 0) {
        var validClients = [];
        for (var k = 0; k < app.clients.length; k++) {
          var client = app.clients[k];
          var include = true;

          if (app.id === "discord") {
            include = TemplateProcessor.isDiscordClientEnabled(client.name);
          } else if (app.id === "code") {
            // For code clients, resolve all theme paths dynamically (version-independent)
            if (TemplateProcessor.isCodeClientEnabled(client.name)) {
              var resolvedPaths = TemplateRegistry.resolvedCodeClientPaths(client.name);
              for (var p = 0; p < resolvedPaths.length; p++) {
                validClients.push(resolvedPaths[p]);
              }
            }
            continue;
          }

          if (include) {
            if (client.path)
              validClients.push(client.path);
          }
        }

        if (validClients.length > 0) {
          path = validClients.join("\n");
        } else {
          path = I18n.tr("panels.color-scheme.templates-none-detected");
        }
      }

      templates.push({
                       "id": app.id,
                       "name": app.name,
                       "category": app.category || "misc",
                       "tooltip": getDesc(path)
                     });
    }

    // Sort alphabetically by name
    templates.sort((a, b) => a.name.localeCompare(b.name));

    return templates;
  }

  // Category filter
  property string selectedCategory: ""

  // Build available categories dynamically
  readonly property var availableCategories: {
    var cats = {};
    for (var i = 0; i < allTemplates.length; i++) {
      cats[allTemplates[i].category] = true;
    }
    return Object.keys(cats).sort();
  }

  // Filter toggle
  property bool showOnlyActive: false

  // Filtered templates based on category, search, and toggle
  property string searchText: ""
  readonly property var filteredTemplates: {
    var result = allTemplates;

    // Filter by category first (unless searching)
    if (selectedCategory !== "" && searchText.trim() === "") {
      result = result.filter(t => t.category === selectedCategory);
    }

    // Search overrides category filter
    if (searchText.trim() !== "") {
      var query = searchText.toLowerCase().trim();
      result = result.filter(t => t.name.toLowerCase().includes(query));
    }

    // Filter by active if enabled (and not searching)
    if (showOnlyActive && searchText.trim() === "") {
      result = result.filter(t => isTemplateActive(t.id));
    }

    return result;
  }

  // Check if a template is active
  function isTemplateActive(templateId) {
    for (var i = 0; i < Settings.data.templates.activeTemplates.length; i++) {
      if (Settings.data.templates.activeTemplates[i].id === templateId) {
        return true;
      }
    }
    return false;
  }

  // Toggle a template on/off
  function toggleTemplate(templateId) {
    var current = Settings.data.templates.activeTemplates.slice();
    var existingIndex = -1;

    for (var i = 0; i < current.length; i++) {
      if (current[i].id === templateId) {
        existingIndex = i;
        break;
      }
    }

    if (existingIndex >= 0) {
      // Remove it
      current.splice(existingIndex, 1);
    } else {
      // Add it
      current.push({
                     "id": templateId,
                     "enabled": true
                   });
    }

    Settings.data.templates.activeTemplates = current;
    AppThemeService.generate();

    // Clear search context on interaction to return to filtered view
    if (searchText !== "") {
      searchText = "";
    }
  }

  NText {
    text: I18n.tr("panels.color-scheme.templates-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Category filter chips
  NTagFilter {
    tags: root.availableCategories
    selectedTag: root.selectedCategory
    onSelectedTagChanged: root.selectedCategory = selectedTag
    label: I18n.tr("panels.color-scheme.templates-filter-label")
    description: I18n.tr("panels.color-scheme.templates-filter-description")
    expanded: true
  }

  // Search/filter input row
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NTextInput {
      Layout.fillWidth: true
      placeholderText: I18n.tr("placeholders.search")
      text: root.searchText
      onTextChanged: root.searchText = text
    }

    NIconButton {
      icon: "filter"
      tooltipText: root.showOnlyActive ? I18n.tr("actions.show-all") : I18n.tr("actions.show-active-only")

      colorBg: root.showOnlyActive ? Color.mPrimary : Color.mSurface
      colorFg: root.showOnlyActive ? Color.mOnPrimary : Color.mOnSurface

      onClicked: root.showOnlyActive = !root.showOnlyActive
    }
  }

  // Chip grid - uniform columns
  GridLayout {
    Layout.fillWidth: true
    columns: 4
    columnSpacing: Style.marginS
    rowSpacing: Style.marginS

    Repeater {
      model: filteredTemplates

      Rectangle {
        id: chip
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Style.baseWidgetSize * 0.9)
        radius: Style.iRadiusM
        color: chipMouse.containsMouse ? Color.mHover : (isActive ? Color.mPrimary : Color.mSurface)
        border.color: isActive ? Color.mPrimary : Color.mOutline
        border.width: Style.borderS

        required property int index
        required property var modelData
        readonly property bool isActive: root.isTemplateActive(modelData.id)

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        NText {
          id: chipText
          anchors.centerIn: parent
          width: parent.width - Style.marginL * 2
          text: chip.modelData.name
          pointSize: Style.fontSizeS
          color: chipMouse.containsMouse ? Color.mOnHover : (isActive ? Color.mOnPrimary : Color.mOnSurface)
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: root.toggleTemplate(chip.modelData.id)
          onEntered: {
            if (chip.modelData.tooltip) {
              TooltipService.show(chip, chip.modelData.tooltip, "auto");
            }
          }
          onExited: {
            TooltipService.hide();
          }
        }
      }
    }
  }

  // No results message
  NText {
    visible: filteredTemplates.length === 0 && searchText.trim() !== ""
    text: I18n.tr("common.no-results")
    color: Color.mOnSurfaceVariant
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
  }

  // User templates checkbox
  NCheckbox {
    label: I18n.tr("panels.color-scheme.templates-misc-user-templates-label")
    description: I18n.tr("panels.color-scheme.templates-misc-user-templates-description")
    checked: Settings.data.templates.enableUserTheming
    onToggled: checked => {
                 Settings.data.templates.enableUserTheming = checked;
                 if (checked) {
                   TemplateRegistry.writeUserTemplatesToml();
                 }
                 AppThemeService.generate();
               }
  }
}
