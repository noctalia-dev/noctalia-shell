#include "shell/settings/settings_entity_editor.h"

#include "i18n/i18n.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cctype>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace settings {
  namespace {

    std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ThemeColor& color,
                                     bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

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

    Flex* makeSection(Flex& content, std::string_view title, float scale) {
      auto section = std::make_unique<Flex>();
      section->setDirection(FlexDirection::Vertical);
      section->setAlign(FlexAlign::Stretch);
      section->setGap(Style::spaceSm * scale);
      section->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      section->setCardStyle(scale);
      section->addChild(makeLabel(title, Style::fontSizeTitle * scale, roleColor(ColorRole::OnSurface), true));

      auto* raw = section.get();
      content.addChild(std::move(section));
      return raw;
    }

    void addMonitorManagement(Flex& content, SettingsEntityEditorContext& ctx) {
      if (ctx.searchQuery.empty() && ctx.selectedSection == "bar" && ctx.selectedBar != nullptr &&
          ctx.selectedMonitorOverride != nullptr && ctx.configService != nullptr &&
          ctx.configService->isOverrideOnlyMonitorOverride(ctx.selectedBar->name, ctx.selectedMonitorOverride->match)) {
        const std::string barName = ctx.selectedBar->name;
        const std::string match = ctx.selectedMonitorOverride->match;
        const bool pendingDelete =
            ctx.pendingDeleteMonitorOverrideBarName == barName && ctx.pendingDeleteMonitorOverrideMatch == match;
        const bool renaming =
            ctx.renamingMonitorOverrideBarName == barName && ctx.renamingMonitorOverrideMatch == match;
        auto* management = makeSection(content, i18n::tr("settings.entities.monitor-override.management"), ctx.scale);

        if (renaming) {
          auto renameRow = std::make_unique<Flex>();
          renameRow->setDirection(FlexDirection::Horizontal);
          renameRow->setAlign(FlexAlign::Center);
          renameRow->setGap(Style::spaceXs * ctx.scale);

          auto input = std::make_unique<Input>();
          input->setValue(match);
          input->setPlaceholder(i18n::tr("settings.entities.monitor-override.match-placeholder"));
          input->setFontSize(Style::fontSizeBody * ctx.scale);
          input->setControlHeight(Style::controlHeight * ctx.scale);
          input->setHorizontalPadding(Style::spaceSm * ctx.scale);
          input->setSize(190.0f * ctx.scale, Style::controlHeight * ctx.scale);
          input->setFlexGrow(1.0f);
          auto* inputPtr = input.get();

          std::vector<std::string> existingMatches;
          existingMatches.reserve(ctx.selectedBar->monitorOverrides.size());
          for (const auto& monitorOverride : ctx.selectedBar->monitorOverrides) {
            if (monitorOverride.match != match) {
              existingMatches.push_back(monitorOverride.match);
            }
          }

          auto doRename = [&renamingMonitorOverrideBarName = ctx.renamingMonitorOverrideBarName,
                           &renamingMonitorOverrideMatch = ctx.renamingMonitorOverrideMatch, barName, match,
                           renameMonitorOverride = ctx.renameMonitorOverride, inputPtr,
                           existingMatches = std::move(existingMatches),
                           requestRebuild = ctx.requestRebuild](std::string rawMatch) {
            const std::string newMatch = normalizedConfigId(rawMatch);
            if (newMatch == match) {
              renamingMonitorOverrideBarName.clear();
              renamingMonitorOverrideMatch.clear();
              inputPtr->setInvalid(false);
              requestRebuild();
              return;
            }
            if (newMatch.empty() ||
                std::find(existingMatches.begin(), existingMatches.end(), newMatch) != existingMatches.end()) {
              inputPtr->setInvalid(true);
              return;
            }
            inputPtr->setInvalid(false);
            renameMonitorOverride(barName, match, newMatch);
          };

          input->setOnChange([inputPtr](const std::string& /*value*/) { inputPtr->setInvalid(false); });
          input->setOnSubmit([doRename](const std::string& text) mutable { doRename(text); });

          auto saveBtn = std::make_unique<Button>();
          saveBtn->setText(i18n::tr("settings.entities.monitor-override.rename-save"));
          saveBtn->setVariant(ButtonVariant::Default);
          saveBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          saveBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          saveBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          saveBtn->setRadius(Style::radiusSm * ctx.scale);
          saveBtn->setOnClick([doRename, inputPtr]() mutable { doRename(inputPtr->value()); });

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setText(i18n::tr("common.actions.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&renamingMonitorOverrideBarName = ctx.renamingMonitorOverrideBarName,
                                 &renamingMonitorOverrideMatch = ctx.renamingMonitorOverrideMatch,
                                 requestRebuild = ctx.requestRebuild]() {
            renamingMonitorOverrideBarName.clear();
            renamingMonitorOverrideMatch.clear();
            requestRebuild();
          });

          renameRow->addChild(std::move(input));
          renameRow->addChild(std::move(saveBtn));
          renameRow->addChild(std::move(cancelBtn));
          management->addChild(std::move(renameRow));
        } else if (pendingDelete) {
          auto confirmPanel = std::make_unique<Flex>();
          confirmPanel->setDirection(FlexDirection::Vertical);
          confirmPanel->setAlign(FlexAlign::Stretch);
          confirmPanel->setGap(Style::spaceXs * ctx.scale);
          confirmPanel->setPadding(Style::spaceSm * ctx.scale);
          confirmPanel->setRadius(Style::radiusSm * ctx.scale);
          confirmPanel->setFill(roleColor(ColorRole::Error, 0.10f));
          confirmPanel->setBorder(roleColor(ColorRole::Error, 0.35f), Style::borderWidth);

          confirmPanel->addChild(
              makeLabel(i18n::tr("settings.entities.monitor-override.delete-confirm-title", "name", match),
                        Style::fontSizeBody * ctx.scale, roleColor(ColorRole::Error), true));
          confirmPanel->addChild(makeLabel(i18n::tr("settings.entities.monitor-override.delete-confirm-desc"),
                                           Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant),
                                           false));

          auto confirmRow = std::make_unique<Flex>();
          confirmRow->setDirection(FlexDirection::Horizontal);
          confirmRow->setAlign(FlexAlign::Center);
          confirmRow->setGap(Style::spaceSm * ctx.scale);

          auto confirmSpacer = std::make_unique<Flex>();
          confirmSpacer->setFlexGrow(1.0f);
          confirmRow->addChild(std::move(confirmSpacer));

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setText(i18n::tr("common.actions.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&pendingDeleteMonitorOverrideBarName = ctx.pendingDeleteMonitorOverrideBarName,
                                 &pendingDeleteMonitorOverrideMatch = ctx.pendingDeleteMonitorOverrideMatch,
                                 requestRebuild = ctx.requestRebuild]() {
            pendingDeleteMonitorOverrideBarName.clear();
            pendingDeleteMonitorOverrideMatch.clear();
            requestRebuild();
          });
          confirmRow->addChild(std::move(cancelBtn));

          auto confirmBtn = std::make_unique<Button>();
          confirmBtn->setGlyph("trash");
          confirmBtn->setText(i18n::tr("settings.entities.monitor-override.delete"));
          confirmBtn->setVariant(ButtonVariant::Destructive);
          confirmBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          confirmBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          confirmBtn->setRadius(Style::radiusSm * ctx.scale);
          confirmBtn->setOnClick([deleteMonitorOverride = ctx.deleteMonitorOverride, barName, match]() {
            deleteMonitorOverride(barName, match);
          });
          confirmRow->addChild(std::move(confirmBtn));

          confirmPanel->addChild(std::move(confirmRow));
          management->addChild(std::move(confirmPanel));
        } else {
          auto actionRow = std::make_unique<Flex>();
          actionRow->setDirection(FlexDirection::Horizontal);
          actionRow->setAlign(FlexAlign::Center);
          actionRow->setGap(Style::spaceXs * ctx.scale);

          auto spacer = std::make_unique<Flex>();
          spacer->setFlexGrow(1.0f);
          actionRow->addChild(std::move(spacer));

          auto renameBtn = std::make_unique<Button>();
          renameBtn->setText(i18n::tr("settings.entities.monitor-override.rename"));
          renameBtn->setVariant(ButtonVariant::Ghost);
          renameBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          renameBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          renameBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          renameBtn->setRadius(Style::radiusSm * ctx.scale);
          renameBtn->setOnClick([&renamingMonitorOverrideBarName = ctx.renamingMonitorOverrideBarName,
                                 &renamingMonitorOverrideMatch = ctx.renamingMonitorOverrideMatch,
                                 &pendingDeleteMonitorOverrideBarName = ctx.pendingDeleteMonitorOverrideBarName,
                                 &pendingDeleteMonitorOverrideMatch = ctx.pendingDeleteMonitorOverrideMatch, barName,
                                 match, requestRebuild = ctx.requestRebuild]() {
            renamingMonitorOverrideBarName = barName;
            renamingMonitorOverrideMatch = match;
            pendingDeleteMonitorOverrideBarName.clear();
            pendingDeleteMonitorOverrideMatch.clear();
            requestRebuild();
          });
          actionRow->addChild(std::move(renameBtn));

          auto deleteBtn = std::make_unique<Button>();
          deleteBtn->setGlyph("trash");
          deleteBtn->setText(i18n::tr("settings.entities.monitor-override.delete"));
          deleteBtn->setVariant(ButtonVariant::Ghost);
          deleteBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          deleteBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          deleteBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          deleteBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          deleteBtn->setRadius(Style::radiusSm * ctx.scale);
          deleteBtn->setOnClick([&pendingDeleteMonitorOverrideBarName = ctx.pendingDeleteMonitorOverrideBarName,
                                 &pendingDeleteMonitorOverrideMatch = ctx.pendingDeleteMonitorOverrideMatch,
                                 &renamingMonitorOverrideBarName = ctx.renamingMonitorOverrideBarName,
                                 &renamingMonitorOverrideMatch = ctx.renamingMonitorOverrideMatch, barName, match,
                                 requestRebuild = ctx.requestRebuild]() {
            pendingDeleteMonitorOverrideBarName = barName;
            pendingDeleteMonitorOverrideMatch = match;
            renamingMonitorOverrideBarName.clear();
            renamingMonitorOverrideMatch.clear();
            requestRebuild();
          });
          actionRow->addChild(std::move(deleteBtn));

          management->addChild(std::move(actionRow));
        }
      }
    }

    void addBarManagement(Flex& content, SettingsEntityEditorContext& ctx) {
      if (ctx.searchQuery.empty() && ctx.selectedSection == "bar" && ctx.selectedBar != nullptr &&
          ctx.selectedMonitorOverride == nullptr && ctx.configService != nullptr) {
        const std::string barName = ctx.selectedBar->name;
        const bool overrideOnly = ctx.configService->isOverrideOnlyBar(barName);
        const bool canMoveUp = ctx.configService->canMoveBarOverride(barName, -1);
        const bool canMoveDown = ctx.configService->canMoveBarOverride(barName, 1);
        if (!overrideOnly && !canMoveUp && !canMoveDown) {
          return;
        }

        const bool pendingDelete = overrideOnly && ctx.pendingDeleteBarName == barName;
        const bool renaming = overrideOnly && ctx.renamingBarName == barName;
        auto* management = makeSection(content, i18n::tr("settings.entities.bar.management"), ctx.scale);

        if (renaming) {
          auto renameRow = std::make_unique<Flex>();
          renameRow->setDirection(FlexDirection::Horizontal);
          renameRow->setAlign(FlexAlign::Center);
          renameRow->setGap(Style::spaceXs * ctx.scale);

          auto input = std::make_unique<Input>();
          input->setValue(barName);
          input->setPlaceholder(i18n::tr("settings.entities.bar.id-placeholder"));
          input->setFontSize(Style::fontSizeBody * ctx.scale);
          input->setControlHeight(Style::controlHeight * ctx.scale);
          input->setHorizontalPadding(Style::spaceSm * ctx.scale);
          input->setSize(190.0f * ctx.scale, Style::controlHeight * ctx.scale);
          input->setFlexGrow(1.0f);
          auto* inputPtr = input.get();

          auto doRename = [&renamingBarName = ctx.renamingBarName, config = ctx.config, barName,
                           renameBar = ctx.renameBar, inputPtr,
                           requestRebuild = ctx.requestRebuild](std::string rawName) {
            const std::string newName = normalizedConfigId(rawName);
            if (newName == barName) {
              renamingBarName.clear();
              inputPtr->setInvalid(false);
              requestRebuild();
              return;
            }
            if (!isValidConfigId(newName) || barNameExists(config, newName)) {
              inputPtr->setInvalid(true);
              return;
            }
            inputPtr->setInvalid(false);
            renameBar(barName, newName);
          };

          input->setOnChange([inputPtr](const std::string& /*value*/) { inputPtr->setInvalid(false); });
          input->setOnSubmit([doRename](const std::string& text) mutable { doRename(text); });

          auto saveBtn = std::make_unique<Button>();
          saveBtn->setText(i18n::tr("settings.entities.bar.rename-save"));
          saveBtn->setVariant(ButtonVariant::Default);
          saveBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          saveBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          saveBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          saveBtn->setRadius(Style::radiusSm * ctx.scale);
          saveBtn->setOnClick([doRename, inputPtr]() mutable { doRename(inputPtr->value()); });

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setText(i18n::tr("common.actions.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick([&renamingBarName = ctx.renamingBarName, requestRebuild = ctx.requestRebuild]() {
            renamingBarName.clear();
            requestRebuild();
          });

          renameRow->addChild(std::move(input));
          renameRow->addChild(std::move(saveBtn));
          renameRow->addChild(std::move(cancelBtn));
          management->addChild(std::move(renameRow));
        } else if (pendingDelete) {
          auto confirmPanel = std::make_unique<Flex>();
          confirmPanel->setDirection(FlexDirection::Vertical);
          confirmPanel->setAlign(FlexAlign::Stretch);
          confirmPanel->setGap(Style::spaceXs * ctx.scale);
          confirmPanel->setPadding(Style::spaceSm * ctx.scale);
          confirmPanel->setRadius(Style::radiusSm * ctx.scale);
          confirmPanel->setFill(roleColor(ColorRole::Error, 0.10f));
          confirmPanel->setBorder(roleColor(ColorRole::Error, 0.35f), Style::borderWidth);

          confirmPanel->addChild(makeLabel(i18n::tr("settings.entities.bar.delete-confirm-title", "name", barName),
                                           Style::fontSizeBody * ctx.scale, roleColor(ColorRole::Error), true));
          confirmPanel->addChild(makeLabel(i18n::tr("settings.entities.bar.delete-confirm-desc"),
                                           Style::fontSizeCaption * ctx.scale, roleColor(ColorRole::OnSurfaceVariant),
                                           false));

          auto confirmRow = std::make_unique<Flex>();
          confirmRow->setDirection(FlexDirection::Horizontal);
          confirmRow->setAlign(FlexAlign::Center);
          confirmRow->setGap(Style::spaceSm * ctx.scale);

          auto confirmSpacer = std::make_unique<Flex>();
          confirmSpacer->setFlexGrow(1.0f);
          confirmRow->addChild(std::move(confirmSpacer));

          auto cancelBtn = std::make_unique<Button>();
          cancelBtn->setText(i18n::tr("common.actions.cancel"));
          cancelBtn->setVariant(ButtonVariant::Ghost);
          cancelBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          cancelBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          cancelBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          cancelBtn->setRadius(Style::radiusSm * ctx.scale);
          cancelBtn->setOnClick(
              [&pendingDeleteBarName = ctx.pendingDeleteBarName, requestRebuild = ctx.requestRebuild]() {
                pendingDeleteBarName.clear();
                requestRebuild();
              });
          confirmRow->addChild(std::move(cancelBtn));

          auto confirmBtn = std::make_unique<Button>();
          confirmBtn->setGlyph("trash");
          confirmBtn->setText(i18n::tr("settings.entities.bar.delete"));
          confirmBtn->setVariant(ButtonVariant::Destructive);
          confirmBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
          confirmBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
          confirmBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
          confirmBtn->setRadius(Style::radiusSm * ctx.scale);
          confirmBtn->setOnClick([deleteBar = ctx.deleteBar, barName]() { deleteBar(barName); });
          confirmRow->addChild(std::move(confirmBtn));

          confirmPanel->addChild(std::move(confirmRow));
          management->addChild(std::move(confirmPanel));
        } else {
          auto actionRow = std::make_unique<Flex>();
          actionRow->setDirection(FlexDirection::Horizontal);
          actionRow->setAlign(FlexAlign::Center);
          actionRow->setGap(Style::spaceXs * ctx.scale);

          auto spacer = std::make_unique<Flex>();
          spacer->setFlexGrow(1.0f);
          actionRow->addChild(std::move(spacer));

          if (canMoveUp || canMoveDown) {
            auto moveUpBtn = std::make_unique<Button>();
            moveUpBtn->setGlyph("chevron-up");
            moveUpBtn->setText(i18n::tr("settings.entities.bar.move-up"));
            moveUpBtn->setVariant(ButtonVariant::Ghost);
            moveUpBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            moveUpBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
            moveUpBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            moveUpBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            moveUpBtn->setRadius(Style::radiusSm * ctx.scale);
            moveUpBtn->setEnabled(canMoveUp);
            moveUpBtn->setOnClick([moveBar = ctx.moveBar, barName]() { moveBar(barName, -1); });
            actionRow->addChild(std::move(moveUpBtn));

            auto moveDownBtn = std::make_unique<Button>();
            moveDownBtn->setGlyph("chevron-down");
            moveDownBtn->setText(i18n::tr("settings.entities.bar.move-down"));
            moveDownBtn->setVariant(ButtonVariant::Ghost);
            moveDownBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            moveDownBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
            moveDownBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            moveDownBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            moveDownBtn->setRadius(Style::radiusSm * ctx.scale);
            moveDownBtn->setEnabled(canMoveDown);
            moveDownBtn->setOnClick([moveBar = ctx.moveBar, barName]() { moveBar(barName, 1); });
            actionRow->addChild(std::move(moveDownBtn));
          }

          if (overrideOnly) {
            auto renameBtn = std::make_unique<Button>();
            renameBtn->setText(i18n::tr("settings.entities.bar.rename"));
            renameBtn->setVariant(ButtonVariant::Ghost);
            renameBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            renameBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            renameBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            renameBtn->setRadius(Style::radiusSm * ctx.scale);
            renameBtn->setOnClick([&renamingBarName = ctx.renamingBarName,
                                   &pendingDeleteBarName = ctx.pendingDeleteBarName, barName,
                                   requestRebuild = ctx.requestRebuild]() {
              renamingBarName = barName;
              pendingDeleteBarName.clear();
              requestRebuild();
            });
            actionRow->addChild(std::move(renameBtn));
          }

          if (ctx.configService->canDeleteBarOverride(barName)) {
            auto deleteBtn = std::make_unique<Button>();
            deleteBtn->setGlyph("trash");
            deleteBtn->setText(i18n::tr("settings.entities.bar.delete"));
            deleteBtn->setVariant(ButtonVariant::Ghost);
            deleteBtn->setFontSize(Style::fontSizeCaption * ctx.scale);
            deleteBtn->setGlyphSize(Style::fontSizeCaption * ctx.scale);
            deleteBtn->setMinHeight(Style::controlHeightSm * ctx.scale);
            deleteBtn->setPadding(Style::spaceXs * ctx.scale, Style::spaceSm * ctx.scale);
            deleteBtn->setRadius(Style::radiusSm * ctx.scale);
            deleteBtn->setOnClick([&pendingDeleteBarName = ctx.pendingDeleteBarName,
                                   &renamingBarName = ctx.renamingBarName, barName,
                                   requestRebuild = ctx.requestRebuild]() {
              pendingDeleteBarName = barName;
              renamingBarName.clear();
              requestRebuild();
            });
            actionRow->addChild(std::move(deleteBtn));
          }

          management->addChild(std::move(actionRow));
        }
      }
    }

  } // namespace

  void addSettingsEntityManagement(Flex& content, SettingsEntityEditorContext ctx) {
    addMonitorManagement(content, ctx);
    addBarManagement(content, ctx);
  }

} // namespace settings
