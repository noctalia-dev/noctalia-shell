#include "shell/settings/settings_sidebar.h"

#include "i18n/i18n.h"
#include "shell/settings/settings_registry.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cctype>
#include <format>
#include <string_view>
#include <utility>
#include <vector>

namespace settings {
  namespace {

    constexpr float kSidebarWidth = 180.0f;

    std::string normalizedConfigId(std::string_view text) { return StringUtils::trim(text); }

    bool isValidConfigId(std::string_view text) {
      const auto trimmed = StringUtils::trim(text);
      if (trimmed.empty()) {
        return false;
      }
      return std::all_of(trimmed.begin(), trimmed.end(),
                         [](unsigned char c) { return std::isalnum(c) != 0 || c == '_' || c == '-'; });
    }

    bool barNameExists(const std::vector<std::string>& barNames, std::string_view name) {
      return std::any_of(barNames.begin(), barNames.end(),
                         [name](const std::string& barName) { return barName == name; });
    }

    std::string nextAvailableBarName(const std::vector<std::string>& barNames) {
      for (std::size_t i = 1;; ++i) {
        const std::string candidate = i == 1 ? "bar" : std::format("bar_{}", i);
        if (!barNameExists(barNames, candidate)) {
          return candidate;
        }
      }
    }

    void applyPrimaryNavStyle(Button& button, float scale, bool selected) {
      button.setVariant(selected ? ButtonVariant::TabActive : ButtonVariant::Tab);
      button.setContentAlign(ButtonContentAlign::Start);
      button.setFontSize(Style::fontSizeBody * scale);
      button.setGlyphSize(21.0f * scale);
      button.setMinHeight(Style::controlHeight * scale);
      button.setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      button.setGap(Style::spaceSm * scale);
      button.setRadius(Style::radiusLg * scale);
      if (button.label() != nullptr) {
        button.label()->setBold(true);
      }
    }

    void applySecondaryNavStyle(Button& button, float scale, bool selected) {
      button.setVariant(selected ? ButtonVariant::TabActive : ButtonVariant::Tab);
      button.setContentAlign(ButtonContentAlign::Start);
      button.setFontSize(Style::fontSizeCaption * scale);
      button.setGlyphSize(Style::fontSizeCaption * scale);
      button.setMinHeight(Style::controlHeightSm * scale);
      button.setPadding(Style::spaceXs * scale, Style::spaceMd * scale, Style::spaceXs * scale, Style::spaceLg * scale);
      button.setGap(Style::spaceXs * scale);
      button.setRadius(Style::radiusMd * scale);
    }

  } // namespace

  std::unique_ptr<Flex> buildSettingsSidebar(SettingsSidebarContext ctx) {
    const Config& cfg = ctx.config;
    std::vector<std::string> existingBarNames = ctx.availableBars;
    const std::string nextBarName = nextAvailableBarName(existingBarNames);
    const auto sectionLabel = [](std::string_view section) {
      return i18n::tr("settings.navigation.sections." + std::string(section));
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

    auto sidebarScroll = std::make_unique<ScrollView>();
    sidebarScroll->bindState(&ctx.sidebarScrollState);
    sidebarScroll->setScrollbarVisible(true);
    sidebarScroll->setViewportPaddingH(0.0f);
    sidebarScroll->setViewportPaddingV(0.0f);
    sidebarScroll->setFill(roleColor(ColorRole::Surface));
    sidebarScroll->setRadius(Style::radiusXl * scale);
    sidebarScroll->clearBorder();
    sidebarScroll->setFillHeight(true);
    sidebarScroll->setSize(kSidebarWidth * scale, 0.0f);
    sidebarScroll->setMinWidth(kSidebarWidth * scale);

    auto* sidebar = sidebarScroll->content();
    sidebar->setDirection(FlexDirection::Vertical);
    sidebar->setAlign(FlexAlign::Stretch);
    sidebar->setGap(Style::spaceXs * scale);
    sidebar->setPadding(Style::spaceSm * scale);

    for (const auto& section : ctx.sections) {
      const bool selected = section == *selectedSection;
      auto navItem = std::make_unique<Button>();
      navItem->setGlyph(sectionGlyph(section));
      navItem->setText(sectionLabel(section));
      applyPrimaryNavStyle(*navItem, scale, selected);
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
      navItem->setGlyph("menu");
      navItem->setText(i18n::tr("settings.entities.bar.label", "name", barName));
      applyPrimaryNavStyle(*navItem, scale, barSelected);
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
        ovrItem->setGlyph("device-desktop");
        ovrItem->setText(i18n::tr("settings.entities.monitor-override.label", "name", ovr.match));
        applySecondaryNavStyle(*ovrItem, scale, ovrSelected);
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
      newMonitorBtn->setText(i18n::tr("settings.entities.monitor-override.new"));
      newMonitorBtn->setGlyph("add");
      newMonitorBtn->setVariant(ButtonVariant::Ghost);
      newMonitorBtn->setContentAlign(ButtonContentAlign::Start);
      newMonitorBtn->setFontSize(Style::fontSizeCaption * scale);
      newMonitorBtn->setGlyphSize(Style::fontSizeCaption * scale);
      newMonitorBtn->setMinHeight(Style::controlHeightSm * scale);
      newMonitorBtn->setPadding(Style::spaceXs * scale, Style::spaceMd * scale, Style::spaceXs * scale,
                                Style::spaceLg * scale);
      newMonitorBtn->setGap(Style::spaceXs * scale);
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
      input->setPlaceholder(i18n::tr("settings.entities.monitor-override.match-placeholder"));
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
      saveBtn->setText(i18n::tr("settings.entities.monitor-override.create"));
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
    newBarBtn->setText(i18n::tr("settings.entities.bar.new"));
    newBarBtn->setGlyph("add");
    newBarBtn->setVariant(ButtonVariant::Ghost);
    newBarBtn->setContentAlign(ButtonContentAlign::Start);
    newBarBtn->setFontSize(Style::fontSizeBody * scale);
    newBarBtn->setGlyphSize(21.0f * scale);
    newBarBtn->setMinHeight(Style::controlHeight * scale);
    newBarBtn->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    newBarBtn->setGap(Style::spaceSm * scale);
    newBarBtn->setRadius(Style::radiusLg * scale);
    if (newBarBtn->label() != nullptr) {
      newBarBtn->label()->setBold(true);
    }
    newBarBtn->setOnClick([creatingBarName, nextBarName, clearTransientState, requestRebuild]() {
      clearTransientState();
      *creatingBarName = nextBarName;
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
      input->setPlaceholder(i18n::tr("settings.entities.bar.id-placeholder"));
      input->setFontSize(Style::fontSizeCaption * scale);
      input->setControlHeight(Style::controlHeightSm * scale);
      input->setHorizontalPadding(Style::spaceXs * scale);
      input->setSize(120.0f * scale, Style::controlHeightSm * scale);
      auto* inputPtr = input.get();

      auto doCreate = [existingBarNames, createBar, inputPtr](std::string rawName) {
        const std::string name = normalizedConfigId(rawName);
        if (!isValidConfigId(name) || barNameExists(existingBarNames, name)) {
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
      saveBtn->setText(i18n::tr("settings.entities.bar.create"));
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

    return sidebarScroll;
  }

} // namespace settings
