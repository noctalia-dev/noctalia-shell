#include "shell/settings/settings_window.h"

#include "compositors/compositor_detect.h"
#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "shell/settings/settings_content.h"
#include "shell/settings/settings_entity_editor.h"
#include "shell/settings/settings_registry.h"
#include "shell/settings/settings_sidebar.h"
#include "theme/community_palettes.h"
#include "theme/community_templates.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/context_menu.h"
#include "ui/controls/context_menu_popup.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select.h"
#include "ui/controls/spacer.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/toplevel_surface.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

  constexpr Logger kLog("settings");
  constexpr std::int32_t kActionSupportReport = 1;
  constexpr std::int32_t kActionFlattenedConfig = 2;

  std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ColorSpec& color, bool bold = false) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(fontSize);
    label->setColor(color);
    label->setBold(bold);
    label->setStableBaseline(true);
    return label;
  }

  std::vector<std::string> sectionKeys(const std::vector<settings::SettingEntry>& entries) {
    std::vector<std::string> sections;
    for (const auto& entry : entries) {
      if (entry.section == "bar") {
        continue;
      }
      if (std::find(sections.begin(), sections.end(), entry.section) == sections.end()) {
        sections.push_back(entry.section);
      }
    }
    return sections;
  }

  bool containsPath(const std::vector<std::vector<std::string>>& paths, const std::vector<std::string>& path) {
    return std::find(paths.begin(), paths.end(), path) != paths.end();
  }

  bool settingEntryBelongsToPage(const settings::SettingEntry& entry, std::string_view selectedSection,
                                 std::string_view selectedBarName, std::string_view selectedMonitorOverride) {
    if (selectedSection != "bar") {
      return entry.section == selectedSection;
    }

    if (entry.section != "bar" || entry.path.size() < 2 || entry.path[0] != "bar" || entry.path[1] != selectedBarName) {
      return false;
    }

    const bool entryIsMonitorOverride = entry.path.size() >= 5 && entry.path[2] == "monitor";
    if (selectedMonitorOverride.empty()) {
      return !entryIsMonitorOverride;
    }
    return entryIsMonitorOverride && entry.path[3] == selectedMonitorOverride;
  }

  std::string pageScopeKey(std::string_view selectedSection, std::string_view selectedBarName,
                           std::string_view selectedMonitorOverride) {
    if (selectedSection != "bar") {
      return std::string(selectedSection);
    }
    std::string key = "bar:" + std::string(selectedBarName);
    if (!selectedMonitorOverride.empty()) {
      key += ":monitor:" + std::string(selectedMonitorOverride);
    }
    return key;
  }

} // namespace

SettingsWindow::~SettingsWindow() = default;

void SettingsWindow::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
  m_showAdvanced = m_config != nullptr ? m_config->config().shell.settingsShowAdvanced : false;
}

float SettingsWindow::uiScale() const {
  if (m_config == nullptr) {
    return 1.0f;
  }
  return std::max(0.1f, m_config->config().shell.uiScale);
}

void SettingsWindow::open() {
  if (m_wayland == nullptr || m_renderContext == nullptr || !m_wayland->hasXdgShell()) {
    return;
  }
  if (isOpen()) {
    m_wayland->activateSurface(m_surface->wlSurface());
    return;
  }

  m_showAdvanced = m_config != nullptr ? m_config->config().shell.settingsShowAdvanced : false;

  wl_output* output = m_wayland->lastPointerOutput();
  if (output == nullptr) {
    const auto& outs = m_wayland->outputs();
    if (!outs.empty() && outs.front().output != nullptr) {
      output = outs.front().output;
    }
  }
  m_output = output;

  m_surface = std::make_unique<ToplevelSurface>(*m_wayland);
  m_surface->setRenderContext(m_renderContext);
  m_surface->setAnimationManager(&m_animations);

  m_surface->setClosedCallback([this]() { destroyWindow(); });

  m_surface->setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) {
    if (m_surface != nullptr) {
      m_surface->requestLayout();
    }
  });

  m_surface->setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });

  m_surface->setUpdateCallback([]() {});

  const float scale = uiScale();
  const std::uint32_t w = static_cast<std::uint32_t>(std::round(900.0f * scale));
  const std::uint32_t h = static_cast<std::uint32_t>(std::round(600.0f * scale));
  const std::uint32_t minW = static_cast<std::uint32_t>(std::round(800.0f * scale));
  const std::uint32_t minH = static_cast<std::uint32_t>(std::round(500.0f * scale));

  ToplevelSurfaceConfig cfg{
      .width = std::max<std::uint32_t>(1, w),
      .height = std::max<std::uint32_t>(1, h),
      .minWidth = minW,
      .minHeight = minH,
      .title = i18n::tr("settings.window.native-title"),
      .appId = "dev.noctalia.Noctalia.Settings",
  };

  if (!m_surface->initialize(output, cfg)) {
    kLog.warn("settings: failed to create toplevel surface");
    m_surface.reset();
    return;
  }
  m_pointerInside = false;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
}

void SettingsWindow::close() {
  if (!isOpen()) {
    return;
  }
  destroyWindow();
}

void SettingsWindow::destroyWindow() {
  if (m_surface != nullptr) {
    m_inputDispatcher.setSceneRoot(nullptr);
    m_surface->setSceneRoot(nullptr);
  }
  m_mainContainer = nullptr;
  m_contentContainer = nullptr;
  m_actionsMenuButton = nullptr;
  if (m_actionsMenuPopup != nullptr) {
    m_actionsMenuPopup->close();
    m_actionsMenuPopup.reset();
  }
  m_sceneRoot.reset();
  m_surface.reset();
  m_pointerInside = false;
  m_output = nullptr;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
  m_settingsRegistry.clear();
  m_rebuildRequested = false;
  m_contentRebuildRequested = false;
  m_focusSearchOnRebuild = false;
  m_statusMessage.clear();
  m_statusIsError = false;
  m_creatingBarName.clear();
  m_renamingBarName.clear();
  m_pendingDeleteBarName.clear();
  m_creatingMonitorOverrideBarName.clear();
  m_creatingMonitorOverrideMatch.clear();
  m_renamingMonitorOverrideBarName.clear();
  m_renamingMonitorOverrideMatch.clear();
  m_pendingDeleteMonitorOverrideBarName.clear();
  m_pendingDeleteMonitorOverrideMatch.clear();
  m_pendingResetPageScope.clear();
}

void SettingsWindow::prepareFrame(bool /*needsUpdate*/, bool needsLayout) {
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }

  const auto width = m_surface->width();
  const auto height = m_surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(m_surface->renderTarget());
  m_renderContext->syncContentScale(m_surface->renderTarget());

  // Rebuild the entire scene only on first build or when something explicitly
  // requested it (config change, nav click, etc.). Pure size changes — which
  // niri delivers at refresh rate during window animations (slide-in on focus
  // return, workspace transitions) — should just re-layout the existing tree.
  // Rebuilding on every configure causes a 25+ rebuild storm during niri
  // animations, freezing input response for ~150 ms.
  const bool firstBuild = m_sceneRoot == nullptr;
  const bool sizeChanged = !firstBuild && (m_lastSceneWidth != width || m_lastSceneHeight != height);
  const bool needRebuild = firstBuild || m_rebuildRequested;

  if (needRebuild) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(width, height);
    m_lastSceneWidth = width;
    m_lastSceneHeight = height;
    m_rebuildRequested = false;
    m_contentRebuildRequested = false;
  } else if ((m_contentRebuildRequested || sizeChanged || needsLayout) && m_sceneRoot != nullptr) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    const float w = static_cast<float>(width);
    const float h = static_cast<float>(height);
    m_sceneRoot->setSize(w, h);
    if (m_panelBackground != nullptr) {
      m_panelBackground->setSize(w, h);
    }
    if (m_mainContainer != nullptr) {
      m_mainContainer->setSize(w, h);
    }
    if (m_contentRebuildRequested) {
      rebuildSettingsContent();
      m_contentRebuildRequested = false;
    }
    m_sceneRoot->layout(*m_renderContext);
    m_lastSceneWidth = width;
    m_lastSceneHeight = height;
  }
}

void SettingsWindow::requestSceneRebuild() {
  DeferredCall::callLater([this]() {
    if (m_surface == nullptr) {
      return;
    }
    m_rebuildRequested = true;
    m_contentRebuildRequested = false;
    m_surface->requestLayout();
  });
}

void SettingsWindow::requestContentRebuild() {
  DeferredCall::callLater([this]() {
    if (m_surface == nullptr) {
      return;
    }
    if (m_sceneRoot == nullptr || m_contentContainer == nullptr) {
      m_rebuildRequested = true;
    } else if (!m_rebuildRequested) {
      m_contentRebuildRequested = true;
    }
    m_surface->requestLayout();
  });
}

void SettingsWindow::clearStatusMessage() {
  m_statusMessage.clear();
  m_statusIsError = false;
}

void SettingsWindow::clearTransientSettingsState() {
  m_openWidgetPickerPath.clear();
  m_openSearchPickerPath.clear();
  m_editingWidgetName.clear();
  m_renamingWidgetName.clear();
  m_pendingDeleteWidgetName.clear();
  m_pendingDeleteWidgetSettingPath.clear();
  m_creatingWidgetType.clear();
  m_creatingBarName.clear();
  m_renamingBarName.clear();
  m_pendingDeleteBarName.clear();
  m_creatingMonitorOverrideBarName.clear();
  m_creatingMonitorOverrideMatch.clear();
  m_renamingMonitorOverrideBarName.clear();
  m_renamingMonitorOverrideMatch.clear();
  m_pendingDeleteMonitorOverrideBarName.clear();
  m_pendingDeleteMonitorOverrideMatch.clear();
  m_pendingResetPageScope.clear();
}

void SettingsWindow::openActionsMenu() {
  if (m_wayland == nullptr || m_renderContext == nullptr || m_surface == nullptr || m_actionsMenuButton == nullptr ||
      m_surface->xdgSurface() == nullptr) {
    return;
  }

  if (m_actionsMenuPopup == nullptr) {
    m_actionsMenuPopup = std::make_unique<ContextMenuPopup>(*m_wayland, *m_renderContext);
    m_actionsMenuPopup->setOnActivate([this](const ContextMenuControlEntry& entry) {
      switch (entry.id) {
      case kActionSupportReport:
        if (m_actionsMenuPopup != nullptr) {
          m_actionsMenuPopup->close();
        }
        DeferredCall::callLater([this]() { saveSupportReport(); });
        break;
      case kActionFlattenedConfig:
        if (m_actionsMenuPopup != nullptr) {
          m_actionsMenuPopup->close();
        }
        DeferredCall::callLater([this]() { saveFlattenedConfig(); });
        break;
      default:
        break;
      }
    });
  } else if (m_actionsMenuPopup->isOpen()) {
    m_actionsMenuPopup->close();
    return;
  }

  std::vector<ContextMenuControlEntry> entries;
  entries.push_back({.id = kActionSupportReport,
                     .label = i18n::tr("settings.window.support-report"),
                     .enabled = true,
                     .separator = false,
                     .hasSubmenu = false});
  entries.push_back({.id = kActionFlattenedConfig,
                     .label = i18n::tr("settings.window.flattened-config"),
                     .enabled = true,
                     .separator = false,
                     .hasSubmenu = false});

  float anchorAbsX = 0.0f;
  float anchorAbsY = 0.0f;
  Node::absolutePosition(m_actionsMenuButton, anchorAbsX, anchorAbsY);

  const float scale = uiScale();
  wl_output* output = m_wayland->lastPointerOutput();
  if (output == nullptr) {
    output = m_output;
  }

  m_actionsMenuPopup->openAsChild(
      std::move(entries), 220.0f * scale, 8, static_cast<std::int32_t>(anchorAbsX),
      static_cast<std::int32_t>(anchorAbsY), static_cast<std::int32_t>(m_actionsMenuButton->width()),
      static_cast<std::int32_t>(m_actionsMenuButton->height()), m_surface->xdgSurface(), output);
}

void SettingsWindow::saveSupportReport() {
  if (m_config == nullptr) {
    return;
  }

  FileDialogOptions options;
  options.mode = FileDialogMode::Save;
  options.defaultFilename = "noctalia-support-report.toml";
  options.title = i18n::tr("settings.window.support-report-title");
  options.extensions = {".toml"};

  const bool opened = FileDialog::open(std::move(options), [this](std::optional<std::filesystem::path> result) {
    if (!result.has_value() || m_config == nullptr) {
      return;
    }

    auto path = *result;
    if (path.extension().empty()) {
      path += ".toml";
    }

    std::ofstream out(path, std::ios::trunc);
    if (!out.is_open()) {
      m_statusMessage = i18n::tr("settings.errors.support-report");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }

    out << m_config->buildSupportReport();
    if (!out.good()) {
      m_statusMessage = i18n::tr("settings.errors.support-report");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }

    m_statusMessage = i18n::tr("settings.window.support-report-saved");
    m_statusIsError = false;
    requestSceneRebuild();
  });

  if (!opened) {
    m_statusMessage = i18n::tr("settings.errors.support-report");
    m_statusIsError = true;
    requestSceneRebuild();
  }
}

void SettingsWindow::saveFlattenedConfig() {
  if (m_config == nullptr) {
    return;
  }

  FileDialogOptions options;
  options.mode = FileDialogMode::Save;
  options.defaultFilename = "noctalia-flattened-config.toml";
  options.title = i18n::tr("settings.window.flattened-config-title");
  options.extensions = {".toml"};

  const bool opened = FileDialog::open(std::move(options), [this](std::optional<std::filesystem::path> result) {
    if (!result.has_value() || m_config == nullptr) {
      return;
    }

    auto path = *result;
    if (path.extension().empty()) {
      path += ".toml";
    }

    std::ofstream out(path, std::ios::trunc);
    if (!out.is_open()) {
      m_statusMessage = i18n::tr("settings.errors.flattened-config");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }

    out << m_config->buildFlattenedConfig();
    if (!out.good()) {
      m_statusMessage = i18n::tr("settings.errors.flattened-config");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }

    m_statusMessage = i18n::tr("settings.window.flattened-config-saved");
    m_statusIsError = false;
    requestSceneRebuild();
  });

  if (!opened) {
    m_statusMessage = i18n::tr("settings.errors.flattened-config");
    m_statusIsError = true;
    requestSceneRebuild();
  }
}

void SettingsWindow::setSettingOverride(std::vector<std::string> path, ConfigOverrideValue value) {
  DeferredCall::callLater([this, path = std::move(path), value = std::move(value)]() mutable {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->setOverride(path, std::move(value))) {
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.write");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::setSettingOverrides(
    std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides) {
  DeferredCall::callLater([this, overrides = std::move(overrides)]() mutable {
    if (m_config == nullptr) {
      return;
    }
    bool changed = false;
    bool failed = false;
    for (auto& [path, value] : overrides) {
      if (m_config->setOverride(path, std::move(value))) {
        changed = true;
      } else {
        failed = true;
      }
    }
    if (failed) {
      m_statusMessage = i18n::tr("settings.errors.batch-write");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }
    const bool hadStatus = !m_statusMessage.empty();
    m_statusMessage.clear();
    m_statusIsError = false;
    m_pendingResetPageScope.clear();
    if (changed || hadStatus) {
      requestSceneRebuild();
    }
  });
}

void SettingsWindow::clearSettingOverride(std::vector<std::string> path) {
  DeferredCall::callLater([this, path = std::move(path)]() mutable {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->clearOverride(path)) {
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.clear");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::clearSettingOverrides(std::vector<std::vector<std::string>> paths) {
  DeferredCall::callLater([this, paths = std::move(paths)]() mutable {
    if (m_config == nullptr || paths.empty()) {
      return;
    }

    bool changed = false;
    bool failed = false;
    for (const auto& path : paths) {
      if (m_config->clearOverride(path)) {
        changed = true;
      } else {
        failed = true;
      }
    }

    m_pendingResetPageScope.clear();
    if (failed) {
      m_statusMessage = i18n::tr("settings.errors.reset-page");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }

    m_statusMessage.clear();
    m_statusIsError = false;
    if (changed) {
      requestSceneRebuild();
    }
  });
}

void SettingsWindow::renameWidgetInstance(
    std::string oldName, std::string newName,
    std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> referenceOverrides) {
  DeferredCall::callLater([this, oldName = std::move(oldName), newName = std::move(newName),
                           referenceOverrides = std::move(referenceOverrides)]() mutable {
    if (m_config == nullptr) {
      return;
    }

    bool changed = m_config->renameOverrideTable({"widget", oldName}, {"widget", newName});
    if (!changed) {
      m_statusMessage = i18n::tr("settings.errors.widget.rename");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }
    bool failed = false;
    for (auto& [path, value] : referenceOverrides) {
      if (m_config->setOverride(path, std::move(value))) {
        changed = true;
      } else {
        failed = true;
      }
    }
    if (failed) {
      m_statusMessage = i18n::tr("settings.errors.batch-write");
      m_statusIsError = true;
      requestSceneRebuild();
      return;
    }
    m_statusMessage.clear();
    m_statusIsError = false;
    m_pendingResetPageScope.clear();
    if (changed) {
      requestSceneRebuild();
    }
  });
}

void SettingsWindow::createBar(std::string name) {
  DeferredCall::callLater([this, name = std::move(name)]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->createBarOverride(name)) {
      m_selectedSection = "bar";
      m_selectedBarName = name;
      m_selectedMonitorOverride.clear();
      m_creatingBarName.clear();
      m_renamingBarName.clear();
      m_pendingDeleteBarName.clear();
      m_creatingMonitorOverrideBarName.clear();
      m_creatingMonitorOverrideMatch.clear();
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_contentScrollState.offset = 0.0f;
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.bar.create");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::renameBar(std::string oldName, std::string newName) {
  DeferredCall::callLater([this, oldName = std::move(oldName), newName = std::move(newName)]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->renameBarOverride(oldName, newName)) {
      if (m_selectedBarName == oldName) {
        m_selectedBarName = newName;
      }
      m_selectedMonitorOverride.clear();
      m_renamingBarName.clear();
      m_pendingDeleteBarName.clear();
      m_creatingMonitorOverrideBarName.clear();
      m_creatingMonitorOverrideMatch.clear();
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_contentScrollState.offset = 0.0f;
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.bar.rename");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::deleteBar(std::string name) {
  DeferredCall::callLater([this, name = std::move(name)]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->deleteBarOverride(name)) {
      if (m_selectedBarName == name) {
        m_selectedBarName.clear();
        m_selectedMonitorOverride.clear();
        m_contentScrollState.offset = 0.0f;
      }
      m_renamingBarName.clear();
      m_pendingDeleteBarName.clear();
      m_creatingMonitorOverrideBarName.clear();
      m_creatingMonitorOverrideMatch.clear();
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.bar.delete");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::moveBar(std::string name, int direction) {
  DeferredCall::callLater([this, name = std::move(name), direction]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->moveBarOverride(name, direction)) {
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.bar.move");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::createMonitorOverride(std::string barName, std::string match) {
  DeferredCall::callLater([this, barName = std::move(barName), match = std::move(match)]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->createMonitorOverride(barName, match)) {
      m_selectedSection = "bar";
      m_selectedBarName = barName;
      m_selectedMonitorOverride = match;
      m_creatingMonitorOverrideBarName.clear();
      m_creatingMonitorOverrideMatch.clear();
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_contentScrollState.offset = 0.0f;
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.monitor-override.create");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::renameMonitorOverride(std::string barName, std::string oldMatch, std::string newMatch) {
  DeferredCall::callLater(
      [this, barName = std::move(barName), oldMatch = std::move(oldMatch), newMatch = std::move(newMatch)]() {
        if (m_config == nullptr) {
          return;
        }
        if (m_config->renameMonitorOverride(barName, oldMatch, newMatch)) {
          if (m_selectedBarName == barName && m_selectedMonitorOverride == oldMatch) {
            m_selectedMonitorOverride = newMatch;
          }
          m_renamingMonitorOverrideBarName.clear();
          m_renamingMonitorOverrideMatch.clear();
          m_pendingDeleteMonitorOverrideBarName.clear();
          m_pendingDeleteMonitorOverrideMatch.clear();
          m_contentScrollState.offset = 0.0f;
          m_statusMessage.clear();
          m_statusIsError = false;
          m_pendingResetPageScope.clear();
          requestSceneRebuild();
          return;
        }
        m_statusMessage = i18n::tr("settings.errors.monitor-override.rename");
        m_statusIsError = true;
        requestSceneRebuild();
      });
}

void SettingsWindow::deleteMonitorOverride(std::string barName, std::string match) {
  DeferredCall::callLater([this, barName = std::move(barName), match = std::move(match)]() {
    if (m_config == nullptr) {
      return;
    }
    if (m_config->deleteMonitorOverride(barName, match)) {
      if (m_selectedBarName == barName && m_selectedMonitorOverride == match) {
        m_selectedMonitorOverride.clear();
        m_contentScrollState.offset = 0.0f;
      }
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_statusMessage.clear();
      m_statusIsError = false;
      m_pendingResetPageScope.clear();
      requestSceneRebuild();
      return;
    }
    m_statusMessage = i18n::tr("settings.errors.monitor-override.delete");
    m_statusIsError = true;
    requestSceneRebuild();
  });
}

void SettingsWindow::rebuildSettingsContent() {
  uiAssertNotRendering("SettingsWindow::rebuildSettingsContent");
  if (m_contentContainer == nullptr) {
    return;
  }

  while (!m_contentContainer->children().empty()) {
    m_contentContainer->removeChild(m_contentContainer->children().back().get());
  }

  const float scale = uiScale();
  const Config fallbackCfg{};
  const Config& cfg = m_config != nullptr ? m_config->config() : fallbackCfg;
  const BarConfig* selectedBar = settings::findBar(cfg, m_selectedBarName);
  const BarMonitorOverride* selectedMonitorOverride = nullptr;
  if (selectedBar != nullptr && !m_selectedMonitorOverride.empty()) {
    selectedMonitorOverride = settings::findMonitorOverride(*selectedBar, m_selectedMonitorOverride);
  }

  const auto requestRebuild = [this]() { requestSceneRebuild(); };
  const auto requestContent = [this]() { requestContentRebuild(); };
  const auto setOverride = [this](std::vector<std::string> path, ConfigOverrideValue value) {
    setSettingOverride(std::move(path), std::move(value));
  };
  const auto setOverrides = [this](std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides) {
    setSettingOverrides(std::move(overrides));
  };
  const auto clearOverride = [this](std::vector<std::string> path) { clearSettingOverride(std::move(path)); };
  const auto renameWidget =
      [this](std::string oldName, std::string newName,
             std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> referenceOverrides) {
        renameWidgetInstance(std::move(oldName), std::move(newName), std::move(referenceOverrides));
      };

  m_contentContainer->setDirection(FlexDirection::Vertical);
  m_contentContainer->setAlign(FlexAlign::Stretch);
  m_contentContainer->setGap(Style::spaceMd * scale);

  settings::addSettingsEntityManagement(
      *m_contentContainer,
      settings::SettingsEntityEditorContext{
          .config = cfg,
          .configService = m_config,
          .scale = scale,
          .searchQuery = m_searchQuery,
          .selectedSection = m_selectedSection,
          .selectedBar = selectedBar,
          .selectedMonitorOverride = selectedMonitorOverride,
          .renamingBarName = m_renamingBarName,
          .pendingDeleteBarName = m_pendingDeleteBarName,
          .renamingMonitorOverrideBarName = m_renamingMonitorOverrideBarName,
          .renamingMonitorOverrideMatch = m_renamingMonitorOverrideMatch,
          .pendingDeleteMonitorOverrideBarName = m_pendingDeleteMonitorOverrideBarName,
          .pendingDeleteMonitorOverrideMatch = m_pendingDeleteMonitorOverrideMatch,
          .requestRebuild = requestRebuild,
          .renameBar = [this](std::string oldName,
                              std::string newName) { renameBar(std::move(oldName), std::move(newName)); },
          .deleteBar = [this](std::string name) { deleteBar(std::move(name)); },
          .moveBar = [this](std::string name, int direction) { moveBar(std::move(name), direction); },
          .renameMonitorOverride =
              [this](std::string barName, std::string oldMatch, std::string newMatch) {
                renameMonitorOverride(std::move(barName), std::move(oldMatch), std::move(newMatch));
              },
          .deleteMonitorOverride =
              [this](std::string barName, std::string match) {
                deleteMonitorOverride(std::move(barName), std::move(match));
              },
      });

  settings::addSettingsContentSections(*m_contentContainer, m_settingsRegistry,
                                       settings::SettingsContentContext{
                                           .config = cfg,
                                           .configService = m_config,
                                           .scale = scale,
                                           .searchQuery = m_searchQuery,
                                           .selectedSection = m_selectedSection,
                                           .selectedBar = selectedBar,
                                           .selectedMonitorOverride = selectedMonitorOverride,
                                           .showAdvanced = m_showAdvanced,
                                           .showOverriddenOnly = m_showOverriddenOnly,
                                           .openWidgetPickerPath = m_openWidgetPickerPath,
                                           .openSearchPickerPath = m_openSearchPickerPath,
                                           .editingWidgetName = m_editingWidgetName,
                                           .pendingDeleteWidgetName = m_pendingDeleteWidgetName,
                                           .pendingDeleteWidgetSettingPath = m_pendingDeleteWidgetSettingPath,
                                           .renamingWidgetName = m_renamingWidgetName,
                                           .creatingWidgetType = m_creatingWidgetType,
                                           .requestRebuild = requestRebuild,
                                           .requestContentRebuild = requestContent,
                                           .resetContentScroll = [this]() { m_contentScrollState.offset = 0.0f; },
                                           .focusArea = [this](InputArea* area) { m_inputDispatcher.setFocus(area); },
                                           .setOverride = setOverride,
                                           .setOverrides = setOverrides,
                                           .clearOverride = clearOverride,
                                           .renameWidgetInstance = renameWidget,
                                       });
}

void SettingsWindow::buildScene(std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("SettingsWindow::buildScene");
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }

  const float w = static_cast<float>(width);
  const float h = static_cast<float>(height);
  const float scale = uiScale();
  m_actionsMenuButton = nullptr;
  const Config fallbackCfg{};
  const Config& cfg = m_config != nullptr ? m_config->config() : fallbackCfg;
  const auto availableBars = settings::barNames(cfg);
  if (availableBars.empty()) {
    m_selectedBarName.clear();
  } else if (settings::findBar(cfg, m_selectedBarName) == nullptr) {
    m_selectedBarName = availableBars.front();
  }
  const BarConfig* selectedBar = settings::findBar(cfg, m_selectedBarName);
  const BarMonitorOverride* selectedMonitorOverride = nullptr;
  if (selectedBar != nullptr && !m_selectedMonitorOverride.empty()) {
    selectedMonitorOverride = settings::findMonitorOverride(*selectedBar, m_selectedMonitorOverride);
    if (selectedMonitorOverride == nullptr) {
      m_selectedMonitorOverride.clear();
    }
  }
  settings::RegistryEnvironment env;
  env.niriBackdropSupported = (m_wayland != nullptr && compositors::isNiri());
  for (const auto& paletteInfo : noctalia::theme::availableCommunityPalettes()) {
    env.communityPalettes.push_back(settings::SelectOption{paletteInfo.name, paletteInfo.name});
  }
  for (const auto& t : noctalia::theme::CommunityTemplateService::availableTemplates()) {
    env.communityTemplates.push_back(settings::SelectOption{t.id, t.displayName});
  }
  if (m_wayland != nullptr) {
    for (const auto& output : m_wayland->outputs()) {
      if (output.output == nullptr || output.connectorName.empty()) {
        continue;
      }
      std::string label = output.connectorName;
      if (!output.description.empty()) {
        label += " (" + output.description + ")";
      }
      env.availableOutputs.push_back(settings::SelectOption{output.connectorName, std::move(label)});
    }
  }
  m_settingsRegistry = settings::buildSettingsRegistry(cfg, selectedBar, selectedMonitorOverride, env);

  if (m_openDesktopWidgetEditor) {
    auto it = std::find_if(m_settingsRegistry.begin(), m_settingsRegistry.end(), [](const settings::SettingEntry& e) {
      return e.section == "desktop" && e.group == "widgets";
    });
    if (it != m_settingsRegistry.end()) {
      ++it;
    }
    settings::SettingEntry btn{
        .section = "desktop",
        .group = "widgets",
        .title = i18n::tr("settings.schema.desktop.widgets-editor.label"),
        .subtitle = i18n::tr("settings.schema.desktop.widgets-editor.description"),
        .path = {},
        .control = settings::ButtonSetting{i18n::tr("settings.schema.desktop.widgets-editor.button"),
                                           m_openDesktopWidgetEditor},
        .searchText = "desktop widgets editor edit",
    };
    m_settingsRegistry.insert(it, std::move(btn));
  }

  const auto sections = sectionKeys(m_settingsRegistry);
  if (m_selectedSection == "bar" && selectedBar == nullptr) {
    m_selectedSection.clear();
  } else if (m_selectedSection != "bar" && !m_selectedSection.empty() &&
             std::find(sections.begin(), sections.end(), m_selectedSection) == sections.end()) {
    m_selectedSection.clear();
  }
  if (m_selectedSection.empty()) {
    m_selectedSection = std::find(sections.begin(), sections.end(), "appearance") != sections.end()
                            ? std::string("appearance")
                            : (!sections.empty() ? sections.front() : std::string{});
  }
  const std::string resetPageScope = pageScopeKey(m_selectedSection, m_selectedBarName, m_selectedMonitorOverride);
  std::vector<std::vector<std::string>> resetPagePaths;
  if (m_config != nullptr) {
    for (const auto& entry : m_settingsRegistry) {
      if (settingEntryBelongsToPage(entry, m_selectedSection, m_selectedBarName, m_selectedMonitorOverride) &&
          m_config->hasOverride(entry.path) && !containsPath(resetPagePaths, entry.path)) {
        resetPagePaths.push_back(entry.path);
      }
    }
  }
  if (m_pendingResetPageScope != resetPageScope) {
    m_pendingResetPageScope.clear();
  }

  m_inputDispatcher.setSceneRoot(nullptr);
  m_mainContainer = nullptr;
  m_panelBackground = nullptr;
  m_contentContainer = nullptr;
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setSize(w, h);
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  bg->setRadius(0.0f);
  bg->setBorder(clearColor(), 0);
  bg->setPosition(0.0f, 0.0f);
  bg->setSize(w, h);
  m_panelBackground = static_cast<Box*>(m_sceneRoot->addChild(std::move(bg)));

  auto main = std::make_unique<Flex>();
  main->setDirection(FlexDirection::Vertical);
  main->setAlign(FlexAlign::Stretch);
  main->setJustify(FlexJustify::Start);
  main->setGap(Style::spaceMd * scale);
  main->setPadding(Style::spaceLg * scale);
  main->setSize(w, h);

  const float bodyMaxWidth = 1024.0f * scale;
  const auto centeredRow = [&](std::unique_ptr<Flex> child) {
    child->setFlexGrow(1.0f);
    child->setMaxWidth(bodyMaxWidth);
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Stretch);
    row->setJustify(FlexJustify::Center);
    row->addChild(std::move(child));
    return row;
  };

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setJustify(FlexJustify::SpaceBetween);
  header->setGap(Style::spaceSm * scale);

  auto headerTitle = std::make_unique<Label>();
  headerTitle->setText(i18n::tr("settings.window.title"));
  headerTitle->setBold(true);
  headerTitle->setFontSize(Style::fontSizeTitle * scale);
  headerTitle->setColor(colorSpecFromRole(ColorRole::OnSurface));
  headerTitle->setFlexGrow(1.0f);
  headerTitle->setStableBaseline(true);
  header->addChild(std::move(headerTitle));

  auto actionsMenuBtn = std::make_unique<Button>();
  actionsMenuBtn->setGlyph("more-vertical");
  actionsMenuBtn->setVariant(ButtonVariant::Ghost);
  actionsMenuBtn->setGlyphSize(Style::fontSizeBody * scale);
  actionsMenuBtn->setMinWidth(Style::controlHeightSm * scale);
  actionsMenuBtn->setMinHeight(Style::controlHeightSm * scale);
  actionsMenuBtn->setPadding(Style::spaceXs * scale);
  actionsMenuBtn->setRadius(Style::radiusMd * scale);
  actionsMenuBtn->setOnClick([this]() { openActionsMenu(); });
  m_actionsMenuButton = actionsMenuBtn.get();
  header->addChild(std::move(actionsMenuBtn));

  auto closeBtn = std::make_unique<Button>();
  closeBtn->setGlyph("close");
  closeBtn->setVariant(ButtonVariant::Default);
  closeBtn->setGlyphSize(Style::fontSizeBody * scale);
  closeBtn->setMinWidth(Style::controlHeightSm * scale);
  closeBtn->setMinHeight(Style::controlHeightSm * scale);
  closeBtn->setPadding(Style::spaceXs * scale);
  closeBtn->setRadius(Style::radiusMd * scale);
  closeBtn->setOnClick([this]() { close(); });
  header->addChild(std::move(closeBtn));

  main->addChild(centeredRow(std::move(header)));

  const auto requestRebuild = [this]() { requestSceneRebuild(); };
  const auto clearStatus = [this]() { clearStatusMessage(); };
  const auto clearOverrides = [this](std::vector<std::vector<std::string>> paths) {
    clearSettingOverrides(std::move(paths));
  };
  const auto createBar = [this](std::string name) { this->createBar(std::move(name)); };
  const auto createMonitorOverride = [this](std::string barName, std::string match) {
    this->createMonitorOverride(std::move(barName), std::move(match));
  };

  auto filters = std::make_unique<Flex>();
  filters->setDirection(FlexDirection::Horizontal);
  filters->setAlign(FlexAlign::Center);
  filters->setJustify(FlexJustify::Start);
  filters->setGap(Style::spaceMd * scale);

  auto searchInput = std::make_unique<Input>();
  searchInput->setPlaceholder(i18n::tr("settings.window.search-placeholder"));
  searchInput->setValue(m_searchQuery);
  searchInput->setFontSize(Style::fontSizeBody * scale);
  searchInput->setControlHeight(Style::controlHeight * scale);
  searchInput->setHorizontalPadding(Style::spaceSm * scale);
  searchInput->setClearButtonEnabled(true);
  searchInput->setSize(320.0f * scale, Style::controlHeight * scale);
  Input* searchInputPtr = searchInput.get();
  searchInput->setOnChange([this](const std::string& value) {
    const bool wasSearchActive = !m_searchQuery.empty();
    m_searchQuery = value;
    const bool searchActiveChanged = wasSearchActive != !m_searchQuery.empty();
    const bool hadPendingReset = !m_pendingResetPageScope.empty();
    m_pendingResetPageScope.clear();
    m_openSearchPickerPath.clear();
    if (hadPendingReset || searchActiveChanged) {
      m_focusSearchOnRebuild = true;
      requestSceneRebuild();
    } else {
      requestContentRebuild();
    }
  });
  filters->addChild(std::move(searchInput));
  filters->addChild(std::make_unique<Spacer>());

  auto advancedLabel = makeLabel(i18n::tr("settings.badges.advanced"), Style::fontSizeBody * scale,
                                 colorSpecFromRole(ColorRole::OnSurfaceVariant), false);
  filters->addChild(std::move(advancedLabel));

  auto advancedToggle = std::make_unique<Toggle>();
  advancedToggle->setScale(scale);
  advancedToggle->setChecked(m_showAdvanced);
  advancedToggle->setOnChange([this, requestRebuild](bool value) {
    if (m_config != nullptr && !m_config->setOverride({"shell", "settings_show_advanced"}, value)) {
      m_statusMessage = i18n::tr("settings.errors.write");
      m_statusIsError = true;
      requestRebuild();
      return;
    }
    m_showAdvanced = value;
    const bool hadPendingReset = !m_pendingResetPageScope.empty();
    m_pendingResetPageScope.clear();
    if (hadPendingReset) {
      requestRebuild();
    } else {
      requestContentRebuild();
    }
  });
  filters->addChild(std::move(advancedToggle));

  auto overriddenLabel = makeLabel(i18n::tr("settings.window.filter-modified"), Style::fontSizeBody * scale,
                                   colorSpecFromRole(ColorRole::OnSurfaceVariant), false);
  filters->addChild(std::move(overriddenLabel));

  auto overriddenToggle = std::make_unique<Toggle>();
  overriddenToggle->setScale(scale);
  overriddenToggle->setChecked(m_showOverriddenOnly);
  overriddenToggle->setOnChange([this, requestRebuild](bool value) {
    m_showOverriddenOnly = value;
    const bool hadPendingReset = !m_pendingResetPageScope.empty();
    m_pendingResetPageScope.clear();
    if (hadPendingReset) {
      requestRebuild();
    } else {
      requestContentRebuild();
    }
  });
  filters->addChild(std::move(overriddenToggle));

  if (!resetPagePaths.empty()) {
    const bool pendingReset = m_pendingResetPageScope == resetPageScope;
    auto resetPageBtn = std::make_unique<Button>();
    resetPageBtn->setText(pendingReset ? i18n::tr("settings.window.reset-page-confirm")
                                       : i18n::tr("settings.window.reset-page"));
    resetPageBtn->setVariant(pendingReset ? ButtonVariant::Destructive : ButtonVariant::Ghost);
    resetPageBtn->setFontSize(Style::fontSizeCaption * scale);
    resetPageBtn->setMinHeight(Style::controlHeightSm * scale);
    resetPageBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
    resetPageBtn->setRadius(Style::radiusMd * scale);
    resetPageBtn->setOnClick(
        [this, resetPageScope, resetPagePaths, requestRebuild, clearOverrides, pendingReset]() mutable {
          if (!pendingReset) {
            m_pendingResetPageScope = resetPageScope;
            requestRebuild();
            return;
          }
          clearOverrides(std::move(resetPagePaths));
        });
    filters->addChild(std::move(resetPageBtn));
  }

  main->addChild(centeredRow(std::move(filters)));

  if (!m_statusMessage.empty()) {
    auto status = std::make_unique<Flex>();
    status->setDirection(FlexDirection::Horizontal);
    status->setAlign(FlexAlign::Center);
    status->setGap(Style::spaceSm * scale);
    status->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
    status->setRadius(Style::radiusMd * scale);
    status->setFill(colorSpecFromRole(m_statusIsError ? ColorRole::Error : ColorRole::Secondary, 0.14f));
    status->setBorder(colorSpecFromRole(m_statusIsError ? ColorRole::Error : ColorRole::Secondary, 0.45f),
                      Style::borderWidth);

    auto message = makeLabel(m_statusMessage, Style::fontSizeCaption * scale,
                             colorSpecFromRole(m_statusIsError ? ColorRole::Error : ColorRole::Secondary), true);
    message->setFlexGrow(1.0f);
    status->addChild(std::move(message));

    auto dismiss = std::make_unique<Button>();
    dismiss->setGlyph("close");
    dismiss->setVariant(ButtonVariant::Ghost);
    dismiss->setGlyphSize(Style::fontSizeCaption * scale);
    dismiss->setMinWidth(Style::controlHeightSm * scale);
    dismiss->setMinHeight(Style::controlHeightSm * scale);
    dismiss->setPadding(Style::spaceXs * scale);
    dismiss->setRadius(Style::radiusSm * scale);
    dismiss->setOnClick([clearStatus, requestRebuild]() {
      clearStatus();
      requestRebuild();
    });
    status->addChild(std::move(dismiss));

    main->addChild(centeredRow(std::move(status)));
  }

  const auto clearTransientSettingsState = [this]() { this->clearTransientSettingsState(); };
  const auto clearSearchQuery = [this]() { m_searchQuery.clear(); };

  auto body = std::make_unique<Flex>();
  body->setDirection(FlexDirection::Horizontal);
  body->setAlign(FlexAlign::Stretch);
  body->setGap(Style::spaceMd * scale);

  auto sidebar = settings::buildSettingsSidebar(settings::SettingsSidebarContext{
      .config = cfg,
      .sections = sections,
      .availableBars = availableBars,
      .scale = scale,
      .globalSearchActive = !m_searchQuery.empty(),
      .sidebarScrollState = m_sidebarScrollState,
      .contentScrollState = m_contentScrollState,
      .selectedSection = m_selectedSection,
      .selectedBarName = m_selectedBarName,
      .selectedMonitorOverride = m_selectedMonitorOverride,
      .creatingBarName = m_creatingBarName,
      .creatingMonitorOverrideBarName = m_creatingMonitorOverrideBarName,
      .creatingMonitorOverrideMatch = m_creatingMonitorOverrideMatch,
      .clearTransientState = clearTransientSettingsState,
      .clearSearchQuery = clearSearchQuery,
      .requestRebuild = requestRebuild,
      .createBar = createBar,
      .createMonitorOverride = createMonitorOverride,
  });

  body->addChild(std::move(sidebar));

  auto scroll = std::make_unique<ScrollView>();
  scroll->bindState(&m_contentScrollState);
  scroll->setFlexGrow(1.0f);
  scroll->setScrollbarVisible(true);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(Style::spaceSm * scale);
  scroll->clearFill();
  scroll->clearBorder();
  auto* content = scroll->content();
  m_contentContainer = content;
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceMd * scale);
  rebuildSettingsContent();

  body->addChild(std::move(scroll));
  auto bodyRow = centeredRow(std::move(body));
  bodyRow->setFlexGrow(1.0f);
  main->addChild(std::move(bodyRow));

  if (m_focusSearchOnRebuild && searchInputPtr != nullptr && searchInputPtr->inputArea() != nullptr) {
    m_inputDispatcher.setFocus(searchInputPtr->inputArea());
    m_focusSearchOnRebuild = false;
  }

  main->setSize(w, h);
  main->layout(*m_renderContext);
  m_mainContainer = static_cast<Flex*>(m_sceneRoot->addChild(std::move(main)));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());
}

bool SettingsWindow::onPointerEvent(const PointerEvent& event) {
  if (!isOpen() || m_surface == nullptr) {
    return false;
  }

  if (m_actionsMenuPopup != nullptr && m_actionsMenuPopup->onPointerEvent(event)) {
    return true;
  }
  if (m_actionsMenuPopup != nullptr && m_actionsMenuPopup->isOpen() && event.type == PointerEvent::Type::Button &&
      event.state == 1) {
    m_actionsMenuPopup->close();
    return true;
  }

  wl_surface* const ws = m_surface->wlSurface();
  const bool onThis = (event.surface != nullptr && event.surface == ws);
  bool consumed = false;

  switch (event.type) {
  case PointerEvent::Type::Enter:
    if (onThis) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    }
    break;
  case PointerEvent::Type::Leave:
    if (onThis) {
      m_pointerInside = false;
      m_inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (onThis || m_pointerInside) {
      if (onThis) {
        m_pointerInside = true;
      }
      m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      consumed = m_pointerInside;
    }
    break;
  case PointerEvent::Type::Button: {
    const bool pressed = (event.state == 1);
    if (onThis || m_pointerInside) {
      if (onThis) {
        m_pointerInside = true;
      }
      if (pressed) {
        Select::handleGlobalPointerPress(m_inputDispatcher.hoveredArea());
      }
      m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                      pressed);
      consumed = m_pointerInside;
    }
    break;
  }
  case PointerEvent::Type::Axis:
    if (m_pointerInside) {
      m_inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                    event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                    event.axisLines);
      consumed = true;
    }
    break;
  }

  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }

  return consumed;
}

void SettingsWindow::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isOpen() || m_config == nullptr) {
    return;
  }
  const auto requestRebuild = [this]() {
    if (m_surface != nullptr) {
      m_rebuildRequested = true;
      m_surface->requestLayout();
    }
  };
  if (event.pressed && m_config->matchesKeybind(KeybindAction::Cancel, event.sym, event.modifiers)) {
    if (m_actionsMenuPopup != nullptr && m_actionsMenuPopup->isOpen()) {
      m_actionsMenuPopup->close();
      return;
    }
    if (!m_openWidgetPickerPath.empty() || !m_editingWidgetName.empty() || !m_creatingWidgetType.empty() ||
        !m_renamingWidgetName.empty() || !m_pendingDeleteWidgetName.empty() ||
        !m_pendingDeleteWidgetSettingPath.empty() || !m_creatingBarName.empty() || !m_renamingBarName.empty() ||
        !m_pendingDeleteBarName.empty() || !m_creatingMonitorOverrideBarName.empty() ||
        !m_renamingMonitorOverrideBarName.empty() || !m_pendingDeleteMonitorOverrideBarName.empty()) {
      m_openWidgetPickerPath.clear();
      m_editingWidgetName.clear();
      m_renamingWidgetName.clear();
      m_pendingDeleteWidgetName.clear();
      m_pendingDeleteWidgetSettingPath.clear();
      m_creatingWidgetType.clear();
      m_creatingBarName.clear();
      m_renamingBarName.clear();
      m_pendingDeleteBarName.clear();
      m_creatingMonitorOverrideBarName.clear();
      m_creatingMonitorOverrideMatch.clear();
      m_renamingMonitorOverrideBarName.clear();
      m_renamingMonitorOverrideMatch.clear();
      m_pendingDeleteMonitorOverrideBarName.clear();
      m_pendingDeleteMonitorOverrideMatch.clear();
      m_contentScrollState.offset = 0.0f;
      requestRebuild();
      return;
    }
    if (Select::closeAnyOpen()) {
      if (m_surface != nullptr) {
        m_surface->requestLayout();
      }
      return;
    }
  }
  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_sceneRoot != nullptr && m_surface != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }
}

void SettingsWindow::onThemeChanged() {
  if (isOpen()) {
    m_surface->requestRedraw();
  }
}

void SettingsWindow::onFontChanged() {
  if (isOpen()) {
    m_surface->requestLayout();
  }
}

void SettingsWindow::onExternalOptionsChanged() { requestSceneRebuild(); }
