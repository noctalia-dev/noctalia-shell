#include "shell/settings/settings_window.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "shell/settings/bar_widget_editor.h"
#include "shell/settings/settings_registry.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/slider.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <format>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace {

  constexpr Logger kLog("settings");

  std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ThemeColor& color, bool bold = false) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(fontSize);
    label->setColor(color);
    label->setBold(bold);
    return label;
  }

  std::optional<std::size_t> optionIndex(const std::vector<settings::SelectOption>& options, std::string_view value) {
    for (std::size_t i = 0; i < options.size(); ++i) {
      if (options[i].value == value) {
        return i;
      }
    }
    return std::nullopt;
  }

  std::vector<std::string> optionLabels(const std::vector<settings::SelectOption>& options) {
    std::vector<std::string> labels;
    labels.reserve(options.size());
    for (const auto& opt : options) {
      labels.push_back(opt.label);
    }
    return labels;
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

  std::string_view trimInput(std::string_view text) {
    const auto first = std::find_if_not(text.begin(), text.end(), [](unsigned char c) { return std::isspace(c) != 0; });
    const auto last =
        std::find_if_not(text.rbegin(), text.rend(), [](unsigned char c) { return std::isspace(c) != 0; }).base();
    if (first >= last) {
      return {};
    }
    return std::string_view(first, static_cast<std::size_t>(last - first));
  }

  bool isBlankInput(std::string_view text) { return trimInput(text).empty(); }

  std::optional<float> parseFloatInput(std::string_view text) {
    const auto trimmedView = trimInput(text);
    if (trimmedView.empty()) {
      return std::nullopt;
    }

    std::string trimmed(trimmedView);
    try {
      std::size_t parsed = 0;
      const float value = std::stof(trimmed, &parsed);
      if (parsed != trimmed.size() || !std::isfinite(value)) {
        return std::nullopt;
      }
      return value;
    } catch (...) {
      return std::nullopt;
    }
  }

  std::optional<double> parseDoubleInput(std::string_view text) {
    const auto trimmedView = trimInput(text);
    if (trimmedView.empty()) {
      return std::nullopt;
    }

    std::string trimmed(trimmedView);
    try {
      std::size_t parsed = 0;
      const double value = std::stod(trimmed, &parsed);
      if (parsed != trimmed.size() || !std::isfinite(value)) {
        return std::nullopt;
      }
      return value;
    } catch (...) {
      return std::nullopt;
    }
  }

  bool monitorOverrideHasExplicitValue(const Config& cfg, const std::vector<std::string>& path) {
    if (path.size() < 5 || path[0] != "bar" || path[2] != "monitor") {
      return false;
    }

    const auto* bar = settings::findBar(cfg, path[1]);
    if (bar == nullptr) {
      return false;
    }

    const auto* override = settings::findMonitorOverride(*bar, path[3]);
    if (override == nullptr) {
      return false;
    }

    const std::string_view key = path.back();
    if (key == "enabled") {
      return override->enabled.has_value();
    }
    if (key == "auto_hide") {
      return override->autoHide.has_value();
    }
    if (key == "reserve_space") {
      return override->reserveSpace.has_value();
    }
    if (key == "thickness") {
      return override->thickness.has_value();
    }
    if (key == "scale") {
      return override->scale.has_value();
    }
    if (key == "margin_h") {
      return override->marginH.has_value();
    }
    if (key == "margin_v") {
      return override->marginV.has_value();
    }
    if (key == "padding") {
      return override->padding.has_value();
    }
    if (key == "radius") {
      return override->radius.has_value();
    }
    if (key == "radius_top_left") {
      return override->radiusTopLeft.has_value();
    }
    if (key == "radius_top_right") {
      return override->radiusTopRight.has_value();
    }
    if (key == "radius_bottom_left") {
      return override->radiusBottomLeft.has_value();
    }
    if (key == "radius_bottom_right") {
      return override->radiusBottomRight.has_value();
    }
    if (key == "background_opacity") {
      return override->backgroundOpacity.has_value();
    }
    if (key == "background_blur") {
      return override->backgroundBlur.has_value();
    }
    if (key == "shadow") {
      return override->shadow.has_value();
    }
    if (key == "widget_spacing") {
      return override->widgetSpacing.has_value();
    }
    if (key == "capsule") {
      return override->widgetCapsuleDefault.has_value();
    }
    if (key == "capsule_fill") {
      return override->widgetCapsuleFill.has_value();
    }
    if (key == "capsule_border") {
      return override->widgetCapsuleBorder.has_value();
    }
    if (key == "capsule_foreground") {
      return override->widgetCapsuleForeground.has_value();
    }
    if (key == "widget_color") {
      return override->widgetColor.has_value();
    }
    if (key == "capsule_padding") {
      return override->widgetCapsulePadding.has_value();
    }
    if (key == "capsule_opacity") {
      return override->widgetCapsuleOpacity.has_value();
    }
    if (key == "start") {
      return override->startWidgets.has_value();
    }
    if (key == "center") {
      return override->centerWidgets.has_value();
    }
    if (key == "end") {
      return override->endWidgets.has_value();
    }
    return false;
  }

} // namespace

void SettingsWindow::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
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

  wl_output* output = m_wayland->lastPointerOutput();
  if (output == nullptr) {
    const auto& outs = m_wayland->outputs();
    if (!outs.empty() && outs.front().output != nullptr) {
      output = outs.front().output;
    }
  }

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
      .title = "Noctalia Settings",
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
  m_sceneRoot.reset();
  m_surface.reset();
  m_pointerInside = false;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
  m_rebuildRequested = false;
  m_focusSearchOnRebuild = false;
  m_statusMessage.clear();
  m_statusIsError = false;
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
  } else if ((sizeChanged || needsLayout) && m_sceneRoot != nullptr) {
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
    m_sceneRoot->layout(*m_renderContext);
    m_lastSceneWidth = width;
    m_lastSceneHeight = height;
  }
}

void SettingsWindow::buildScene(std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("SettingsWindow::buildScene");
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }

  const float w = static_cast<float>(width);
  const float h = static_cast<float>(height);
  const float scale = uiScale();
  const Config cfg = m_config != nullptr ? m_config->config() : Config{};
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
  const auto registry = settings::buildSettingsRegistry(cfg, selectedBar, selectedMonitorOverride);
  const auto sections = sectionKeys(registry);
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
    for (const auto& entry : registry) {
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
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setSize(w, h);
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
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
  headerTitle->setText(i18n::tr("settings.title"));
  headerTitle->setBold(true);
  headerTitle->setFontSize(Style::fontSizeTitle * scale);
  headerTitle->setColor(roleColor(ColorRole::OnSurface));
  headerTitle->setFlexGrow(1.0f);
  header->addChild(std::move(headerTitle));

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

  const auto requestRebuild = [this]() {
    DeferredCall::callLater([this]() {
      if (m_surface == nullptr) {
        return;
      }
      m_rebuildRequested = true;
      m_surface->requestLayout();
    });
  };

  const auto clearStatus = [this]() {
    m_statusMessage.clear();
    m_statusIsError = false;
  };

  const auto setOverride = [this, requestRebuild](std::vector<std::string> path, ConfigOverrideValue value) {
    DeferredCall::callLater([this, path = std::move(path), value = std::move(value), requestRebuild]() mutable {
      if (m_config == nullptr) {
        return;
      }
      if (m_config->setOverride(path, std::move(value))) {
        m_statusMessage.clear();
        m_statusIsError = false;
        m_pendingResetPageScope.clear();
        requestRebuild();
        return;
      }
      m_statusMessage = i18n::tr("settings.write-error");
      m_statusIsError = true;
      requestRebuild();
    });
  };

  const auto setOverrides =
      [this, requestRebuild](std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides) {
        DeferredCall::callLater([this, overrides = std::move(overrides), requestRebuild]() mutable {
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
            m_statusMessage = i18n::tr("settings.batch-write-error");
            m_statusIsError = true;
            requestRebuild();
            return;
          }
          const bool hadStatus = !m_statusMessage.empty();
          m_statusMessage.clear();
          m_statusIsError = false;
          m_pendingResetPageScope.clear();
          if (changed || hadStatus) {
            requestRebuild();
          }
        });
      };

  const auto clearOverride = [this, requestRebuild](std::vector<std::string> path) {
    DeferredCall::callLater([this, path = std::move(path), requestRebuild]() mutable {
      if (m_config == nullptr) {
        return;
      }
      if (m_config->clearOverride(path)) {
        m_statusMessage.clear();
        m_statusIsError = false;
        m_pendingResetPageScope.clear();
        requestRebuild();
        return;
      }
      m_statusMessage = i18n::tr("settings.clear-error");
      m_statusIsError = true;
      requestRebuild();
    });
  };

  const auto clearOverrides = [this, requestRebuild](std::vector<std::vector<std::string>> paths) {
    DeferredCall::callLater([this, paths = std::move(paths), requestRebuild]() mutable {
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
        m_statusMessage = i18n::tr("settings.reset-page-error");
        m_statusIsError = true;
        requestRebuild();
        return;
      }

      m_statusMessage.clear();
      m_statusIsError = false;
      if (changed) {
        requestRebuild();
      }
    });
  };

  const auto renameWidgetInstance =
      [this, requestRebuild](std::string oldName, std::string newName,
                             std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> referenceOverrides) {
        DeferredCall::callLater([this, oldName = std::move(oldName), newName = std::move(newName),
                                 referenceOverrides = std::move(referenceOverrides), requestRebuild]() mutable {
          if (m_config == nullptr) {
            return;
          }

          bool changed = m_config->renameOverrideTable({"widget", oldName}, {"widget", newName});
          if (!changed) {
            m_statusMessage = i18n::tr("settings.rename-widget-error");
            m_statusIsError = true;
            requestRebuild();
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
            m_statusMessage = i18n::tr("settings.batch-write-error");
            m_statusIsError = true;
            requestRebuild();
            return;
          }
          m_statusMessage.clear();
          m_statusIsError = false;
          m_pendingResetPageScope.clear();
          if (changed) {
            requestRebuild();
          }
        });
      };

  auto filters = std::make_unique<Flex>();
  filters->setDirection(FlexDirection::Horizontal);
  filters->setAlign(FlexAlign::Center);
  filters->setJustify(FlexJustify::SpaceBetween);
  filters->setGap(Style::spaceMd * scale);

  auto searchInput = std::make_unique<Input>();
  searchInput->setPlaceholder(i18n::tr("settings.search-placeholder"));
  searchInput->setValue(m_searchQuery);
  searchInput->setFontSize(Style::fontSizeBody * scale);
  searchInput->setControlHeight(Style::controlHeight * scale);
  searchInput->setHorizontalPadding(Style::spaceSm * scale);
  searchInput->setSize(320.0f * scale, Style::controlHeight * scale);
  searchInput->setFlexGrow(1.0f);
  Input* searchInputPtr = searchInput.get();
  searchInput->setOnChange([this, requestRebuild](const std::string& value) {
    m_searchQuery = value;
    m_focusSearchOnRebuild = true;
    m_pendingResetPageScope.clear();
    requestRebuild();
  });
  filters->addChild(std::move(searchInput));

  auto advancedLabel = makeLabel(i18n::tr("settings.badge-advanced"), Style::fontSizeBody * scale,
                                 roleColor(ColorRole::OnSurfaceVariant), false);
  filters->addChild(std::move(advancedLabel));

  auto advancedToggle = std::make_unique<Toggle>();
  advancedToggle->setScale(scale);
  advancedToggle->setChecked(m_showAdvanced);
  advancedToggle->setOnChange([this, requestRebuild](bool value) {
    m_showAdvanced = value;
    m_pendingResetPageScope.clear();
    requestRebuild();
  });
  filters->addChild(std::move(advancedToggle));

  auto overriddenLabel = makeLabel(i18n::tr("settings.filter-modified"), Style::fontSizeBody * scale,
                                   roleColor(ColorRole::OnSurfaceVariant), false);
  filters->addChild(std::move(overriddenLabel));

  auto overriddenToggle = std::make_unique<Toggle>();
  overriddenToggle->setScale(scale);
  overriddenToggle->setChecked(m_showOverriddenOnly);
  overriddenToggle->setOnChange([this, requestRebuild](bool value) {
    m_showOverriddenOnly = value;
    m_pendingResetPageScope.clear();
    requestRebuild();
  });
  filters->addChild(std::move(overriddenToggle));

  if (!resetPagePaths.empty()) {
    const bool pendingReset = m_pendingResetPageScope == resetPageScope;
    auto resetPageBtn = std::make_unique<Button>();
    resetPageBtn->setText(pendingReset ? i18n::tr("settings.reset-page-confirm") : i18n::tr("settings.reset-page"));
    resetPageBtn->setVariant(pendingReset ? ButtonVariant::Default : ButtonVariant::Ghost);
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
    status->setFill(roleColor(m_statusIsError ? ColorRole::Error : ColorRole::Secondary, 0.14f));
    status->setBorder(roleColor(m_statusIsError ? ColorRole::Error : ColorRole::Secondary, 0.45f), Style::borderWidth);

    auto message = makeLabel(m_statusMessage, Style::fontSizeCaption * scale,
                             roleColor(m_statusIsError ? ColorRole::Error : ColorRole::Secondary), true);
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

  const auto sectionLabel = [&](std::string_view section) {
    return i18n::tr("settings.section." + std::string(section));
  };

  const auto groupLabel = [&](std::string_view group) { return i18n::tr("settings.group." + std::string(group)); };

  auto body = std::make_unique<Flex>();
  body->setDirection(FlexDirection::Horizontal);
  body->setAlign(FlexAlign::Stretch);
  body->setGap(Style::spaceMd * scale);

  auto sidebar = std::make_unique<Flex>();
  sidebar->setDirection(FlexDirection::Vertical);
  sidebar->setAlign(FlexAlign::Stretch);
  sidebar->setGap(Style::spaceXs * scale);
  sidebar->setSize(132.0f * scale, 0.0f);
  sidebar->setMinWidth(132.0f * scale);
  sidebar->setPadding(Style::spaceXs * scale, 0.0f);

  for (const auto& section : sections) {
    const bool selected = section == m_selectedSection;
    auto navItem = std::make_unique<Button>();
    navItem->setText(sectionLabel(section));
    navItem->setVariant(selected ? ButtonVariant::TabActive : ButtonVariant::Tab);
    navItem->setContentAlign(ButtonContentAlign::Start);
    navItem->setFontSize(Style::fontSizeBody * scale);
    navItem->setMinHeight(Style::controlHeight * scale);
    navItem->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    navItem->setRadius(Style::radiusMd * scale);
    navItem->setOnClick([this, section, requestRebuild]() {
      if (m_selectedSection != section) {
        m_contentScrollState.offset = 0.0f;
      }
      m_selectedSection = section;
      m_openWidgetPickerPath.clear();
      m_editingWidgetName.clear();
      m_renamingWidgetName.clear();
      m_pendingDeleteWidgetName.clear();
      m_pendingDeleteWidgetSettingPath.clear();
      m_creatingWidgetType.clear();
      m_pendingResetPageScope.clear();
      requestRebuild();
    });
    sidebar->addChild(std::move(navItem));
  }

  for (const auto& barName : availableBars) {
    const bool barSelected =
        m_selectedSection == "bar" && m_selectedBarName == barName && m_selectedMonitorOverride.empty();
    auto navItem = std::make_unique<Button>();
    navItem->setText(i18n::tr("settings.bar-label", "name", barName));
    navItem->setVariant(barSelected ? ButtonVariant::TabActive : ButtonVariant::Tab);
    navItem->setContentAlign(ButtonContentAlign::Start);
    navItem->setFontSize(Style::fontSizeBody * scale);
    navItem->setMinHeight(Style::controlHeight * scale);
    navItem->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    navItem->setRadius(Style::radiusMd * scale);
    navItem->setOnClick([this, barName, requestRebuild]() {
      if (m_selectedSection != "bar" || m_selectedBarName != barName || !m_selectedMonitorOverride.empty()) {
        m_contentScrollState.offset = 0.0f;
      }
      m_selectedSection = "bar";
      m_selectedBarName = barName;
      m_selectedMonitorOverride.clear();
      m_openWidgetPickerPath.clear();
      m_editingWidgetName.clear();
      m_renamingWidgetName.clear();
      m_pendingDeleteWidgetName.clear();
      m_pendingDeleteWidgetSettingPath.clear();
      m_creatingWidgetType.clear();
      m_pendingResetPageScope.clear();
      requestRebuild();
    });
    sidebar->addChild(std::move(navItem));

    const auto* bar = settings::findBar(cfg, barName);
    if (bar != nullptr) {
      for (const auto& ovr : bar->monitorOverrides) {
        const bool ovrSelected =
            m_selectedSection == "bar" && m_selectedBarName == barName && m_selectedMonitorOverride == ovr.match;
        auto ovrItem = std::make_unique<Button>();
        ovrItem->setText(i18n::tr("settings.monitor-override-label", "name", ovr.match));
        ovrItem->setVariant(ovrSelected ? ButtonVariant::TabActive : ButtonVariant::Tab);
        ovrItem->setContentAlign(ButtonContentAlign::Start);
        ovrItem->setFontSize(Style::fontSizeCaption * scale);
        ovrItem->setMinHeight(Style::controlHeightSm * scale);
        ovrItem->setPadding(Style::spaceXs * scale, Style::spaceMd * scale, Style::spaceXs * scale,
                            Style::spaceLg * scale);
        ovrItem->setRadius(Style::radiusMd * scale);
        auto match = ovr.match;
        ovrItem->setOnClick([this, barName, match, requestRebuild]() {
          if (m_selectedSection != "bar" || m_selectedBarName != barName || m_selectedMonitorOverride != match) {
            m_contentScrollState.offset = 0.0f;
          }
          m_selectedSection = "bar";
          m_selectedBarName = barName;
          m_selectedMonitorOverride = match;
          m_openWidgetPickerPath.clear();
          m_editingWidgetName.clear();
          m_renamingWidgetName.clear();
          m_pendingDeleteWidgetName.clear();
          m_pendingDeleteWidgetSettingPath.clear();
          m_creatingWidgetType.clear();
          m_pendingResetPageScope.clear();
          requestRebuild();
        });
        sidebar->addChild(std::move(ovrItem));
      }
    }
  }

  body->addChild(std::move(sidebar));

  auto sidebarSep = std::make_unique<Separator>();
  sidebarSep->setColor(roleColor(ColorRole::Outline, 0.25f));
  body->addChild(std::move(sidebarSep));

  auto scroll = std::make_unique<ScrollView>();
  scroll->bindState(&m_contentScrollState);
  scroll->setFlexGrow(1.0f);
  scroll->setScrollbarVisible(true);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(Style::spaceSm * scale);
  scroll->clearFill();
  scroll->clearBorder();
  auto* content = scroll->content();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceMd * scale);

  const auto makeSection = [&](std::string_view title) -> Flex* {
    auto section = std::make_unique<Flex>();
    section->setDirection(FlexDirection::Vertical);
    section->setAlign(FlexAlign::Stretch);
    section->setGap(Style::spaceSm * scale);
    section->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    section->setCardStyle(scale);

    auto titleLabel = makeLabel(title, Style::fontSizeTitle * scale, roleColor(ColorRole::OnSurface), true);
    section->addChild(std::move(titleLabel));
    auto* raw = section.get();
    content->addChild(std::move(section));
    return raw;
  };

  const auto addGroupLabel = [&](Flex& section, std::string_view title, bool isFirst) {
    if (title.empty()) {
      return;
    }
    if (!isFirst) {
      auto groupHeader = std::make_unique<Flex>();
      groupHeader->setDirection(FlexDirection::Vertical);
      groupHeader->setAlign(FlexAlign::Stretch);
      groupHeader->setGap(Style::spaceSm * scale);
      groupHeader->setPadding(Style::spaceSm * scale, 0.0f, 0.0f, 0.0f);
      auto sep = std::make_unique<Separator>();
      sep->setColor(roleColor(ColorRole::Outline, 0.20f));
      groupHeader->addChild(std::move(sep));
      groupHeader->addChild(
          makeLabel(title, Style::fontSizeBody * scale, roleColor(ColorRole::OnSurfaceVariant), true));
      section.addChild(std::move(groupHeader));
    } else {
      section.addChild(makeLabel(title, Style::fontSizeBody * scale, roleColor(ColorRole::OnSurfaceVariant), true));
    }
  };

  const auto makeResetButton = [&](const std::vector<std::string>& path) {
    auto reset = std::make_unique<Button>();
    reset->setText(i18n::tr("settings.reset"));
    reset->setVariant(ButtonVariant::Ghost);
    reset->setFontSize(Style::fontSizeCaption * scale);
    reset->setMinHeight(Style::controlHeightSm * scale);
    reset->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
    reset->setRadius(Style::radiusMd * scale);
    reset->setOnClick([clearOverride, path]() { clearOverride(path); });
    return reset;
  };

  const auto makeRow = [&](Flex& section, const settings::SettingEntry& entry, std::unique_ptr<Node> control) {
    const bool overridden = (m_config != nullptr && m_config->hasOverride(entry.path));
    const bool monitorExplicit = monitorOverrideHasExplicitValue(cfg, entry.path);

    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setJustify(FlexJustify::SpaceBetween);
    row->setGap(Style::spaceXs * scale);
    row->setPadding(2.0f * scale, 0.0f);
    row->setMinHeight(Style::controlHeight * scale);

    auto copy = std::make_unique<Flex>();
    copy->setDirection(FlexDirection::Vertical);
    copy->setAlign(FlexAlign::Start);
    copy->setGap(Style::spaceXs * scale);
    copy->setFlexGrow(1.0f);

    auto titleRow = std::make_unique<Flex>();
    titleRow->setDirection(FlexDirection::Horizontal);
    titleRow->setAlign(FlexAlign::Center);
    titleRow->setGap(Style::spaceSm * scale);
    titleRow->addChild(makeLabel(entry.title, Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), false));
    if (monitorExplicit) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setFill(roleColor(ColorRole::Secondary, 0.15f));
      badge->addChild(makeLabel(i18n::tr("settings.badge-monitor"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::Secondary), true));
      titleRow->addChild(std::move(badge));
    }
    if (overridden) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setFill(roleColor(ColorRole::Primary, 0.15f));
      badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::Primary), true));
      titleRow->addChild(std::move(badge));
    }
    if (entry.advanced) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setFill(roleColor(ColorRole::OnSurfaceVariant, 0.12f));
      badge->addChild(makeLabel(i18n::tr("settings.badge-advanced"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::OnSurfaceVariant), true));
      titleRow->addChild(std::move(badge));
    }
    copy->addChild(std::move(titleRow));

    if (!entry.subtitle.empty()) {
      auto detail =
          makeLabel(entry.subtitle, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant), false);
      detail->setMaxWidth(360.0f * scale);
      copy->addChild(std::move(detail));
    }

    row->addChild(std::move(copy));

    auto actions = std::make_unique<Flex>();
    actions->setDirection(FlexDirection::Horizontal);
    actions->setAlign(FlexAlign::Center);
    actions->setGap(Style::spaceSm * scale);
    if (overridden) {
      actions->addChild(makeResetButton(entry.path));
    }
    actions->addChild(std::move(control));
    row->addChild(std::move(actions));

    section.addChild(std::move(row));
  };

  const auto makeToggle = [&](bool checked, std::vector<std::string> path) {
    auto toggle = std::make_unique<Toggle>();
    toggle->setScale(scale);
    toggle->setChecked(checked);
    toggle->setOnChange([setOverride, path](bool value) { setOverride(path, value); });
    return toggle;
  };

  const auto makeSelect = [&](const settings::SelectSetting& setting, std::vector<std::string> path) {
    auto select = std::make_unique<Select>();
    select->setOptions(optionLabels(setting.options));
    if (const auto index = optionIndex(setting.options, setting.selectedValue)) {
      select->setSelectedIndex(*index);
    } else if (!setting.selectedValue.empty()) {
      select->clearSelection();
      select->setPlaceholder(i18n::tr("settings.unknown-select-value", "value", setting.selectedValue));
    }
    select->setFontSize(Style::fontSizeBody * scale);
    select->setControlHeight(Style::controlHeight * scale);
    select->setGlyphSize(Style::fontSizeBody * scale);
    select->setSize(190.0f * scale, Style::controlHeight * scale);
    auto options = setting.options;
    select->setOnSelectionChanged([setOverride, path, options](std::size_t index, std::string_view /*label*/) {
      if (index < options.size()) {
        setOverride(path, options[index].value);
      }
    });
    return select;
  };

  const auto makeSlider = [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
                              bool integerValue = false) {
    auto wrap = std::make_unique<Flex>();
    wrap->setDirection(FlexDirection::Horizontal);
    wrap->setAlign(FlexAlign::Center);
    wrap->setGap(Style::spaceSm * scale);

    auto valueInput = std::make_unique<Input>();
    valueInput->setValue(integerValue ? std::format("{}", static_cast<int>(std::lround(value)))
                                      : std::format("{:.2f}", value));
    valueInput->setFontSize(Style::fontSizeCaption * scale);
    valueInput->setControlHeight(Style::controlHeightSm * scale);
    valueInput->setHorizontalPadding(Style::spaceXs * scale);
    valueInput->setSize(50.0f * scale, Style::controlHeightSm * scale);
    auto* valueInputPtr = valueInput.get();

    auto slider = std::make_unique<Slider>();
    slider->setRange(minValue, maxValue);
    slider->setStep(step);
    slider->setSize(180.0f * scale, Style::controlHeight * scale);
    slider->setControlHeight(Style::controlHeight * scale);
    slider->setThumbSize(16.0f * scale);
    slider->setTrackHeight(5.0f * scale);
    slider->setValue(value);
    auto* sliderPtr = slider.get();
    slider->setOnValueChanged([valueInputPtr, integerValue](float next) {
      valueInputPtr->setInvalid(false);
      valueInputPtr->setValue(integerValue ? std::format("{}", static_cast<int>(std::lround(next)))
                                           : std::format("{:.2f}", next));
    });
    slider->setOnDragEnd([setOverride, path, sliderPtr, integerValue]() {
      if (integerValue) {
        setOverride(path, static_cast<std::int64_t>(std::lround(sliderPtr->value())));
      } else {
        setOverride(path, static_cast<double>(sliderPtr->value()));
      }
    });

    valueInput->setOnChange([valueInputPtr](const std::string& /*text*/) { valueInputPtr->setInvalid(false); });
    valueInput->setOnSubmit(
        [setOverride, path, sliderPtr, valueInputPtr, minValue, maxValue, integerValue](const std::string& text) {
          const auto parsed = parseFloatInput(text);
          if (!parsed.has_value() || *parsed < minValue || *parsed > maxValue) {
            valueInputPtr->setInvalid(true);
            return;
          }
          const float v = *parsed;
          valueInputPtr->setInvalid(false);
          sliderPtr->setValue(v);
          if (integerValue) {
            setOverride(path, static_cast<std::int64_t>(std::lround(v)));
          } else {
            setOverride(path, static_cast<double>(v));
          }
        });

    wrap->addChild(std::move(valueInput));
    wrap->addChild(std::move(slider));
    return wrap;
  };

  const auto makeText = [&](const std::string& value, const std::string& placeholder, std::vector<std::string> path) {
    auto input = std::make_unique<Input>();
    input->setValue(value);
    input->setPlaceholder(placeholder);
    input->setFontSize(Style::fontSizeBody * scale);
    input->setControlHeight(Style::controlHeight * scale);
    input->setHorizontalPadding(Style::spaceSm * scale);
    input->setSize(190.0f * scale, Style::controlHeight * scale);
    input->setOnSubmit([setOverride, path](const std::string& v) { setOverride(path, v); });
    return input;
  };

  const auto makeOptionalNumber = [&](const settings::OptionalNumberSetting& setting, std::vector<std::string> path) {
    auto input = std::make_unique<Input>();
    input->setValue(setting.value.has_value() ? std::format("{}", *setting.value) : "");
    input->setPlaceholder(setting.placeholder);
    input->setFontSize(Style::fontSizeBody * scale);
    input->setControlHeight(Style::controlHeight * scale);
    input->setHorizontalPadding(Style::spaceSm * scale);
    input->setSize(190.0f * scale, Style::controlHeight * scale);
    auto* inputPtr = input.get();
    input->setOnChange([inputPtr](const std::string& /*text*/) { inputPtr->setInvalid(false); });
    input->setOnSubmit([this, clearOverride, setOverride, path, inputPtr, minValue = setting.minValue,
                        maxValue = setting.maxValue](const std::string& text) {
      if (isBlankInput(text)) {
        inputPtr->setInvalid(false);
        if (m_config != nullptr && m_config->hasOverride(path)) {
          clearOverride(path);
        }
        return;
      }

      const auto parsed = parseDoubleInput(text);
      if (!parsed.has_value() || *parsed < minValue || *parsed > maxValue) {
        inputPtr->setInvalid(true);
        return;
      }

      inputPtr->setInvalid(false);
      setOverride(path, *parsed);
    });
    return input;
  };

  const auto makeListBlock = [&](Flex& section, const settings::SettingEntry& entry,
                                 const settings::ListSetting& list) {
    const bool overridden = (m_config != nullptr && m_config->hasOverride(entry.path));

    auto block = std::make_unique<Flex>();
    block->setDirection(FlexDirection::Vertical);
    block->setAlign(FlexAlign::Stretch);
    block->setGap(Style::spaceXs * scale);
    block->setPadding(2.0f * scale, 0.0f);

    auto titleRow = std::make_unique<Flex>();
    titleRow->setDirection(FlexDirection::Horizontal);
    titleRow->setAlign(FlexAlign::Center);
    titleRow->setGap(Style::spaceSm * scale);
    titleRow->addChild(makeLabel(entry.title, Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), false));
    if (overridden) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setFill(roleColor(ColorRole::Primary, 0.15f));
      badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::Primary), true));
      titleRow->addChild(std::move(badge));
    }
    if (overridden) {
      titleRow->addChild(makeResetButton(entry.path));
    }
    block->addChild(std::move(titleRow));

    if (!entry.subtitle.empty()) {
      block->addChild(
          makeLabel(entry.subtitle, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant), false));
    }

    for (std::size_t i = 0; i < list.items.size(); ++i) {
      auto itemRow = std::make_unique<Flex>();
      itemRow->setDirection(FlexDirection::Horizontal);
      itemRow->setAlign(FlexAlign::Center);
      itemRow->setGap(Style::spaceXs * scale);
      itemRow->setMinHeight(Style::controlHeightSm * scale);

      itemRow->addChild(
          makeLabel(list.items[i], Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurface), false));

      auto spacer = std::make_unique<Flex>();
      spacer->setFlexGrow(1.0f);
      itemRow->addChild(std::move(spacer));

      if (i > 0) {
        auto upBtn = std::make_unique<Button>();
        upBtn->setGlyph("chevron-up");
        upBtn->setVariant(ButtonVariant::Ghost);
        upBtn->setGlyphSize(Style::fontSizeCaption * scale);
        upBtn->setMinWidth(Style::controlHeightSm * scale);
        upBtn->setMinHeight(Style::controlHeightSm * scale);
        upBtn->setPadding(Style::spaceXs * scale);
        upBtn->setRadius(Style::radiusSm * scale);
        auto items = list.items;
        auto path = entry.path;
        upBtn->setOnClick([setOverride, items, path, i]() mutable {
          std::swap(items[i], items[i - 1]);
          setOverride(path, items);
        });
        itemRow->addChild(std::move(upBtn));
      }
      if (i + 1 < list.items.size()) {
        auto downBtn = std::make_unique<Button>();
        downBtn->setGlyph("chevron-down");
        downBtn->setVariant(ButtonVariant::Ghost);
        downBtn->setGlyphSize(Style::fontSizeCaption * scale);
        downBtn->setMinWidth(Style::controlHeightSm * scale);
        downBtn->setMinHeight(Style::controlHeightSm * scale);
        downBtn->setPadding(Style::spaceXs * scale);
        downBtn->setRadius(Style::radiusSm * scale);
        auto items = list.items;
        auto path = entry.path;
        downBtn->setOnClick([setOverride, items, path, i]() mutable {
          std::swap(items[i], items[i + 1]);
          setOverride(path, items);
        });
        itemRow->addChild(std::move(downBtn));
      }

      auto removeBtn = std::make_unique<Button>();
      removeBtn->setGlyph("close");
      removeBtn->setVariant(ButtonVariant::Ghost);
      removeBtn->setGlyphSize(Style::fontSizeCaption * scale);
      removeBtn->setMinWidth(Style::controlHeightSm * scale);
      removeBtn->setMinHeight(Style::controlHeightSm * scale);
      removeBtn->setPadding(Style::spaceXs * scale);
      removeBtn->setRadius(Style::radiusSm * scale);
      auto items = list.items;
      auto path = entry.path;
      removeBtn->setOnClick([setOverride, items, path, i]() mutable {
        items.erase(items.begin() + static_cast<std::ptrdiff_t>(i));
        setOverride(path, items);
      });
      itemRow->addChild(std::move(removeBtn));

      block->addChild(std::move(itemRow));
    }

    auto addRow = std::make_unique<Flex>();
    addRow->setDirection(FlexDirection::Horizontal);
    addRow->setAlign(FlexAlign::Center);
    addRow->setGap(Style::spaceXs * scale);

    auto addInput = std::make_unique<Input>();
    addInput->setFontSize(Style::fontSizeCaption * scale);
    addInput->setControlHeight(Style::controlHeightSm * scale);
    addInput->setHorizontalPadding(Style::spaceXs * scale);
    addInput->setSize(140.0f * scale, Style::controlHeightSm * scale);
    addInput->setFlexGrow(1.0f);
    auto* addInputPtr = addInput.get();

    auto addBtn = std::make_unique<Button>();
    addBtn->setGlyph("add");
    addBtn->setVariant(ButtonVariant::Ghost);
    addBtn->setGlyphSize(Style::fontSizeCaption * scale);
    addBtn->setMinWidth(Style::controlHeightSm * scale);
    addBtn->setMinHeight(Style::controlHeightSm * scale);
    addBtn->setPadding(Style::spaceXs * scale);
    addBtn->setRadius(Style::radiusSm * scale);
    auto items = list.items;
    auto path = entry.path;
    addBtn->setOnClick([setOverride, addInputPtr, items, path]() mutable {
      const auto& text = addInputPtr->value();
      if (!text.empty()) {
        items.push_back(text);
        setOverride(path, items);
      }
    });

    addInput->setOnSubmit([setOverride, items, path](const std::string& text) mutable {
      if (!text.empty()) {
        items.push_back(text);
        setOverride(path, items);
      }
    });

    addRow->addChild(std::move(addInput));
    addRow->addChild(std::move(addBtn));
    block->addChild(std::move(addRow));

    section.addChild(std::move(block));
  };

  const auto makeControl = [&](const settings::SettingEntry& entry) -> std::unique_ptr<Node> {
    return std::visit(
        [&](const auto& control) -> std::unique_ptr<Node> {
          using T = std::decay_t<decltype(control)>;
          if constexpr (std::is_same_v<T, settings::ToggleSetting>) {
            return makeToggle(control.checked, entry.path);
          } else if constexpr (std::is_same_v<T, settings::SelectSetting>) {
            return makeSelect(control, entry.path);
          } else if constexpr (std::is_same_v<T, settings::SliderSetting>) {
            return makeSlider(control.value, control.minValue, control.maxValue, control.step, entry.path,
                              control.integerValue);
          } else if constexpr (std::is_same_v<T, settings::TextSetting>) {
            return makeText(control.value, control.placeholder, entry.path);
          } else if constexpr (std::is_same_v<T, settings::OptionalNumberSetting>) {
            return makeOptionalNumber(control, entry.path);
          } else if constexpr (std::is_same_v<T, settings::ListSetting>) {
            return nullptr;
          }
        },
        entry.control);
  };

  std::string activeSectionKey;
  std::string activeGroupKey;
  Flex* activeSection = nullptr;
  std::size_t visibleEntries = 0;

  settings::BarWidgetEditorContext barWidgetEditorCtx{
      .config = cfg,
      .configService = m_config,
      .scale = scale,
      .showAdvanced = m_showAdvanced,
      .showOverriddenOnly = m_showOverriddenOnly,
      .openWidgetPickerPath = m_openWidgetPickerPath,
      .editingWidgetName = m_editingWidgetName,
      .pendingDeleteWidgetName = m_pendingDeleteWidgetName,
      .pendingDeleteWidgetSettingPath = m_pendingDeleteWidgetSettingPath,
      .renamingWidgetName = m_renamingWidgetName,
      .creatingWidgetType = m_creatingWidgetType,
      .requestRebuild = requestRebuild,
      .resetContentScroll = [this]() { m_contentScrollState.offset = 0.0f; },
      .setOverride = setOverride,
      .setOverrides = setOverrides,
      .clearOverride = clearOverride,
      .renameWidgetInstance = renameWidgetInstance,
      .makeResetButton = makeResetButton,
      .makeRow = makeRow,
      .makeToggle = [&](bool checked, std::vector<std::string> path) -> std::unique_ptr<Node> {
        return makeToggle(checked, std::move(path));
      },
      .makeSelect = [&](const settings::SelectSetting& setting, std::vector<std::string> path)
          -> std::unique_ptr<Node> { return makeSelect(setting, std::move(path)); },
      .makeSlider = [&](float value, float minValue, float maxValue, float step, std::vector<std::string> path,
                        bool integerValue) -> std::unique_ptr<Node> {
        return makeSlider(value, minValue, maxValue, step, std::move(path), integerValue);
      },
      .makeText = [&](const std::string& value, const std::string& placeholder, std::vector<std::string> path)
          -> std::unique_ptr<Node> { return makeText(value, placeholder, std::move(path)); },
      .makeListBlock = [&](Flex& section, const settings::SettingEntry& entry,
                           const settings::ListSetting& list) { makeListBlock(section, entry, list); },
  };

  for (const auto& entry : registry) {
    if (m_searchQuery.empty() && !m_selectedSection.empty() && entry.section != m_selectedSection) {
      continue;
    }
    if (!m_showAdvanced && entry.advanced) {
      continue;
    }
    if (m_showOverriddenOnly && m_config != nullptr && !m_config->hasOverride(entry.path)) {
      continue;
    }
    if (!settings::matchesSettingQuery(entry, m_searchQuery)) {
      continue;
    }

    if (entry.section != activeSectionKey) {
      activeSectionKey = entry.section;
      activeGroupKey.clear();
      std::string displayTitle;
      if (entry.section == "bar" && selectedBar != nullptr) {
        displayTitle = i18n::tr("settings.bar-label", "name", selectedBar->name);
        if (selectedMonitorOverride != nullptr) {
          displayTitle += " / " + selectedMonitorOverride->match;
        }
      } else {
        displayTitle = sectionLabel(entry.section);
      }
      activeSection = makeSection(displayTitle);
    }
    if (activeSection != nullptr) {
      if (entry.group != activeGroupKey) {
        const bool isFirstGroup = activeGroupKey.empty();
        activeGroupKey = entry.group;
        addGroupLabel(*activeSection, groupLabel(entry.group), isFirstGroup);
      }
      if (const auto* list = std::get_if<settings::ListSetting>(&entry.control)) {
        if (settings::isFirstBarWidgetListPath(entry.path)) {
          settings::addBarWidgetLaneEditor(*activeSection, entry, barWidgetEditorCtx);
        } else if (!settings::isBarWidgetListPath(entry.path)) {
          makeListBlock(*activeSection, entry, *list);
        }
      } else {
        makeRow(*activeSection, entry, makeControl(entry));
      }
      ++visibleEntries;
    }
  }

  if (visibleEntries == 0) {
    auto emptyState = std::make_unique<Flex>();
    emptyState->setDirection(FlexDirection::Vertical);
    emptyState->setAlign(FlexAlign::Center);
    emptyState->setJustify(FlexJustify::Center);
    emptyState->setGap(Style::spaceXs * scale);
    emptyState->setPadding((Style::spaceLg + Style::spaceMd) * scale);
    emptyState->setFill(roleColor(ColorRole::SurfaceVariant, 0.24f));
    emptyState->setBorder(roleColor(ColorRole::Outline, 0.28f), Style::borderWidth);
    emptyState->setRadius(Style::radiusMd * scale);
    emptyState->addChild(
        makeLabel(i18n::tr("settings.no-results"), Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), true));
    emptyState->addChild(makeLabel(i18n::tr("settings.no-results-hint"), Style::fontSizeCaption * scale,
                                   roleColor(ColorRole::OnSurfaceVariant), false));
    content->addChild(std::move(emptyState));
  }

  body->addChild(std::move(scroll));
  auto bodyRow = centeredRow(std::move(body));
  bodyRow->setFlexGrow(1.0f);
  main->addChild(std::move(bodyRow));

  main->setSize(w, h);
  main->layout(*m_renderContext);

  m_mainContainer = static_cast<Flex*>(m_sceneRoot->addChild(std::move(main)));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  if (m_focusSearchOnRebuild && searchInputPtr != nullptr && searchInputPtr->inputArea() != nullptr) {
    m_inputDispatcher.setFocus(searchInputPtr->inputArea());
    m_focusSearchOnRebuild = false;
  }
  m_surface->setSceneRoot(m_sceneRoot.get());
}

bool SettingsWindow::onPointerEvent(const PointerEvent& event) {
  if (!isOpen() || m_surface == nullptr) {
    return false;
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
    if (!m_openWidgetPickerPath.empty() || !m_editingWidgetName.empty() || !m_creatingWidgetType.empty() ||
        !m_renamingWidgetName.empty() || !m_pendingDeleteWidgetName.empty() ||
        !m_pendingDeleteWidgetSettingPath.empty()) {
      m_openWidgetPickerPath.clear();
      m_editingWidgetName.clear();
      m_renamingWidgetName.clear();
      m_pendingDeleteWidgetName.clear();
      m_pendingDeleteWidgetSettingPath.clear();
      m_creatingWidgetType.clear();
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
