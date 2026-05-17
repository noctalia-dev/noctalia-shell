#include "compositors/compositor_detect.h"
#include "config/config_service.h"
#include "core/process.h"
#include "core/ui_phase.h"
#include "dbus/upower/upower_service.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "shell/settings/settings_content.h"
#include "shell/settings/settings_entity_editor.h"
#include "shell/settings/settings_sidebar.h"
#include "shell/settings/settings_window.h"
#include "system/dependency_service.h"
#include "theme/community_palettes.h"
#include "theme/community_templates.h"
#include "theme/custom_palettes.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select_dropdown_popup.h"
#include "ui/controls/separator.h"
#include "ui/controls/spacer.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/toplevel_surface.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

  constexpr float kBodyMaxWidth = 1280.0f;

  std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ColorSpec& color, bool bold = false) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(fontSize);
    label->setColor(color);
    label->setBold(bold);
    return label;
  }

  std::unique_ptr<Flex> centeredRow(std::unique_ptr<Flex> child, float scale) {
    child->setFlexGrow(1.0f);
    child->setMaxWidth(kBodyMaxWidth * scale);
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Stretch);
    row->setJustify(FlexJustify::Center);
    row->addChild(std::move(child));
    return row;
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

  std::string upowerDeviceLabel(const UPowerDeviceInfo& device) {
    const std::string nativeName =
        !device.nativePath.empty() ? StringUtils::pathTail(device.nativePath) : StringUtils::pathTail(device.path);

    std::string label;
    if (!device.vendor.empty() && !device.model.empty()) {
      label = device.vendor + " " + device.model;
    } else if (!device.model.empty()) {
      label = device.model;
    } else if (!device.vendor.empty()) {
      label = device.vendor;
    } else {
      label = nativeName;
    }

    if (!nativeName.empty() && label != nativeName) {
      label += " (" + nativeName + ")";
    }
    return label;
  }

  std::vector<settings::SelectOption> upowerBatteryDeviceOptions(UPowerService* upower) {
    std::vector<settings::SelectOption> options;
    options.push_back(settings::SelectOption{.value = "auto", .label = i18n::tr("common.states.auto")});
    if (upower == nullptr) {
      return options;
    }

    const auto devices = upower->batteryDevices();
    options.reserve(devices.size() + 1);
    for (const auto& device : devices) {
      std::string description = device.path;
      if (!device.nativePath.empty() && device.nativePath != device.path) {
        description = device.nativePath + " - " + device.path;
      }
      options.push_back(settings::SelectOption{
          .value = device.path,
          .label = upowerDeviceLabel(device),
          .description = std::move(description),
      });
    }
    return options;
  }

  std::vector<settings::SelectOption> discoverFontFamilyOptions() {
    std::vector<settings::SelectOption> options;
    if (!process::commandExists("fc-list")) {
      return options;
    }

    const auto result = process::runSync({"fc-list", ":", "family"});
    if (!result) {
      return options;
    }

    std::unordered_set<std::string> seen;
    seen.reserve(4096);

    std::size_t lineStart = 0;
    while (lineStart <= result.out.size()) {
      const std::size_t lineEnd = result.out.find('\n', lineStart);
      const std::string_view line = lineEnd == std::string::npos
                                        ? std::string_view(result.out).substr(lineStart)
                                        : std::string_view(result.out).substr(lineStart, lineEnd - lineStart);

      std::size_t tokenStart = 0;
      while (tokenStart <= line.size()) {
        const std::size_t tokenEnd = line.find(',', tokenStart);
        const std::string_view token =
            tokenEnd == std::string::npos ? line.substr(tokenStart) : line.substr(tokenStart, tokenEnd - tokenStart);
        const std::string family = StringUtils::trim(std::string(token));
        if (!family.empty()) {
          seen.insert(family);
        }
        if (tokenEnd == std::string::npos) {
          break;
        }
        tokenStart = tokenEnd + 1;
      }

      if (lineEnd == std::string::npos) {
        break;
      }
      lineStart = lineEnd + 1;
    }

    std::vector<std::string> sortedFamilies;
    sortedFamilies.reserve(seen.size());
    for (const auto& family : seen) {
      sortedFamilies.push_back(family);
    }
    std::sort(sortedFamilies.begin(), sortedFamilies.end(), [](const std::string& a, const std::string& b) {
      return StringUtils::toLower(a) < StringUtils::toLower(b);
    });

    options.reserve(sortedFamilies.size());
    for (const auto& family : sortedFamilies) {
      options.push_back(settings::SelectOption{family, family});
    }

    return options;
  }

} // namespace

void SettingsWindow::applyPendingContentScrollTarget(float margin) {
  if (!m_scrollToPendingContentTarget) {
    return;
  }

  auto clearPending = [this]() {
    m_scrollToPendingContentTarget = false;
    m_pendingContentScrollTarget = nullptr;
  };

  if (m_contentScrollView == nullptr || m_contentScrollView->content() == nullptr ||
      m_pendingContentScrollTarget == nullptr) {
    clearPending();
    return;
  }

  const float viewportHeight =
      std::max(0.0f, m_contentScrollView->height() - m_contentScrollView->viewportPaddingV() * 2.0f);
  if (viewportHeight <= 0.0f) {
    clearPending();
    return;
  }

  float targetX = 0.0f;
  float targetY = 0.0f;
  float contentX = 0.0f;
  float contentY = 0.0f;
  Node::absolutePosition(m_pendingContentScrollTarget, targetX, targetY);
  Node::absolutePosition(m_contentScrollView->content(), contentX, contentY);
  (void)targetX;
  (void)contentX;

  const float targetTop = std::max(0.0f, targetY - contentY - margin);
  const float targetBottom = targetY - contentY + m_pendingContentScrollTarget->height() + margin;
  const float currentTop = m_contentScrollView->scrollOffset();
  const float currentBottom = currentTop + viewportHeight;

  float desiredOffset = currentTop;
  if (targetBottom - targetTop >= viewportHeight) {
    desiredOffset = targetTop;
  } else if (targetTop < currentTop) {
    desiredOffset = targetTop;
  } else if (targetBottom > currentBottom) {
    desiredOffset = targetBottom - viewportHeight;
  }

  m_contentScrollView->setScrollOffset(desiredOffset);
  m_contentScrollState.offset = m_contentScrollView->scrollOffset();
  clearPending();
}

settings::RegistryEnvironment SettingsWindow::buildRegistryEnvironment() const {
  settings::RegistryEnvironment env;
  env.niriBackdropSupported = (m_wayland != nullptr && compositors::isNiri());
  env.ddcutilAvailable = (m_dependencies != nullptr && m_dependencies->hasDdcutil());
  env.gammaControlAvailable = (m_wayland != nullptr && m_wayland->hasGammaControl());
  for (const auto& paletteInfo : noctalia::theme::availableCommunityPalettes()) {
    env.communityPalettes.push_back(settings::SelectOption{paletteInfo.name, paletteInfo.name});
  }
  for (const auto& p : noctalia::theme::availableCustomPalettes()) {
    env.customPalettes.push_back(settings::SelectOption{p.name, p.name});
  }
  for (const auto& t : noctalia::theme::CommunityTemplateService::availableTemplates()) {
    env.communityTemplates.push_back(settings::SelectOption{t.id, t.displayName});
  }
  static const std::vector<settings::SelectOption> kFontFamilies = discoverFontFamilyOptions();
  env.fontFamilies = kFontFamilies;
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
  return env;
}

void SettingsWindow::syncSelectedBarState(const Config& cfg, const std::vector<std::string>& availableBars) {
  if (availableBars.empty()) {
    m_selectedBarName.clear();
  } else if (settings::findBar(cfg, m_selectedBarName) == nullptr) {
    m_selectedBarName = availableBars.front();
  }

  const BarConfig* selectedBar = settings::findBar(cfg, m_selectedBarName);
  if (selectedBar != nullptr && !m_selectedMonitorOverride.empty() &&
      settings::findMonitorOverride(*selectedBar, m_selectedMonitorOverride) == nullptr) {
    m_selectedMonitorOverride.clear();
  }
}

std::vector<settings::SelectOption> SettingsWindow::batteryDeviceOptions() const {
  return upowerBatteryDeviceOptions(m_upower);
}

settings::SettingsContentContext SettingsWindow::makeContentContext(const Config& cfg, const BarConfig* selectedBar,
                                                                    const BarMonitorOverride* selectedMonitorOverride) {
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

  return settings::SettingsContentContext{
      .config = cfg,
      .configService = m_config,
      .scale = uiScale(),
      .searchQuery = m_searchQuery,
      .selectedSection = m_selectedSection,
      .selectedBar = selectedBar,
      .selectedMonitorOverride = selectedMonitorOverride,
      .showAdvanced = m_showAdvanced,
      .showOverriddenOnly = m_showOverriddenOnly,
      .batteryDeviceOptions = batteryDeviceOptions(),
      .openWidgetPickerPath = m_openWidgetPickerPath,
      .editingWidgetName = m_editingWidgetName,
      .pendingDeleteWidgetName = m_pendingDeleteWidgetName,
      .pendingDeleteWidgetSettingPath = m_pendingDeleteWidgetSettingPath,
      .renamingWidgetName = m_renamingWidgetName,
      .creatingWidgetType = m_creatingWidgetType,
      .requestRebuild = requestRebuild,
      .requestContentRebuild = requestContent,
      .resetContentScroll = [this]() { m_contentScrollState.offset = 0.0f; },
      .setScrollTarget = [this](Node* target) { m_pendingContentScrollTarget = target; },
      .focusArea = [this](InputArea* area) { m_inputDispatcher.setFocus(area); },
      .openBarWidgetAddPopup = [this](const std::vector<std::string>& lanePath) { openBarWidgetAddPopup(lanePath); },
      .openSearchPickerPopup =
          [this](const std::string& title, const std::vector<settings::SelectOption>& options,
                 const std::string& selectedValue, const std::string& placeholder, const std::string& emptyText,
                 const std::vector<std::string>& settingPath) {
            openSearchPickerPopup(title, options, selectedValue, placeholder, emptyText, settingPath);
          },
      .setOverride = setOverride,
      .setOverrides = setOverrides,
      .clearOverride = clearOverride,
      .renameWidgetInstance = renameWidget,
      .openSessionActionEntryEditor = [this](std::size_t entryIndex) { openSessionActionEntryEditor(entryIndex); },
      .openIdleBehaviorEntryEditor = [this](std::size_t entryIndex) { openIdleBehaviorEntryEditor(entryIndex); },
      .openIdleBehaviorCreateEditor = [this]() { openIdleBehaviorCreateEditor(); },
      .registerIdleLiveStatusLabel =
          [this](Label* label) {
            m_idleLiveStatusLabel = label;
            refreshIdleLiveStatusText();
          },
      .afterSessionActionsCommit = {},
      .afterIdleBehaviorApply = {},
      .closeHostedEditor = {},
  };
}

void SettingsWindow::rebuildSettingsContent() {
  uiAssertNotRendering("SettingsWindow::rebuildSettingsContent");
  if (m_contentContainer == nullptr) {
    return;
  }

  m_pendingContentScrollTarget = nullptr;
  m_idleLiveStatusLabel = nullptr;
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
          .requestRebuild = [this]() { requestSceneRebuild(); },
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
                                       makeContentContext(cfg, selectedBar, selectedMonitorOverride));
}

std::unique_ptr<Flex> SettingsWindow::buildHeaderRow(float scale) {
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
  header->addChild(std::move(headerTitle));

  auto actionsMenuBtn = std::make_unique<Button>();
  actionsMenuBtn->setGlyph("more-vertical");
  actionsMenuBtn->setVariant(ButtonVariant::Ghost);
  actionsMenuBtn->setGlyphSize(Style::fontSizeBody * scale);
  actionsMenuBtn->setMinWidth(Style::controlHeightSm * scale);
  actionsMenuBtn->setMinHeight(Style::controlHeightSm * scale);
  actionsMenuBtn->setPadding(Style::spaceXs * scale);
  actionsMenuBtn->setRadius(Style::scaledRadiusMd(scale));
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
  closeBtn->setRadius(Style::scaledRadiusMd(scale));
  closeBtn->setOnClick([this]() { close(); });
  header->addChild(std::move(closeBtn));

  return header;
}

std::unique_ptr<Flex> SettingsWindow::buildFilterRow(float scale, const std::string& resetPageScope,
                                                     std::vector<std::vector<std::string>> resetPagePaths) {
  const auto requestRebuild = [this]() { requestSceneRebuild(); };
  const auto clearOverrides = [this](std::vector<std::vector<std::string>> paths) {
    clearSettingOverrides(std::move(paths));
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
      markSettingsWriteError(i18n::tr("settings.errors.write"));
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
    resetPageBtn->setRadius(Style::scaledRadiusMd(scale));
    resetPageBtn->setOnClick([this, resetPageScope, resetPagePaths = std::move(resetPagePaths), requestRebuild,
                              clearOverrides, pendingReset]() mutable {
      if (!pendingReset) {
        m_pendingResetPageScope = resetPageScope;
        requestRebuild();
        return;
      }
      clearOverrides(std::move(resetPagePaths));
    });
    filters->addChild(std::move(resetPageBtn));
  }

  if (m_focusSearchOnRebuild && searchInputPtr != nullptr && searchInputPtr->inputArea() != nullptr) {
    m_inputDispatcher.setFocus(searchInputPtr->inputArea());
    m_focusSearchOnRebuild = false;
  }

  return filters;
}

std::unique_ptr<Flex> SettingsWindow::buildStatusRow(float scale) {
  if (m_statusMessage.empty()) {
    return nullptr;
  }

  const auto requestRebuild = [this]() { requestSceneRebuild(); };
  const auto clearStatus = [this]() { clearStatusMessage(); };

  auto status = std::make_unique<Flex>();
  status->setDirection(FlexDirection::Horizontal);
  status->setAlign(FlexAlign::Center);
  status->setGap(Style::spaceSm * scale);
  status->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
  status->setRadius(Style::scaledRadiusMd(scale));
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
  dismiss->setRadius(Style::scaledRadiusSm(scale));
  dismiss->setOnClick([clearStatus, requestRebuild]() {
    clearStatus();
    requestRebuild();
  });
  status->addChild(std::move(dismiss));

  return status;
}

std::unique_ptr<Flex> SettingsWindow::buildBody(float scale, const Config& cfg,
                                                const std::vector<std::string>& sections,
                                                const std::vector<std::string>& availableBars) {
  const auto requestRebuild = [this]() { requestSceneRebuild(); };
  const auto createBar = [this](std::string name) { this->createBar(std::move(name)); };
  const auto createMonitorOverride = [this](std::string barName, std::string match) {
    this->createMonitorOverride(std::move(barName), std::move(match));
  };
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
  body->addChild(std::make_unique<Separator>());

  auto scroll = std::make_unique<ScrollView>();
  scroll->bindState(&m_contentScrollState);
  scroll->setFlexGrow(1.0f);
  scroll->setScrollbarVisible(true);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(Style::spaceSm * scale);
  scroll->clearFill();
  scroll->clearBorder();
  m_contentScrollView = scroll.get();

  auto* content = scroll->content();
  m_contentContainer = content;
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceMd * scale);
  rebuildSettingsContent();

  body->addChild(std::move(scroll));
  return body;
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
  m_contentScrollView = nullptr;

  const Config fallbackCfg{};
  const Config& cfg = m_config != nullptr ? m_config->config() : fallbackCfg;
  const auto availableBars = settings::barNames(cfg);
  syncSelectedBarState(cfg, availableBars);

  const BarConfig* selectedBar = settings::findBar(cfg, m_selectedBarName);
  const BarMonitorOverride* selectedMonitorOverride = nullptr;
  if (selectedBar != nullptr && !m_selectedMonitorOverride.empty()) {
    selectedMonitorOverride = settings::findMonitorOverride(*selectedBar, m_selectedMonitorOverride);
  }

  m_settingsRegistry =
      settings::buildSettingsRegistry(cfg, selectedBar, selectedMonitorOverride, buildRegistryEnvironment());

  if (m_openWallpaperPanel) {
    auto it = std::find_if(m_settingsRegistry.begin(), m_settingsRegistry.end(), [](const settings::SettingEntry& e) {
      return e.section == "wallpaper" && e.group == "general" &&
             e.path == std::vector<std::string>{"wallpaper", "fill_mode"};
    });
    settings::SettingEntry btn{
        .section = "wallpaper",
        .group = "general",
        .title = i18n::tr("settings.schema.wallpaper.panel.label"),
        .subtitle = i18n::tr("settings.schema.wallpaper.panel.description"),
        .path = {},
        .control = settings::ButtonSetting{.label = i18n::tr("settings.schema.wallpaper.panel.button"),
                                           .action = m_openWallpaperPanel,
                                           .glyph = "wallpaper-selector"},
        .searchText = "wallpaper panel open selector browse",
        .visibleWhen = std::nullopt,
    };
    m_settingsRegistry.insert(it, std::move(btn));
  }

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
        .control = settings::ButtonSetting{.label = i18n::tr("settings.schema.desktop.widgets-editor.button"),
                                           .action = m_openDesktopWidgetEditor,
                                           .glyph = {}},
        .searchText = "desktop widgets editor edit",
        .visibleWhen = std::nullopt,
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
          m_config->hasEffectiveOverride(entry.path) && !containsPath(resetPagePaths, entry.path)) {
        resetPagePaths.push_back(entry.path);
      }
    }
  }
  if (m_pendingResetPageScope != resetPageScope) {
    m_pendingResetPageScope.clear();
  }

  m_inputDispatcher.setSceneRoot(nullptr);
  m_mainContainer = nullptr;
  m_headerRow = nullptr;
  m_panelBackground = nullptr;
  m_contentContainer = nullptr;
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setSize(w, h);
  m_sceneRoot->setAnimationManager(&m_animations);
  if (m_surface != nullptr && m_renderContext != nullptr && m_wayland != nullptr) {
    m_selectPopup = std::make_unique<SelectDropdownPopup>(*m_wayland, *m_renderContext);
    m_selectPopup->setShadowConfig(cfg.shell.shadow);
    m_selectPopup->setParent(m_surface->xdgSurface(), m_output);
    m_sceneRoot->setPopupContext(m_selectPopup.get());
  }

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

  m_headerRow = main->addChild(centeredRow(buildHeaderRow(scale), scale));
  main->addChild(centeredRow(buildFilterRow(scale, resetPageScope, std::move(resetPagePaths)), scale));
  if (auto status = buildStatusRow(scale)) {
    main->addChild(centeredRow(std::move(status), scale));
  }

  auto bodyRow = centeredRow(buildBody(scale, cfg, sections, availableBars), scale);
  bodyRow->setFlexGrow(1.0f);
  main->addChild(std::move(bodyRow));

  main->setSize(w, h);
  main->layout(*m_renderContext);
  applyPendingContentScrollTarget(Style::spaceMd * scale);
  m_mainContainer = static_cast<Flex*>(m_sceneRoot->addChild(std::move(main)));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());
}
