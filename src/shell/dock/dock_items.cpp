#include "shell/dock/dock_items.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/dock/dock_geometry.h"
#include "shell/dock/dock_instance.h"
#include "shell/dock/dock_model.h"
#include "system/icon_resolver.h"
#include "ui/app_icon_colorization.h"
#include "ui/builders.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"

#include <algorithm>
#include <cmath>
#include <linux/input-event-codes.h>
#include <memory>
#include <utility>

namespace {

  // Instance-count badge geometry — scales with icon size.
  constexpr float kBadgeSizeRatio = 0.30f; // fraction of icon size
  constexpr float kBadgeMinSize = 16.0f;   // minimum diameter in px
  constexpr float kBadgeFontRatio = 0.72f; // font size relative to badge diameter
  constexpr float kDotSizeRatio = 0.09f;
  constexpr float kDotMinSize = 4.0f;
  constexpr float kDotGap = 3.0f;
  constexpr float kCellPad = 6.0f;

  void applyShellAppIconColorization(Image* image, const ShellConfig& shell) {
    if (image == nullptr) {
      return;
    }
    image->setAppIconColorization(effectiveShellAppIconColorizationTint(shell));
  }

} // namespace

namespace shell::dock {

  struct DockItemClickContext {
    ConfigService& config;
    DockItemCallbacks callbacks;
  };

  std::string_view dockLauncherIconGlyph(const DockConfig& cfg) {
    return cfg.launcherIcon.empty() ? "grid-dots" : std::string_view{cfg.launcherIcon};
  }

  std::unique_ptr<Flex> makeDockItemRow(const DockConfig& cfg, bool vertical) {
    return ui::flex(
        vertical ? FlexDirection::Vertical : FlexDirection::Horizontal,
        {
            .align = FlexAlign::Center,
            .gap = static_cast<float>(cfg.itemSpacing),
            .padding = static_cast<float>(cfg.padding),
        }
    );
  }

  void handleItemClick(DockInstance& instance, const DockItemAction& action, DockItemClickContext& context);

  std::unique_ptr<InputArea> createLauncherButton(
      DockInstance& instance, const DockConfig& cfg, const std::shared_ptr<DockItemClickContext>& clickContext
  ) {
    const DockEdge edge = cfg.position;
    const bool vert = shell::dock::isVerticalEdge(edge);
    const float iSize = static_cast<float>(cfg.iconSize);
    const float cellMain = iSize + 2.0f * kCellPad;
    const float cellCross = iSize + 2.0f * kCellPad;
    const float glyphSize = iSize * 0.8f;
    const float glyphOffsetY = kCellPad + (iSize - glyphSize) * 0.5f;

    auto areaNode = std::make_unique<InputArea>();
    if (!vert) {
      areaNode->setSize(cellMain, cellCross);
    } else {
      areaNode->setSize(cellCross, cellMain);
    }

    Box* bgPtr = nullptr;
    areaNode->addChild(
        ui::box({
            .out = &bgPtr,
            .fill = clearColorSpec(),
            .radius = static_cast<float>(cfg.radius),
            .width = cellMain,
            .height = cellMain,
            .configure = [](Box& box) { box.setPosition(0.0f, 0.0f); },
        })
    );

    auto launcherGlyph = ui::glyph({
        .glyphSize = glyphSize,
        .color = colorSpecFromRole(ColorRole::OnSurface),
        .width = iSize,
        .height = iSize,
        .configure = [&cfg, glyphOffsetY](Glyph& glyph) {
          if (!glyph.setGlyph(dockLauncherIconGlyph(cfg))) {
            glyph.setGlyph("grid-dots");
          }
          glyph.setPosition(kCellPad, glyphOffsetY);
        },
    });
    areaNode->addChild(std::move(launcherGlyph));

    auto* instPtr = &instance;
    areaNode->setOnEnter([bgPtr, instPtr](const InputArea::PointerData&) {
      bgPtr->setFill(colorSpecFromRole(ColorRole::Hover));
      if (instPtr->sceneRoot != nullptr) {
        instPtr->sceneRoot->markPaintDirty();
      }
    });
    areaNode->setOnLeave([bgPtr, instPtr]() {
      bgPtr->setFill(clearColorSpec());
      if (instPtr->sceneRoot != nullptr) {
        instPtr->sceneRoot->markPaintDirty();
      }
    });
    areaNode->setAcceptedButtons(InputArea::buttonMask({BTN_LEFT}));
    areaNode->setOnClick([instPtr, clickContext](const InputArea::PointerData& d) {
      if (d.button == BTN_LEFT && clickContext->callbacks.toggleLauncher) {
        clickContext->callbacks.toggleLauncher(*instPtr);
      }
    });

    return areaNode;
  }

  void rebuildItems(
      DockInstance& instance, DockItemSceneDependencies deps, const DockSnapshot& snapshot,
      const DockItemCallbacks& callbacks
  ) {
    uiAssertNotRendering("shell::dock::rebuildItems");
    if (instance.row == nullptr) {
      return;
    }

    const auto& cfg = deps.model.config.config().dock;
    const DockEdge edge = cfg.position;
    const DockLauncherPosition launcherPosition = cfg.launcherPosition;
    const bool vert = shell::dock::isVerticalEdge(edge);
    const float iSize = static_cast<float>(cfg.iconSize);
    auto clickContext = std::make_shared<DockItemClickContext>(DockItemClickContext{
        .config = deps.model.config,
        .callbacks = callbacks,
    });

    for (auto& item : instance.items) {
      if (item.scaleAnimId != 0) {
        instance.animations.cancel(item.scaleAnimId);
        item.scaleAnimId = 0;
      }
      if (item.opacityAnimId != 0) {
        instance.animations.cancel(item.opacityAnimId);
        item.opacityAnimId = 0;
      }
    }

    // Clear previous items by recreating the row.
    if (instance.row != nullptr && instance.panel != nullptr) {
      instance.panel->removeChild(instance.row);
      instance.row = nullptr;
    }
    instance.items.clear();

    auto freshRow = makeDockItemRow(cfg, vert);
    instance.row = static_cast<Flex*>(
        instance.panel != nullptr ? instance.panel->addChild(std::move(freshRow))
                                  : instance.sceneRoot->addChild(std::move(freshRow))
    );
    const auto& itemModels = snapshot.items;

    if (launcherPosition == DockLauncherPosition::Start) {
      instance.row->addChild(createLauncherButton(instance, cfg, clickContext));
    }

    // Reserve up-front so emplace_back never reallocates while lambdas hold raw pointers.
    instance.items.reserve(itemModels.size());

    for (const auto& model : itemModels) {
      auto& item = instance.items.emplace_back();
      DockItemAction action{
          .entry = model.entry,
          .idLower = model.idLower,
          .startupWmClassLower = model.startupWmClassLower,
      };

      const float cellMain = iSize + 2.0f * kCellPad;
      const float cellCross = iSize + 2.0f * kCellPad;
      auto areaNode = std::make_unique<InputArea>();
      if (!vert) {
        areaNode->setSize(cellMain, cellCross);
      } else {
        areaNode->setSize(cellCross, cellMain);
      }

      areaNode->addChild(
          ui::box({
              .out = &item.background,
              .fill = clearColorSpec(),
              .radius = static_cast<float>(cfg.radius),
              .width = cellMain,
              .height = cellMain,
              .configure = [](Box& box) { box.setPosition(0.0f, 0.0f); },
          })
      );

      const std::string& iconPath = [&]() -> const std::string& {
        if (!model.entry.icon.empty()) {
          const std::string& primary = deps.iconResolver.resolve(model.entry.icon, cfg.iconSize);
          if (!primary.empty()) {
            return primary;
          }
        }
        return deps.iconResolver.resolve("application-x-executable", cfg.iconSize);
      }();
      RenderContext* renderContext = &deps.renderContext;
      auto iconImg = ui::image({
          .width = iSize,
          .height = iSize,
          .configure = [renderContext, &iconPath, &cfg, &shell = deps.model.config.config().shell](Image& image) {
            image.setAppIconColorization(effectiveShellAppIconColorizationTint(shell));
            if (!iconPath.empty() && renderContext != nullptr) {
              image.setSourceFile(*renderContext, iconPath, cfg.iconSize, true);
            }
            image.setPosition(kCellPad, kCellPad);
          },
      });

      if (iconImg->hasImage()) {
        item.iconImage = static_cast<Image*>(areaNode->addChild(std::move(iconImg)));
      } else {
        item.iconGlyph = static_cast<Glyph*>(areaNode->addChild(
            ui::glyph({
                .glyph = "app-window",
                .glyphSize = iSize,
                .color = colorSpecFromRole(ColorRole::OnSurface),
                .width = iSize,
                .height = iSize,
                .configure = [](Glyph& glyph) { glyph.setPosition(kCellPad, kCellPad); },
            })
        ));
      }

      if (cfg.showDots) {
        const float dot = std::max(kDotMinSize, std::round(iSize * kDotSizeRatio));
        const bool verticalDots = shell::dock::isVerticalEdge(edge);

        for (std::size_t dotIndex = 0; dotIndex < item.dotIndicators.size(); ++dotIndex) {
          item.dotIndicators[dotIndex] = static_cast<Box*>(areaNode->addChild(
              ui::box({
                  .fill = colorSpecFromRole(ColorRole::Secondary),
                  .radius = dot * 0.5f,
                  .width = dot,
                  .height = dot,
                  .visible = false,
                  .configure = [verticalDots, edge, cellMain, dot](Box& box) {
                    if (verticalDots) {
                      const float x = edge == DockEdge::Left ? std::round(cellMain - dot - 1.0f) : 1.0f;
                      box.setPosition(x, std::round((cellMain - dot) * 0.5f));
                    } else {
                      const float y = edge == DockEdge::Bottom ? 1.0f : std::round(cellMain - dot - 1.0f);
                      box.setPosition(std::round((cellMain - dot) * 0.5f), y);
                    }
                  },
              })
          ));
        }
      }

      if (cfg.showInstanceCount) {
        const float bd = std::max(kBadgeMinSize, iSize * kBadgeSizeRatio);
        const float badgeX = kCellPad + iSize - bd * 0.55f;
        const float badgeY = kCellPad - bd * 0.45f;

        areaNode->addChild(
            ui::box({
                .out = &item.badge,
                .radius = bd * 0.5f,
                .width = bd,
                .height = bd,
                .visible = false,
                .configure = [badgeX, badgeY](Box& box) { box.setPosition(badgeX, badgeY); },
            })
        );

        item.badge->addChild(
            ui::label({
                .out = &item.badgeLabel,
                .fontSize = bd * kBadgeFontRatio,
                .maxLines = 1,
                .fontWeight = FontWeight::Bold,
                .visible = false,
            })
        );
      }

      auto* itemPtr = &item;
      auto* instPtr = &instance;

      areaNode->setOnEnter([itemPtr, instPtr](const InputArea::PointerData&) {
        if (!itemPtr->hovered) {
          itemPtr->hovered = true;
          if (itemPtr->background) {
            itemPtr->background->setFill(colorSpecFromRole(ColorRole::Hover));
          }
          if (instPtr->sceneRoot) {
            instPtr->sceneRoot->markPaintDirty();
          }
        }
      });
      areaNode->setOnLeave([itemPtr, instPtr]() {
        if (itemPtr->hovered) {
          itemPtr->hovered = false;
          if (itemPtr->background) {
            itemPtr->background->setFill(clearColorSpec());
          }
          if (instPtr->sceneRoot) {
            instPtr->sceneRoot->markPaintDirty();
          }
        }
      });
      areaNode->setAcceptedButtons(InputArea::buttonMask({BTN_LEFT, BTN_RIGHT}));
      areaNode->setOnClick([action = std::move(action), instPtr, clickContext](const InputArea::PointerData& d) {
        if (d.button == BTN_LEFT) {
          handleItemClick(*instPtr, action, *clickContext);
        } else if (d.button == BTN_RIGHT && clickContext->callbacks.openItemMenu) {
          clickContext->callbacks.openItemMenu(*instPtr, action);
        }
      });

      item.area = static_cast<InputArea*>(instance.row->addChild(std::move(areaNode)));
    }

    if (launcherPosition == DockLauncherPosition::End) {
      instance.row->addChild(createLauncherButton(instance, cfg, clickContext));
    }

    shell::dock::resizeSurface(instance, cfg, deps.model.config.config().shell.shadow);
  }

  void updateVisuals(DockInstance& instance, DockItemSceneDependencies deps, const DockSnapshot& snapshot) {
    const auto& cfg = deps.model.config.config().dock;
    const auto& shell = deps.model.config.config().shell;
    const DockEdge edge = cfg.position;
    const std::size_t itemCount = std::min(instance.items.size(), snapshot.items.size());

    for (std::size_t itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
      auto& item = instance.items[itemIndex];
      const auto& model = snapshot.items[itemIndex];
      const float iconScale = model.active ? cfg.activeScale : cfg.inactiveScale;
      const float iconOpacity = model.active ? cfg.activeOpacity : cfg.inactiveOpacity;
      applyShellAppIconColorization(item.iconImage, shell);
      Node* iconNode =
          item.iconImage != nullptr ? static_cast<Node*>(item.iconImage) : static_cast<Node*>(item.iconGlyph);

      if (iconNode != nullptr) {
        if (item.visualScale < 0.0f) {
          item.visualScale = iconScale;
          iconNode->setScale(iconScale);
        } else if (std::abs(item.visualScale - iconScale) > 0.001f) {
          if (item.scaleAnimId != 0) {
            instance.animations.cancel(item.scaleAnimId);
          }
          item.scaleAnimId = instance.animations.animate(
              item.visualScale, iconScale, Style::animNormal, Easing::EaseOutCubic,
              [node = iconNode, itemPtr = &item](float value) {
                itemPtr->visualScale = value;
                node->setScale(value);
              },
              [itemPtr = &item] { itemPtr->scaleAnimId = 0; }
          );
        }

        if (item.visualOpacity < 0.0f) {
          item.visualOpacity = iconOpacity;
          iconNode->setOpacity(iconOpacity);
        } else if (std::abs(item.visualOpacity - iconOpacity) > 0.001f) {
          if (item.opacityAnimId != 0) {
            instance.animations.cancel(item.opacityAnimId);
          }
          item.opacityAnimId = instance.animations.animate(
              item.visualOpacity, iconOpacity, Style::animNormal, Easing::EaseOutCubic,
              [node = iconNode, itemPtr = &item](float value) {
                itemPtr->visualOpacity = value;
                node->setOpacity(value);
              },
              [itemPtr = &item] { itemPtr->opacityAnimId = 0; }
          );
        }
      }

      const std::size_t count = model.instanceCount;

      if (cfg.showDots) {
        const std::size_t dotCount = std::min<std::size_t>(count, 3);
        const float iSize = static_cast<float>(cfg.iconSize);
        const float cellMain = iSize + 2.0f * kCellPad;
        const float dot = std::max(kDotMinSize, std::round(iSize * kDotSizeRatio));
        const float groupLength =
            dotCount == 0 ? dot : dot * static_cast<float>(dotCount) + kDotGap * static_cast<float>(dotCount - 1);
        const float groupStart = std::round((cellMain - groupLength) * 0.5f);
        const bool verticalDots = shell::dock::isVerticalEdge(edge);

        for (std::size_t dotIndex = 0; dotIndex < item.dotIndicators.size(); ++dotIndex) {
          if (item.dotIndicators[dotIndex] == nullptr) {
            continue;
          }
          Box* dotNode = item.dotIndicators[dotIndex];
          const bool visible = dotIndex < dotCount;
          dotNode->setVisible(visible);
          dotNode->setFill(colorSpecFromRole(ColorRole::Secondary));
          if (visible) {
            const float main = groupStart + static_cast<float>(dotIndex) * (dot + kDotGap);
            if (verticalDots) {
              const float x = edge == DockEdge::Left ? std::round(cellMain - dot - 1.0f) : 1.0f;
              dotNode->setPosition(x, main);
            } else {
              const float y = edge == DockEdge::Bottom ? 1.0f : std::round(cellMain - dot - 1.0f);
              dotNode->setPosition(main, y);
            }
          }
        }
      }

      if (item.badge != nullptr && item.badgeLabel != nullptr) {
        const bool show = count >= 2;
        item.badge->setVisible(show);
        item.badgeLabel->setVisible(show);
        if (show) {
          const std::string label = (count > 9) ? "9+" : std::to_string(count);
          item.badgeLabel->setText(label);
          item.badgeLabel->setColor(colorSpecFromRole(ColorRole::OnPrimary));
          item.badge->setFill(colorSpecFromRole(ColorRole::Primary));
          const float bd = std::max(kBadgeMinSize, static_cast<float>(cfg.iconSize) * kBadgeSizeRatio);
          item.badgeLabel->measure(deps.renderContext);
          item.badgeLabel->setPosition(
              std::round((bd - item.badgeLabel->width()) * 0.5f), std::round((bd - item.badgeLabel->height()) * 0.5f)
          );
        }
      }
    }
  }

  void handleItemClick(DockInstance& instance, const DockItemAction& action, DockItemClickContext& context) {
    if (context.callbacks.activateOrLaunch) {
      context.callbacks.activateOrLaunch(instance, action);
    }
  }

} // namespace shell::dock
