#include "shell/settings/settings_sidebar.h"

#include "i18n/i18n.h"
#include "shell/settings/settings_registry.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cctype>
#include <format>
#include <string_view>
#include <utility>

namespace settings {
  namespace {

    std::string normalizedConfigId(std::string_view text) { return StringUtils::trim(text); }

    bool isValidConfigId(std::string_view text) {
      const auto trimmed = StringUtils::trim(text);
      if (trimmed.empty()) {
        return false;
      }
      return std::all_of(trimmed.begin(), trimmed.end(),
                         [](unsigned char c) { return std::isalnum(c) != 0 || c == '_' || c == '-'; });
    }

    bool barNameExists(const Config& cfg, std::string_view name) {
      return std::any_of(cfg.bars.begin(), cfg.bars.end(), [name](const BarConfig& bar) { return bar.name == name; });
    }

    std::string nextAvailableBarName(const Config& cfg) {
      for (std::size_t i = 1;; ++i) {
        const std::string candidate = i == 1 ? "bar" : std::format("bar_{}", i);
        if (!barNameExists(cfg, candidate)) {
          return candidate;
        }
      }
    }

  } // namespace

  std::unique_ptr<Flex> buildSettingsSidebar(SettingsSidebarContext ctx) {
    const Config cfg = ctx.config;
    const auto sectionLabel = [](std::string_view section) {
      return i18n::tr("settings.section." + std::string(section));
    };

    auto* scroll = &ctx.contentScrollState;
    auto* selectedSection = &ctx.selectedSection;
    auto* selectedBarName = &ctx.selectedBarName;
    auto* selectedMonitorOverride = &ctx.selectedMonitorOverride;
    auto* creatingBarName = &ctx.creatingBarName;
    auto* creatingMonitorOverrideBarName = &ctx.creatingMonitorOverrideBarName;
    auto* creatingMonitorOverrideMatch = &ctx.creatingMonitorOverrideMatch;

    const auto clearTransientState = std::move(ctx.clearTransientState);
    const auto requestRebuild = std::move(ctx.requestRebuild);
    const auto createBar = std::move(ctx.createBar);
    const auto createMonitorOverride = std::move(ctx.createMonitorOverride);
    const float scale = ctx.scale;

    auto sidebar = std::make_unique<Flex>();
    sidebar->setDirection(FlexDirection::Vertical);
    sidebar->setAlign(FlexAlign::Stretch);
    sidebar->setGap(Style::spaceXs * scale);
    sidebar->setSize(132.0f * scale, 0.0f);
    sidebar->setMinWidth(132.0f * scale);
    sidebar->setPadding(Style::spaceXs * scale, 0.0f);

    for (const auto& section : ctx.sections) {
      const bool selected = section == *selectedSection;
      auto navItem = std::make_unique<Button>();
      navItem->setText(sectionLabel(section));
      navItem->setVariant(selected ? ButtonVariant::TabActive : ButtonVariant::Tab);
      navItem->setContentAlign(ButtonContentAlign::Start);
      navItem->setFontSize(Style::fontSizeBody * scale);
      navItem->setMinHeight(Style::controlHeight * scale);
      navItem->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      navItem->setRadius(Style::radiusMd * scale);
      navItem->setOnClick([selectedSection, scroll, section, clearTransientState, requestRebuild]() {
        if (*selectedSection != section) {
          scroll->offset = 0.0f;
        }
        *selectedSection = section;
        clearTransientState();
        requestRebuild();
      });
      sidebar->addChild(std::move(navItem));
    }

    for (const auto& barName : ctx.availableBars) {
      const bool barSelected =
          *selectedSection == "bar" && *selectedBarName == barName && selectedMonitorOverride->empty();
      auto navItem = std::make_unique<Button>();
      navItem->setText(i18n::tr("settings.bar-label", "name", barName));
      navItem->setVariant(barSelected ? ButtonVariant::TabActive : ButtonVariant::Tab);
      navItem->setContentAlign(ButtonContentAlign::Start);
      navItem->setFontSize(Style::fontSizeBody * scale);
      navItem->setMinHeight(Style::controlHeight * scale);
      navItem->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      navItem->setRadius(Style::radiusMd * scale);
      navItem->setOnClick([selectedSection, selectedBarName, selectedMonitorOverride, scroll, barName,
                           clearTransientState, requestRebuild]() {
        if (*selectedSection != "bar" || *selectedBarName != barName || !selectedMonitorOverride->empty()) {
          scroll->offset = 0.0f;
        }
        *selectedSection = "bar";
        *selectedBarName = barName;
        selectedMonitorOverride->clear();
        clearTransientState();
        requestRebuild();
      });
      sidebar->addChild(std::move(navItem));

      const auto* bar = settings::findBar(cfg, barName);
      if (bar == nullptr) {
        continue;
      }

      for (const auto& ovr : bar->monitorOverrides) {
        const bool ovrSelected =
            *selectedSection == "bar" && *selectedBarName == barName && *selectedMonitorOverride == ovr.match;
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
        ovrItem->setOnClick([selectedSection, selectedBarName, selectedMonitorOverride, scroll, barName, match,
                             clearTransientState, requestRebuild]() {
          if (*selectedSection != "bar" || *selectedBarName != barName || *selectedMonitorOverride != match) {
            scroll->offset = 0.0f;
          }
          *selectedSection = "bar";
          *selectedBarName = barName;
          *selectedMonitorOverride = match;
          clearTransientState();
          requestRebuild();
        });
        sidebar->addChild(std::move(ovrItem));
      }

      if (*selectedSection != "bar" || *selectedBarName != barName) {
        continue;
      }

      auto newMonitorBtn = std::make_unique<Button>();
      newMonitorBtn->setText(i18n::tr("settings.new-monitor-override"));
      newMonitorBtn->setGlyph("add");
      newMonitorBtn->setVariant(ButtonVariant::Ghost);
      newMonitorBtn->setContentAlign(ButtonContentAlign::Start);
      newMonitorBtn->setFontSize(Style::fontSizeCaption * scale);
      newMonitorBtn->setGlyphSize(Style::fontSizeCaption * scale);
      newMonitorBtn->setMinHeight(Style::controlHeightSm * scale);
      newMonitorBtn->setPadding(Style::spaceXs * scale, Style::spaceMd * scale, Style::spaceXs * scale,
                                Style::spaceLg * scale);
      newMonitorBtn->setRadius(Style::radiusMd * scale);
      newMonitorBtn->setOnClick([creatingMonitorOverrideBarName, creatingMonitorOverrideMatch, barName,
                                 clearTransientState, requestRebuild]() {
        clearTransientState();
        *creatingMonitorOverrideBarName = barName;
        creatingMonitorOverrideMatch->clear();
        requestRebuild();
      });
      sidebar->addChild(std::move(newMonitorBtn));

      if (*creatingMonitorOverrideBarName != barName) {
        continue;
      }

      auto createPanel = std::make_unique<Flex>();
      createPanel->setDirection(FlexDirection::Vertical);
      createPanel->setAlign(FlexAlign::Stretch);
      createPanel->setGap(Style::spaceXs * scale);
      createPanel->setPadding(0.0f, Style::spaceXs * scale, 0.0f, Style::spaceLg * scale);

      auto input = std::make_unique<Input>();
      input->setValue(*creatingMonitorOverrideMatch);
      input->setPlaceholder(i18n::tr("settings.monitor-match-placeholder"));
      input->setFontSize(Style::fontSizeCaption * scale);
      input->setControlHeight(Style::controlHeightSm * scale);
      input->setHorizontalPadding(Style::spaceXs * scale);
      input->setSize(112.0f * scale, Style::controlHeightSm * scale);
      auto* inputPtr = input.get();

      std::vector<std::string> existingMatches;
      existingMatches.reserve(bar->monitorOverrides.size());
      for (const auto& monitorOverride : bar->monitorOverrides) {
        existingMatches.push_back(monitorOverride.match);
      }

      auto doCreate = [barName, createMonitorOverride, inputPtr,
                       existingMatches = std::move(existingMatches)](std::string rawMatch) {
        const std::string match = normalizedConfigId(rawMatch);
        if (match.empty() ||
            std::find(existingMatches.begin(), existingMatches.end(), match) != existingMatches.end()) {
          inputPtr->setInvalid(true);
          return;
        }
        inputPtr->setInvalid(false);
        createMonitorOverride(barName, match);
      };

      input->setOnChange([creatingMonitorOverrideMatch, inputPtr](const std::string& value) {
        *creatingMonitorOverrideMatch = value;
        inputPtr->setInvalid(false);
      });
      input->setOnSubmit([doCreate](const std::string& text) mutable { doCreate(text); });

      auto actions = std::make_unique<Flex>();
      actions->setDirection(FlexDirection::Horizontal);
      actions->setAlign(FlexAlign::Center);
      actions->setGap(Style::spaceXs * scale);

      auto saveBtn = std::make_unique<Button>();
      saveBtn->setText(i18n::tr("settings.create-monitor-override"));
      saveBtn->setVariant(ButtonVariant::Default);
      saveBtn->setFontSize(Style::fontSizeCaption * scale);
      saveBtn->setMinHeight(Style::controlHeightSm * scale);
      saveBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      saveBtn->setRadius(Style::radiusSm * scale);
      saveBtn->setOnClick([doCreate, inputPtr]() mutable { doCreate(inputPtr->value()); });
      actions->addChild(std::move(saveBtn));

      auto cancelBtn = std::make_unique<Button>();
      cancelBtn->setGlyph("close");
      cancelBtn->setVariant(ButtonVariant::Ghost);
      cancelBtn->setGlyphSize(Style::fontSizeCaption * scale);
      cancelBtn->setMinWidth(Style::controlHeightSm * scale);
      cancelBtn->setMinHeight(Style::controlHeightSm * scale);
      cancelBtn->setPadding(Style::spaceXs * scale);
      cancelBtn->setRadius(Style::radiusSm * scale);
      cancelBtn->setOnClick([creatingMonitorOverrideBarName, creatingMonitorOverrideMatch, requestRebuild]() {
        creatingMonitorOverrideBarName->clear();
        creatingMonitorOverrideMatch->clear();
        requestRebuild();
      });
      actions->addChild(std::move(cancelBtn));

      createPanel->addChild(std::move(input));
      createPanel->addChild(std::move(actions));
      sidebar->addChild(std::move(createPanel));
    }

    auto newBarBtn = std::make_unique<Button>();
    newBarBtn->setText(i18n::tr("settings.new-bar"));
    newBarBtn->setGlyph("add");
    newBarBtn->setVariant(ButtonVariant::Ghost);
    newBarBtn->setContentAlign(ButtonContentAlign::Start);
    newBarBtn->setFontSize(Style::fontSizeBody * scale);
    newBarBtn->setGlyphSize(Style::fontSizeBody * scale);
    newBarBtn->setMinHeight(Style::controlHeight * scale);
    newBarBtn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    newBarBtn->setRadius(Style::radiusMd * scale);
    newBarBtn->setOnClick([creatingBarName, cfg, clearTransientState, requestRebuild]() {
      clearTransientState();
      *creatingBarName = nextAvailableBarName(cfg);
      requestRebuild();
    });
    sidebar->addChild(std::move(newBarBtn));

    if (!creatingBarName->empty()) {
      auto createPanel = std::make_unique<Flex>();
      createPanel->setDirection(FlexDirection::Vertical);
      createPanel->setAlign(FlexAlign::Stretch);
      createPanel->setGap(Style::spaceXs * scale);
      createPanel->setPadding(0.0f, Style::spaceXs * scale);

      auto input = std::make_unique<Input>();
      input->setValue(*creatingBarName);
      input->setPlaceholder(i18n::tr("settings.bar-id-placeholder"));
      input->setFontSize(Style::fontSizeCaption * scale);
      input->setControlHeight(Style::controlHeightSm * scale);
      input->setHorizontalPadding(Style::spaceXs * scale);
      input->setSize(120.0f * scale, Style::controlHeightSm * scale);
      auto* inputPtr = input.get();

      auto doCreate = [cfg, createBar, inputPtr](std::string rawName) {
        const std::string name = normalizedConfigId(rawName);
        if (!isValidConfigId(name) || barNameExists(cfg, name)) {
          inputPtr->setInvalid(true);
          return;
        }
        inputPtr->setInvalid(false);
        createBar(name);
      };

      input->setOnChange([creatingBarName, inputPtr](const std::string& value) {
        *creatingBarName = value;
        inputPtr->setInvalid(false);
      });
      input->setOnSubmit([doCreate](const std::string& text) mutable { doCreate(text); });

      auto actions = std::make_unique<Flex>();
      actions->setDirection(FlexDirection::Horizontal);
      actions->setAlign(FlexAlign::Center);
      actions->setGap(Style::spaceXs * scale);

      auto saveBtn = std::make_unique<Button>();
      saveBtn->setText(i18n::tr("settings.create-bar"));
      saveBtn->setVariant(ButtonVariant::Default);
      saveBtn->setFontSize(Style::fontSizeCaption * scale);
      saveBtn->setMinHeight(Style::controlHeightSm * scale);
      saveBtn->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      saveBtn->setRadius(Style::radiusSm * scale);
      saveBtn->setOnClick([doCreate, inputPtr]() mutable { doCreate(inputPtr->value()); });
      actions->addChild(std::move(saveBtn));

      auto cancelBtn = std::make_unique<Button>();
      cancelBtn->setGlyph("close");
      cancelBtn->setVariant(ButtonVariant::Ghost);
      cancelBtn->setGlyphSize(Style::fontSizeCaption * scale);
      cancelBtn->setMinWidth(Style::controlHeightSm * scale);
      cancelBtn->setMinHeight(Style::controlHeightSm * scale);
      cancelBtn->setPadding(Style::spaceXs * scale);
      cancelBtn->setRadius(Style::radiusSm * scale);
      cancelBtn->setOnClick([creatingBarName, requestRebuild]() {
        creatingBarName->clear();
        requestRebuild();
      });
      actions->addChild(std::move(cancelBtn));

      createPanel->addChild(std::move(input));
      createPanel->addChild(std::move(actions));
      sidebar->addChild(std::move(createPanel));
    }

    return sidebar;
  }

} // namespace settings
