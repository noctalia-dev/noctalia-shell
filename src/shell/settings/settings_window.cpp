#include "shell/settings/settings_window.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "shell/settings/settings_registry.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/search_picker.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/slider.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
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

  std::string pathKey(const std::vector<std::string>& path) {
    std::string out;
    for (const auto& part : path) {
      if (!out.empty()) {
        out.push_back('.');
      }
      out += part;
    }
    return out;
  }

  bool isBarWidgetListPath(const std::vector<std::string>& path) {
    if (path.size() < 3 || path.front() != "bar") {
      return false;
    }
    const auto& key = path.back();
    return key == "start" || key == "center" || key == "end";
  }

  bool isFirstBarWidgetListPath(const std::vector<std::string>& path) {
    return isBarWidgetListPath(path) && path.back() == "start";
  }

  std::vector<std::string> pathWithLastSegment(std::vector<std::string> path, std::string segment) {
    if (!path.empty()) {
      path.back() = std::move(segment);
    }
    return path;
  }

  std::string laneLabel(std::string_view lane) {
    if (lane == "start") {
      return i18n::tr("settings.widget-lane-start");
    }
    if (lane == "center") {
      return i18n::tr("settings.widget-lane-center");
    }
    if (lane == "end") {
      return i18n::tr("settings.widget-lane-end");
    }
    return std::string(lane);
  }

  std::vector<std::string> barWidgetItemsForPath(const Config& cfg, const std::vector<std::string>& path) {
    if (!isBarWidgetListPath(path) || path.size() < 3) {
      return {};
    }

    const auto* bar = settings::findBar(cfg, path[1]);
    if (bar == nullptr) {
      return {};
    }

    const auto& lane = path.back();
    if (path.size() >= 5 && path[2] == "monitor") {
      const auto* ovr = settings::findMonitorOverride(*bar, path[3]);
      if (ovr != nullptr) {
        if (lane == "start") {
          return ovr->startWidgets.value_or(bar->startWidgets);
        }
        if (lane == "center") {
          return ovr->centerWidgets.value_or(bar->centerWidgets);
        }
        if (lane == "end") {
          return ovr->endWidgets.value_or(bar->endWidgets);
        }
      }
    }

    if (lane == "start") {
      return bar->startWidgets;
    }
    if (lane == "center") {
      return bar->centerWidgets;
    }
    if (lane == "end") {
      return bar->endWidgets;
    }
    return {};
  }

  ThemeColor widgetBadgeColor(settings::WidgetReferenceKind kind) {
    switch (kind) {
    case settings::WidgetReferenceKind::BuiltIn:
      return roleColor(ColorRole::Primary, 0.16f);
    case settings::WidgetReferenceKind::Named:
      return roleColor(ColorRole::Secondary, 0.18f);
    case settings::WidgetReferenceKind::Unknown:
      return roleColor(ColorRole::Error, 0.16f);
    }
    return roleColor(ColorRole::OnSurfaceVariant, 0.12f);
  }

  std::vector<SearchPickerOption> widgetPickerOptions(const Config& cfg) {
    std::vector<SearchPickerOption> options;
    const auto entries = settings::widgetPickerEntries(cfg);
    options.reserve(entries.size());
    for (const auto& entry : entries) {
      options.push_back(SearchPickerOption{.value = entry.value,
                                           .label = entry.label,
                                           .description = entry.description,
                                           .category = entry.category,
                                           .enabled = true});
    }
    return options;
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
  const std::uint32_t w = static_cast<std::uint32_t>(std::round(640.0f * scale));
  const std::uint32_t h = static_cast<std::uint32_t>(std::round(420.0f * scale));

  ToplevelSurfaceConfig cfg{
      .width = std::max<std::uint32_t>(1, w),
      .height = std::max<std::uint32_t>(1, h),
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
  m_sceneRoot.reset();
  m_surface.reset();
  m_pointerInside = false;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
  m_rebuildRequested = false;
  m_focusSearchOnRebuild = false;
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

  const bool sizeChanged = m_sceneRoot == nullptr || m_lastSceneWidth != width || m_lastSceneHeight != height;
  const bool needRebuild = sizeChanged || m_rebuildRequested;

  if (needRebuild) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(width, height);
    m_lastSceneWidth = width;
    m_lastSceneHeight = height;
    m_rebuildRequested = false;
  } else if (needsLayout && m_sceneRoot != nullptr) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    m_sceneRoot->setSize(static_cast<float>(width), static_cast<float>(height));
    m_sceneRoot->layout(*m_renderContext);
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

  m_inputDispatcher.setSceneRoot(nullptr);
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setSize(w, h);
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  bg->setPosition(0.0f, 0.0f);
  bg->setSize(w, h);
  m_sceneRoot->addChild(std::move(bg));

  auto main = std::make_unique<Flex>();
  main->setDirection(FlexDirection::Vertical);
  main->setAlign(FlexAlign::Stretch);
  main->setJustify(FlexJustify::Start);
  main->setGap(Style::spaceMd * scale);
  main->setPadding(Style::spaceLg * scale);
  main->setSize(w, h);

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

  main->addChild(std::move(header));

  const auto requestRebuild = [this]() {
    DeferredCall::callLater([this]() {
      if (m_surface == nullptr) {
        return;
      }
      m_rebuildRequested = true;
      m_surface->requestLayout();
    });
  };

  const auto setOverride = [this, requestRebuild](std::vector<std::string> path, ConfigOverrideValue value) {
    DeferredCall::callLater([this, path = std::move(path), value = std::move(value), requestRebuild]() mutable {
      if (m_config != nullptr && m_config->setOverride(path, std::move(value))) {
        requestRebuild();
      }
    });
  };

  const auto setOverrides =
      [this, requestRebuild](std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides) {
        DeferredCall::callLater([this, overrides = std::move(overrides), requestRebuild]() mutable {
          if (m_config == nullptr) {
            return;
          }
          bool changed = false;
          for (auto& [path, value] : overrides) {
            changed = m_config->setOverride(path, std::move(value)) || changed;
          }
          if (changed) {
            requestRebuild();
          }
        });
      };

  const auto clearOverride = [this, requestRebuild](std::vector<std::string> path) {
    DeferredCall::callLater([this, path = std::move(path), requestRebuild]() mutable {
      if (m_config != nullptr && m_config->clearOverride(path)) {
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
    requestRebuild();
  });
  filters->addChild(std::move(advancedToggle));

  auto overriddenLabel = makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeBody * scale,
                                   roleColor(ColorRole::OnSurfaceVariant), false);
  filters->addChild(std::move(overriddenLabel));

  auto overriddenToggle = std::make_unique<Toggle>();
  overriddenToggle->setScale(scale);
  overriddenToggle->setChecked(m_showOverriddenOnly);
  overriddenToggle->setOnChange([this, requestRebuild](bool value) {
    m_showOverriddenOnly = value;
    requestRebuild();
  });
  filters->addChild(std::move(overriddenToggle));

  main->addChild(std::move(filters));

  const auto sectionLabel = [&](std::string_view section) {
    return i18n::tr("settings.section." + std::string(section));
  };

  const auto groupLabel = [&](std::string_view group) { return i18n::tr("settings.group." + std::string(group)); };

  auto body = std::make_unique<Flex>();
  body->setDirection(FlexDirection::Horizontal);
  body->setAlign(FlexAlign::Stretch);
  body->setGap(Style::spaceMd * scale);
  body->setFlexGrow(1.0f);

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
      requestRebuild();
    });
    sidebar->addChild(std::move(navItem));

    const auto* bar = settings::findBar(cfg, barName);
    if (bar != nullptr) {
      for (const auto& ovr : bar->monitorOverrides) {
        const bool ovrSelected =
            m_selectedSection == "bar" && m_selectedBarName == barName && m_selectedMonitorOverride == ovr.match;
        auto ovrItem = std::make_unique<Button>();
        ovrItem->setText(ovr.match);
        ovrItem->setVariant(ovrSelected ? ButtonVariant::TabActive : ButtonVariant::Tab);
        ovrItem->setContentAlign(ButtonContentAlign::Start);
        ovrItem->setFontSize(Style::fontSizeCaption * scale);
        ovrItem->setMinHeight(Style::controlHeight * scale);
        ovrItem->setPadding(Style::spaceSm * scale, Style::spaceMd * scale, Style::spaceSm * scale,
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
  scroll->setBackgroundStyle(rgba(0, 0, 0, 0), rgba(0, 0, 0, 0), 0.0f);
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
    section->setBackground(roleColor(ColorRole::SurfaceVariant));
    section->setBorderColor(roleColor(ColorRole::Outline, 0.5f));
    section->setBorderWidth(Style::borderWidth);
    section->setRadius(Style::radiusMd * scale);

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
    if (overridden) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setBackground(roleColor(ColorRole::Primary, 0.15f));
      badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::Primary), true));
      titleRow->addChild(std::move(badge));
    }
    if (entry.advanced) {
      auto badge = std::make_unique<Flex>();
      badge->setAlign(FlexAlign::Center);
      badge->setPadding(1.0f * scale, Style::spaceXs * scale);
      badge->setRadius(Style::radiusSm * scale);
      badge->setBackground(roleColor(ColorRole::OnSurfaceVariant, 0.12f));
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

    valueInput->setOnSubmit([setOverride, path, sliderPtr, minValue, maxValue, integerValue](const std::string& text) {
      try {
        float v = std::clamp(std::stof(text), minValue, maxValue);
        sliderPtr->setValue(v);
        if (integerValue) {
          setOverride(path, static_cast<std::int64_t>(std::lround(v)));
        } else {
          setOverride(path, static_cast<double>(v));
        }
      } catch (...) {
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

  const auto widgetSettingPath = [](std::string widgetName, std::string settingKey) {
    return std::vector<std::string>{"widget", std::move(widgetName), std::move(settingKey)};
  };

  const auto widgetSettingValue = [&](std::string_view widgetName,
                                      const settings::WidgetSettingSpec& spec) -> WidgetSettingValue {
    if (const auto it = cfg.widgets.find(std::string(widgetName)); it != cfg.widgets.end()) {
      if (const auto settingIt = it->second.settings.find(spec.key); settingIt != it->second.settings.end()) {
        return settingIt->second;
      }
    }
    return spec.defaultValue;
  };

  const auto settingValueAsBool = [](const WidgetSettingValue& value) {
    if (const auto* v = std::get_if<bool>(&value)) {
      return *v;
    }
    return false;
  };

  const auto settingValueAsInt = [](const WidgetSettingValue& value) {
    if (const auto* v = std::get_if<std::int64_t>(&value)) {
      return *v;
    }
    if (const auto* v = std::get_if<double>(&value)) {
      return static_cast<std::int64_t>(std::llround(*v));
    }
    return std::int64_t{0};
  };

  const auto settingValueAsDouble = [](const WidgetSettingValue& value) {
    if (const auto* v = std::get_if<double>(&value)) {
      return *v;
    }
    if (const auto* v = std::get_if<std::int64_t>(&value)) {
      return static_cast<double>(*v);
    }
    return 0.0;
  };

  const auto settingValueAsString = [](const WidgetSettingValue& value) {
    if (const auto* v = std::get_if<std::string>(&value)) {
      return *v;
    }
    return std::string{};
  };

  const auto settingValueAsStringList = [](const WidgetSettingValue& value) {
    if (const auto* v = std::get_if<std::vector<std::string>>(&value)) {
      return *v;
    }
    return std::vector<std::string>{};
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
      badge->setBackground(roleColor(ColorRole::Primary, 0.15f));
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

      if (isBarWidgetListPath(entry.path)) {
        static constexpr std::string_view kLanes[] = {"start", "center", "end"};
        const auto currentLane = std::string_view(entry.path.back());
        for (const auto targetLane : kLanes) {
          if (targetLane == currentLane) {
            continue;
          }
          auto moveBtn = std::make_unique<Button>();
          moveBtn->setText(laneLabel(targetLane));
          moveBtn->setVariant(ButtonVariant::Ghost);
          moveBtn->setFontSize(Style::fontSizeCaption * scale);
          moveBtn->setMinHeight(Style::controlHeightSm * scale);
          moveBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
          moveBtn->setRadius(Style::radiusSm * scale);
          auto sourceItems = list.items;
          auto sourcePath = entry.path;
          auto targetPath = pathWithLastSegment(entry.path, std::string(targetLane));
          auto targetItems = barWidgetItemsForPath(cfg, targetPath);
          moveBtn->setOnClick([setOverrides, sourceItems, sourcePath, targetItems, targetPath, i]() mutable {
            if (i >= sourceItems.size()) {
              return;
            }
            auto item = sourceItems[i];
            sourceItems.erase(sourceItems.begin() + static_cast<std::ptrdiff_t>(i));
            targetItems.push_back(std::move(item));
            setOverrides({{sourcePath, sourceItems}, {targetPath, targetItems}});
          });
          itemRow->addChild(std::move(moveBtn));
        }
      }

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

    if (isBarWidgetListPath(entry.path)) {
      const std::string pickerKey = pathKey(entry.path);
      auto addBtn = std::make_unique<Button>();
      addBtn->setText(i18n::tr("settings.add-widget"));
      addBtn->setGlyph("add");
      addBtn->setVariant(ButtonVariant::Ghost);
      addBtn->setGlyphSize(Style::fontSizeCaption * scale);
      addBtn->setFontSize(Style::fontSizeCaption * scale);
      addBtn->setMinHeight(Style::controlHeightSm * scale);
      addBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      addBtn->setRadius(Style::radiusSm * scale);
      addBtn->setOnClick([this, pickerKey, requestRebuild]() {
        m_openWidgetPickerPath = m_openWidgetPickerPath == pickerKey ? std::string{} : pickerKey;
        requestRebuild();
      });
      block->addChild(std::move(addBtn));

      if (m_openWidgetPickerPath == pickerKey) {
        auto picker = std::make_unique<SearchPicker>();
        picker->setPlaceholder(i18n::tr("settings.widget-picker-placeholder"));
        picker->setEmptyText(i18n::tr("settings.widget-picker-empty"));
        picker->setOptions(widgetPickerOptions(cfg));
        picker->setSize(360.0f * scale, 260.0f * scale);
        auto items = list.items;
        auto path = entry.path;
        picker->setOnActivated([this, setOverride, items, path](const SearchPickerOption& option) mutable {
          if (!option.value.empty()) {
            items.push_back(option.value);
            m_openWidgetPickerPath.clear();
            setOverride(path, items);
          }
        });
        picker->setOnCancel([this, requestRebuild]() {
          m_openWidgetPickerPath.clear();
          requestRebuild();
        });
        block->addChild(std::move(picker));
      }
    } else {
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
    }

    section.addChild(std::move(block));
  };

  const auto makeWidgetSettingsPanel = [&](Flex& item, std::string widgetName) {
    const auto widgetType = settings::widgetTypeForReference(cfg, widgetName);
    if (widgetType.empty()) {
      return;
    }

    auto specs = settings::widgetSettingSpecs(widgetType);
    if (specs.empty()) {
      return;
    }

    auto panel = std::make_unique<Flex>();
    panel->setDirection(FlexDirection::Vertical);
    panel->setAlign(FlexAlign::Stretch);
    panel->setGap(Style::spaceXs * scale);
    panel->setPadding(Style::spaceSm * scale);
    panel->setRadius(Style::radiusSm * scale);
    panel->setBackground(roleColor(ColorRole::SurfaceVariant, 0.55f));
    panel->setBorderColor(roleColor(ColorRole::Outline, 0.22f));
    panel->setBorderWidth(Style::borderWidth);

    auto panelHeader = std::make_unique<Flex>();
    panelHeader->setDirection(FlexDirection::Horizontal);
    panelHeader->setAlign(FlexAlign::Center);
    panelHeader->setGap(Style::spaceXs * scale);
    panelHeader->addChild(makeLabel(i18n::tr("settings.widget-settings"), Style::fontSizeCaption * scale,
                                    roleColor(ColorRole::OnSurface), true));
    panelHeader->addChild(
        makeLabel(widgetType, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant), false));
    panel->addChild(std::move(panelHeader));

    std::size_t visibleSpecs = 0;
    for (const auto& spec : specs) {
      if (spec.advanced && !m_showAdvanced) {
        continue;
      }
      const auto path = widgetSettingPath(widgetName, spec.key);
      const bool overridden = m_config != nullptr && m_config->hasOverride(path);
      if (m_showOverriddenOnly && !overridden) {
        continue;
      }

      const auto value = widgetSettingValue(widgetName, spec);
      settings::SettingEntry entry{
          .section = "bar",
          .group = "widget-settings",
          .title = i18n::tr(spec.labelKey),
          .subtitle = i18n::tr(spec.descriptionKey),
          .path = path,
          .control = settings::TextSetting{},
          .advanced = spec.advanced,
          .searchText = {},
      };

      switch (spec.valueType) {
      case settings::WidgetSettingValueType::Bool:
        makeRow(*panel, entry, makeToggle(settingValueAsBool(value), path));
        break;
      case settings::WidgetSettingValueType::Int: {
        const auto minValue = static_cast<float>(spec.minValue.value_or(0.0));
        const auto maxValue = static_cast<float>(spec.maxValue.value_or(100.0));
        makeRow(*panel, entry,
                makeSlider(static_cast<float>(settingValueAsInt(value)), minValue, maxValue,
                           static_cast<float>(spec.step), path, true));
        break;
      }
      case settings::WidgetSettingValueType::Double: {
        const auto minValue = static_cast<float>(spec.minValue.value_or(0.0));
        const auto maxValue = static_cast<float>(spec.maxValue.value_or(1.0));
        makeRow(*panel, entry,
                makeSlider(static_cast<float>(settingValueAsDouble(value)), minValue, maxValue,
                           static_cast<float>(spec.step), path, false));
        break;
      }
      case settings::WidgetSettingValueType::String:
        makeRow(*panel, entry, makeText(settingValueAsString(value), {}, path));
        break;
      case settings::WidgetSettingValueType::StringList:
        makeListBlock(*panel, entry, settings::ListSetting{settingValueAsStringList(value)});
        break;
      case settings::WidgetSettingValueType::Select: {
        std::vector<settings::SelectOption> options;
        options.reserve(spec.options.size());
        for (const auto& option : spec.options) {
          options.push_back(settings::SelectOption{std::string(option.value), i18n::tr(option.labelKey)});
        }
        makeRow(*panel, entry,
                makeSelect(settings::SelectSetting{std::move(options), settingValueAsString(value)}, path));
        break;
      }
      }
      ++visibleSpecs;
    }

    if (visibleSpecs == 0) {
      panel->addChild(makeLabel(i18n::tr("settings.widget-settings-empty"), Style::fontSizeCaption * scale,
                                roleColor(ColorRole::OnSurfaceVariant), false));
    }

    item.addChild(std::move(panel));
  };

  const auto makeBarWidgetLaneEditor = [&](Flex& section, const settings::SettingEntry& entry) {
    if (!isFirstBarWidgetListPath(entry.path)) {
      return;
    }

    auto block = std::make_unique<Flex>();
    block->setDirection(FlexDirection::Vertical);
    block->setAlign(FlexAlign::Stretch);
    block->setGap(Style::spaceSm * scale);
    block->setPadding(2.0f * scale, 0.0f);

    auto titleRow = std::make_unique<Flex>();
    titleRow->setDirection(FlexDirection::Horizontal);
    titleRow->setAlign(FlexAlign::Center);
    titleRow->setGap(Style::spaceSm * scale);
    titleRow->addChild(makeLabel(i18n::tr("settings.bar-widget-editor"), Style::fontSizeBody * scale,
                                 roleColor(ColorRole::OnSurface), false));
    block->addChild(std::move(titleRow));

    block->addChild(makeLabel(i18n::tr("settings.bar-widget-editor-desc"), Style::fontSizeCaption * scale,
                              roleColor(ColorRole::OnSurfaceVariant), false));

    auto lanes = std::make_unique<Flex>();
    lanes->setDirection(FlexDirection::Horizontal);
    lanes->setAlign(FlexAlign::Stretch);
    lanes->setGap(Style::spaceSm * scale);
    lanes->setFillParentMainAxis(true);

    static constexpr std::string_view kLaneKeys[] = {"start", "center", "end"};
    for (const auto laneKey : kLaneKeys) {
      auto lanePath = pathWithLastSegment(entry.path, std::string(laneKey));
      const auto laneItems = barWidgetItemsForPath(cfg, lanePath);
      const bool overridden = m_config != nullptr && m_config->hasOverride(lanePath);

      auto lane = std::make_unique<Flex>();
      lane->setDirection(FlexDirection::Vertical);
      lane->setAlign(FlexAlign::Stretch);
      lane->setGap(Style::spaceXs * scale);
      lane->setPadding(Style::spaceSm * scale);
      lane->setRadius(Style::radiusMd * scale);
      lane->setBackground(roleColor(ColorRole::SurfaceVariant, 0.45f));
      lane->setBorderColor(roleColor(ColorRole::Outline, 0.35f));
      lane->setBorderWidth(Style::borderWidth);
      lane->setFlexGrow(1.0f);
      lane->setMinWidth(180.0f * scale);

      auto laneHeader = std::make_unique<Flex>();
      laneHeader->setDirection(FlexDirection::Horizontal);
      laneHeader->setAlign(FlexAlign::Center);
      laneHeader->setGap(Style::spaceXs * scale);
      laneHeader->addChild(
          makeLabel(laneLabel(laneKey), Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), true));
      if (overridden) {
        auto badge = std::make_unique<Flex>();
        badge->setAlign(FlexAlign::Center);
        badge->setPadding(1.0f * scale, Style::spaceXs * scale);
        badge->setRadius(Style::radiusSm * scale);
        badge->setBackground(roleColor(ColorRole::Primary, 0.15f));
        badge->addChild(makeLabel(i18n::tr("settings.badge-override"), Style::fontSizeCaption * scale,
                                  roleColor(ColorRole::Primary), true));
        laneHeader->addChild(std::move(badge));
      }
      auto laneSpacer = std::make_unique<Flex>();
      laneSpacer->setFlexGrow(1.0f);
      laneHeader->addChild(std::move(laneSpacer));
      if (overridden) {
        laneHeader->addChild(makeResetButton(lanePath));
      }
      lane->addChild(std::move(laneHeader));

      for (std::size_t i = 0; i < laneItems.size(); ++i) {
        const auto info = settings::widgetReferenceInfo(cfg, laneItems[i]);
        auto item = std::make_unique<Flex>();
        item->setDirection(FlexDirection::Vertical);
        item->setAlign(FlexAlign::Stretch);
        item->setGap(Style::spaceXs * scale);
        item->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
        item->setRadius(Style::radiusSm * scale);
        item->setBackground(roleColor(ColorRole::Surface, 0.72f));
        item->setBorderColor(roleColor(ColorRole::Outline, 0.22f));
        item->setBorderWidth(Style::borderWidth);

        auto itemTop = std::make_unique<Flex>();
        itemTop->setDirection(FlexDirection::Horizontal);
        itemTop->setAlign(FlexAlign::Center);
        itemTop->setGap(Style::spaceXs * scale);
        itemTop->addChild(makeLabel(info.title, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurface), true));
        auto itemSpacer = std::make_unique<Flex>();
        itemSpacer->setFlexGrow(1.0f);
        itemTop->addChild(std::move(itemSpacer));
        auto kindBadge = std::make_unique<Flex>();
        kindBadge->setAlign(FlexAlign::Center);
        kindBadge->setPadding(1.0f * scale, Style::spaceXs * scale);
        kindBadge->setRadius(Style::radiusSm * scale);
        kindBadge->setBackground(widgetBadgeColor(info.kind));
        kindBadge->addChild(
            makeLabel(info.badge, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurface), true));
        itemTop->addChild(std::move(kindBadge));
        item->addChild(std::move(itemTop));

        item->addChild(
            makeLabel(info.detail, Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant), false));

        auto actions = std::make_unique<Flex>();
        actions->setDirection(FlexDirection::Horizontal);
        actions->setAlign(FlexAlign::Center);
        actions->setGap(Style::spaceXs * scale);

        const auto widgetName = laneItems[i];
        const bool editableWidget = !settings::widgetTypeForReference(cfg, widgetName).empty();
        if (editableWidget) {
          auto editBtn = std::make_unique<Button>();
          editBtn->setGlyph("settings");
          editBtn->setVariant(m_editingWidgetName == widgetName ? ButtonVariant::Default : ButtonVariant::Ghost);
          editBtn->setGlyphSize(Style::fontSizeCaption * scale);
          editBtn->setMinWidth(Style::controlHeightSm * scale);
          editBtn->setMinHeight(Style::controlHeightSm * scale);
          editBtn->setPadding(Style::spaceXs * scale);
          editBtn->setRadius(Style::radiusSm * scale);
          editBtn->setOnClick([this, widgetName, requestRebuild]() {
            m_editingWidgetName = m_editingWidgetName == widgetName ? std::string{} : widgetName;
            m_openWidgetPickerPath.clear();
            requestRebuild();
          });
          actions->addChild(std::move(editBtn));
        }

        if (i > 0) {
          auto upBtn = std::make_unique<Button>();
          upBtn->setGlyph("chevron-up");
          upBtn->setVariant(ButtonVariant::Ghost);
          upBtn->setGlyphSize(Style::fontSizeCaption * scale);
          upBtn->setMinWidth(Style::controlHeightSm * scale);
          upBtn->setMinHeight(Style::controlHeightSm * scale);
          upBtn->setPadding(Style::spaceXs * scale);
          upBtn->setRadius(Style::radiusSm * scale);
          auto items = laneItems;
          auto path = lanePath;
          upBtn->setOnClick([setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i - 1]);
            setOverride(path, items);
          });
          actions->addChild(std::move(upBtn));
        }
        if (i + 1 < laneItems.size()) {
          auto downBtn = std::make_unique<Button>();
          downBtn->setGlyph("chevron-down");
          downBtn->setVariant(ButtonVariant::Ghost);
          downBtn->setGlyphSize(Style::fontSizeCaption * scale);
          downBtn->setMinWidth(Style::controlHeightSm * scale);
          downBtn->setMinHeight(Style::controlHeightSm * scale);
          downBtn->setPadding(Style::spaceXs * scale);
          downBtn->setRadius(Style::radiusSm * scale);
          auto items = laneItems;
          auto path = lanePath;
          downBtn->setOnClick([setOverride, items, path, i]() mutable {
            std::swap(items[i], items[i + 1]);
            setOverride(path, items);
          });
          actions->addChild(std::move(downBtn));
        }

        for (const auto targetLane : kLaneKeys) {
          if (targetLane == laneKey) {
            continue;
          }
          auto moveBtn = std::make_unique<Button>();
          moveBtn->setText(laneLabel(targetLane));
          moveBtn->setVariant(ButtonVariant::Ghost);
          moveBtn->setFontSize(Style::fontSizeCaption * scale);
          moveBtn->setMinHeight(Style::controlHeightSm * scale);
          moveBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
          moveBtn->setRadius(Style::radiusSm * scale);
          auto sourceItems = laneItems;
          auto sourcePath = lanePath;
          auto targetPath = pathWithLastSegment(entry.path, std::string(targetLane));
          auto targetItems = barWidgetItemsForPath(cfg, targetPath);
          moveBtn->setOnClick([setOverrides, sourceItems, sourcePath, targetItems, targetPath, i]() mutable {
            if (i >= sourceItems.size()) {
              return;
            }
            auto widget = sourceItems[i];
            sourceItems.erase(sourceItems.begin() + static_cast<std::ptrdiff_t>(i));
            targetItems.push_back(std::move(widget));
            setOverrides({{sourcePath, sourceItems}, {targetPath, targetItems}});
          });
          actions->addChild(std::move(moveBtn));
        }

        auto removeBtn = std::make_unique<Button>();
        removeBtn->setGlyph("close");
        removeBtn->setVariant(ButtonVariant::Ghost);
        removeBtn->setGlyphSize(Style::fontSizeCaption * scale);
        removeBtn->setMinWidth(Style::controlHeightSm * scale);
        removeBtn->setMinHeight(Style::controlHeightSm * scale);
        removeBtn->setPadding(Style::spaceXs * scale);
        removeBtn->setRadius(Style::radiusSm * scale);
        auto items = laneItems;
        auto path = lanePath;
        removeBtn->setOnClick([setOverride, items, path, i]() mutable {
          items.erase(items.begin() + static_cast<std::ptrdiff_t>(i));
          setOverride(path, items);
        });
        actions->addChild(std::move(removeBtn));

        item->addChild(std::move(actions));
        if (m_editingWidgetName == widgetName) {
          makeWidgetSettingsPanel(*item, widgetName);
        }
        lane->addChild(std::move(item));
      }

      const std::string pickerKey = pathKey(lanePath);
      auto addBtn = std::make_unique<Button>();
      addBtn->setText(i18n::tr("settings.add-widget"));
      addBtn->setGlyph("add");
      addBtn->setVariant(ButtonVariant::Ghost);
      addBtn->setGlyphSize(Style::fontSizeCaption * scale);
      addBtn->setFontSize(Style::fontSizeCaption * scale);
      addBtn->setMinHeight(Style::controlHeightSm * scale);
      addBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      addBtn->setRadius(Style::radiusSm * scale);
      addBtn->setOnClick([this, pickerKey, requestRebuild]() {
        m_openWidgetPickerPath = m_openWidgetPickerPath == pickerKey ? std::string{} : pickerKey;
        requestRebuild();
      });
      lane->addChild(std::move(addBtn));

      if (m_openWidgetPickerPath == pickerKey) {
        auto picker = std::make_unique<SearchPicker>();
        picker->setPlaceholder(i18n::tr("settings.widget-picker-placeholder"));
        picker->setEmptyText(i18n::tr("settings.widget-picker-empty"));
        picker->setOptions(widgetPickerOptions(cfg));
        picker->setSize(320.0f * scale, 250.0f * scale);
        auto items = laneItems;
        auto path = lanePath;
        picker->setOnActivated([this, setOverride, items, path](const SearchPickerOption& option) mutable {
          if (!option.value.empty()) {
            items.push_back(option.value);
            m_openWidgetPickerPath.clear();
            setOverride(path, items);
          }
        });
        picker->setOnCancel([this, requestRebuild]() {
          m_openWidgetPickerPath.clear();
          requestRebuild();
        });
        lane->addChild(std::move(picker));
      }

      lanes->addChild(std::move(lane));
    }

    block->addChild(std::move(lanes));
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
        if (isFirstBarWidgetListPath(entry.path)) {
          makeBarWidgetLaneEditor(*activeSection, entry);
        } else if (!isBarWidgetListPath(entry.path)) {
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
    emptyState->setBackground(roleColor(ColorRole::SurfaceVariant, 0.24f));
    emptyState->setBorderColor(roleColor(ColorRole::Outline, 0.28f));
    emptyState->setBorderWidth(Style::borderWidth);
    emptyState->setRadius(Style::radiusMd * scale);
    emptyState->addChild(
        makeLabel(i18n::tr("settings.no-results"), Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), true));
    emptyState->addChild(makeLabel(i18n::tr("settings.no-results-hint"), Style::fontSizeCaption * scale,
                                   roleColor(ColorRole::OnSurfaceVariant), false));
    content->addChild(std::move(emptyState));
  }

  body->addChild(std::move(scroll));
  main->addChild(std::move(body));

  main->setSize(w, h);
  main->layout(*m_renderContext);

  m_sceneRoot->addChild(std::move(main));

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
    if (!m_openWidgetPickerPath.empty()) {
      m_openWidgetPickerPath.clear();
      requestRebuild();
      return;
    }
    if (!m_editingWidgetName.empty()) {
      m_editingWidgetName.clear();
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
