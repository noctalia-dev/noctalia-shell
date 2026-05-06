#include "shell/bar/widgets/taskbar_widget.h"

#include "core/deferred_call.h"
#include "core/process.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "system/app_identity.h"
#include "system/desktop_entry.h"
#include "system/internal_app_metadata.h"
#include "ui/controls/box.h"
#include "ui/controls/context_menu.h"
#include "ui/controls/context_menu_popup.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/wayland_seat.h"
#include "wayland/wayland_toplevels.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <linux/input-event-codes.h>
#include <memory>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <wayland-client-protocol.h>

TaskbarWidget::TaskbarWidget(WaylandConnection& connection, wl_output* output, bool groupByWorkspace,
                             std::string barPosition)
    : m_connection(connection), m_output(output), m_groupByWorkspace(groupByWorkspace),
      m_barPosition(std::move(barPosition)) {
  buildDesktopIconIndex();
}

TaskbarWidget::~TaskbarWidget() = default;

void TaskbarWidget::create() {
  auto container = std::make_unique<InputArea>();
  container->setOnAxisHandler([this](const InputArea::PointerData& data) {
    if (!m_groupByWorkspace) {
      return false;
    }

    if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL && data.axis != WL_POINTER_AXIS_HORIZONTAL_SCROLL) {
      return false;
    }

    float delta = data.scrollDelta(1.0f);
    if (delta == 0.0f && data.axisValue120 != 0) {
      delta = static_cast<float>(data.axisValue120) / 120.0f;
    }
    if (delta == 0.0f && data.axisDiscrete != 0) {
      delta = static_cast<float>(data.axisDiscrete);
    }
    if (delta == 0.0f) {
      return false;
    }
    activateAdjacentWorkspace(delta > 0.0f ? 1 : -1);
    return true;
  });

  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Horizontal);
  root->setAlign(FlexAlign::Center);
  root->setGap(Style::spaceSm);

  auto taskStrip = std::make_unique<Flex>();
  taskStrip->setDirection(FlexDirection::Horizontal);
  taskStrip->setAlign(FlexAlign::Center);
  taskStrip->setGap(Style::spaceSm);
  m_taskStrip = static_cast<Flex*>(root->addChild(std::move(taskStrip)));

  m_root = root.get();
  container->addChild(std::move(root));
  setRoot(std::move(container));
}

void TaskbarWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  if (m_root == nullptr || m_taskStrip == nullptr) {
    return;
  }

  const bool wasVertical = m_vertical;
  m_vertical = containerHeight > containerWidth;
  if (m_vertical != wasVertical) {
    m_rebuildPending = true;
  }

  m_root->setDirection(m_vertical ? FlexDirection::Vertical : FlexDirection::Horizontal);
  m_root->setAlign(FlexAlign::Center);
  m_root->setGap(Style::spaceSm * m_contentScale);

  m_taskStrip->setDirection(m_vertical ? FlexDirection::Vertical : FlexDirection::Horizontal);
  m_taskStrip->setGap(Style::spaceSm * m_contentScale);

  if (m_rebuildPending) {
    rebuild(renderer);
    m_rebuildPending = false;
  }

  m_root->layout(renderer);
  if (Node* container = root(); container != nullptr && container != m_root) {
    container->setFrameSize(m_root->width(), m_root->height());
  }
}

void TaskbarWidget::doUpdate(Renderer& renderer) {
  (void)renderer;
  updateModels();
}

void TaskbarWidget::rebuild(Renderer& renderer) {
  if (m_taskStrip == nullptr) {
    return;
  }
  clearChildren(m_taskStrip);
  buildTaskButtons(renderer);
}

void TaskbarWidget::clearChildren(Flex* flex) const {
  while (flex != nullptr && !flex->children().empty()) {
    flex->removeChild(flex->children().back().get());
  }
}

void TaskbarWidget::buildTaskButtons(Renderer& renderer) {
  if (m_taskStrip == nullptr) {
    return;
  }
  const float iconSize = Style::barGlyphSize * m_contentScale;
  const float tilePadding = Style::spaceXs * 0.35f * m_contentScale;
  const float tileSize = iconSize + tilePadding * 2.0f;
  const auto workspaceAxisHandler = [this](const InputArea::PointerData& data) -> bool {
    if (!m_groupByWorkspace) {
      return false;
    }
    if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL && data.axis != WL_POINTER_AXIS_HORIZONTAL_SCROLL) {
      return false;
    }

    float delta = data.scrollDelta(1.0f);
    if (delta == 0.0f && data.axisValue120 != 0) {
      delta = static_cast<float>(data.axisValue120) / 120.0f;
    }
    if (delta == 0.0f && data.axisDiscrete != 0) {
      delta = static_cast<float>(data.axisDiscrete);
    }
    if (delta == 0.0f) {
      return false;
    }

    activateAdjacentWorkspace(delta > 0.0f ? 1 : -1);
    return true;
  };
  auto createTaskTile = [&](const TaskModel& task) {
    auto area = std::make_unique<InputArea>();
    area->setFrameSize(tileSize, tileSize);
    area->setAcceptedButtons(BTN_LEFT | BTN_RIGHT);
    area->setOnAxisHandler(workspaceAxisHandler);

    if (task.firstHandle != nullptr) {
      auto* areaPtr = area.get();
      area->setOnClick([this, task, areaPtr, handle = task.firstHandle](const InputArea::PointerData& data) {
        if (data.button == BTN_LEFT) {
          m_connection.activateToplevel(handle);
          return;
        }
        if (data.button == BTN_RIGHT && areaPtr != nullptr) {
          openTaskContextMenu(task, *areaPtr);
        }
      });
    } else {
      area->setEnabled(false);
    }

    if (!task.iconPath.empty()) {
      auto image = std::make_unique<Image>();
      image->setFit(ImageFit::Contain);
      image->setSize(iconSize, iconSize);
      image->setPosition(std::round((tileSize - iconSize) * 0.5f), std::round((tileSize - iconSize) * 0.5f));
      image->setSourceFile(renderer, task.iconPath, static_cast<int>(std::round(48.0f * m_contentScale)), true);
      area->addChild(std::move(image));
    } else {
      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyph("apps");
      glyph->setGlyphSize(iconSize);
      glyph->setPosition(std::round((tileSize - iconSize) * 0.5f), std::round((tileSize - iconSize) * 0.5f));
      area->addChild(std::move(glyph));
    }

    if (task.active) {
      const float d = std::max(4.0f, std::round(Style::barGlyphSize * 0.32f * m_contentScale));
      const float bottomInset = 0.25f * m_contentScale;
      auto indicator = std::make_unique<Box>();
      indicator->setFill(colorSpecFromRole(ColorRole::Primary));
      indicator->setRadius(d * 0.5f);
      indicator->setFrameSize(d, d);
      indicator->setPosition(std::round((tileSize - d) * 0.5f), std::round(tileSize - d - bottomInset));
      area->addChild(std::move(indicator));
    }
    return area;
  };

  if (m_groupByWorkspace && !m_workspaces.empty()) {
    const float capsuleRadius = Style::radiusLg * m_contentScale;
    const float groupGap = Style::spaceXs * m_contentScale;
    const float groupPadCross = Style::spaceXs * 0.35f * m_contentScale;
    const float groupPadEnd = Style::spaceXs * 0.55f * m_contentScale;
    const float badgeBase = std::round(std::max(11.0f, Style::barGlyphSize * 0.72f) * m_contentScale);
    const float badgeFontSize = std::round(Style::fontSizeCaption * 0.72f * m_contentScale);
    for (const auto& ws : m_workspaces) {
      std::vector<const TaskModel*> tasks;
      for (const auto& task : m_tasks) {
        if (task.workspaceKey == ws.key || task.workspaceKey == ws.workspace.id ||
            task.workspaceKey == ws.workspace.name) {
          tasks.push_back(&task);
        }
      }
      std::stable_sort(tasks.begin(), tasks.end(), [](const TaskModel* lhs, const TaskModel* rhs) {
        if (lhs->workspaceOrder != rhs->workspaceOrder) {
          return lhs->workspaceOrder < rhs->workspaceOrder;
        }
        if (lhs->order != rhs->order) {
          return lhs->order < rhs->order;
        }
        return lhs->handleKey < rhs->handleKey;
      });

      const auto badgeMetrics = renderer.measureText(ws.label, badgeFontSize, true);
      const float badgeTextWidth = std::max(0.0f, badgeMetrics.right - badgeMetrics.left);
      const float badgeWidth = std::round(std::max(badgeBase, badgeTextWidth + (Style::spaceXs * m_contentScale)));
      const float groupPadStart = std::round(std::max(groupPadEnd, badgeWidth * 0.68f));
      const float taskCount = std::max(1.0f, static_cast<float>(tasks.size()));
      const float gapCount = tasks.empty() ? 0.0f : (taskCount - 1.0f);
      const float runLength = (tileSize * taskCount) + (groupGap * gapCount);
      const float groupWidth = m_vertical ? std::round(tileSize + (groupPadCross * 2.0f))
                                          : std::round(groupPadStart + groupPadEnd + runLength);
      const float groupHeight = m_vertical ? std::round(groupPadStart + groupPadEnd + runLength)
                                           : std::round(tileSize + (groupPadCross * 2.0f));

      auto group = std::make_unique<Box>();
      group->setFrameSize(groupWidth, groupHeight);
      group->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, ws.workspace.active ? 0.52f : 0.18f));
      group->setBorder(colorSpecFromRole(ColorRole::Primary, ws.workspace.active ? 0.65f : 0.16f), Style::borderWidth);
      group->setRadius(capsuleRadius);
      auto* groupPtr = static_cast<Box*>(m_taskStrip->addChild(std::move(group)));

      if (tasks.empty()) {
        auto switcher = std::make_unique<InputArea>();
        switcher->setFrameSize(groupWidth, groupHeight);
        switcher->setPosition(0.0f, 0.0f);
        switcher->setAcceptedButtons(BTN_LEFT);
        switcher->setOnAxisHandler(workspaceAxisHandler);
        auto wsCopy = ws.workspace;
        switcher->setOnClick([this, wsCopy](const InputArea::PointerData& data) {
          if (data.button == BTN_LEFT) {
            m_connection.activateWorkspace(m_output, wsCopy);
          }
        });
        groupPtr->addChild(std::move(switcher));
      }

      for (std::size_t i = 0; i < tasks.size(); ++i) {
        const float tileOffset = (tileSize + groupGap) * static_cast<float>(i);
        auto tile = createTaskTile(*tasks[i]);
        if (m_vertical) {
          tile->setPosition(std::round(groupPadCross), std::round(groupPadStart + tileOffset));
        } else {
          tile->setPosition(std::round(groupPadStart + tileOffset), std::round(groupPadCross));
        }
        groupPtr->addChild(std::move(tile));
      }

      const float badgeLeft = std::round(badgeWidth * -0.32f);
      const float badgeTop = std::round(badgeBase * -0.22f);
      auto badgeHit = std::make_unique<InputArea>();
      badgeHit->setFrameSize(badgeWidth, badgeBase);
      badgeHit->setPosition(badgeLeft, badgeTop);
      badgeHit->setAcceptedButtons(BTN_LEFT);
      badgeHit->setOnAxisHandler(workspaceAxisHandler);
      auto wsForBadge = ws.workspace;
      badgeHit->setOnClick([this, wsForBadge](const InputArea::PointerData& data) {
        if (data.button == BTN_LEFT) {
          m_connection.activateWorkspace(m_output, wsForBadge);
        }
      });

      auto badge = std::make_unique<Box>();
      badge->setFrameSize(badgeWidth, badgeBase);
      badge->setRadius(badgeBase * 0.5f);
      badge->setFill(colorSpecFromRole(ws.workspace.active ? ColorRole::Primary : ColorRole::Surface));
      badge->setBorder(colorSpecFromRole(ColorRole::Outline, 0.45f), Style::borderWidth);
      badge->setPosition(0.0f, 0.0f);
      auto* badgePtr = static_cast<Box*>(badgeHit->addChild(std::move(badge)));

      auto badgeText = std::make_unique<Label>();
      badgeText->setText(ws.label);
      badgeText->setBold(true);
      badgeText->setFontSize(badgeFontSize);
      badgeText->setColor(colorSpecFromRole(ws.workspace.active ? ColorRole::OnPrimary : ColorRole::OnSurface));
      badgeText->measure(renderer);
      badgeText->setPosition(std::round((badgeWidth - badgeText->width()) * 0.5f),
                             std::round((badgeBase - badgeText->height()) * 0.5f));
      badgePtr->addChild(std::move(badgeText));
      if (tasks.empty()) {
        badgeHit->setHitTestVisible(false);
      }
      groupPtr->addChild(std::move(badgeHit));
    }
    return;
  }

  for (const auto& task : m_tasks) {
    m_taskStrip->addChild(createTaskTile(task));
  }
}

void TaskbarWidget::updateModels() {
  const auto desktopVersion = desktopEntriesVersion();
  if (desktopVersion != m_desktopEntriesVersion) {
    buildDesktopIconIndex();
  }

  const auto active = m_connection.activeToplevel();
  const auto* activeHandle = active.has_value() ? active->handle : nullptr;

  const auto running = m_connection.runningAppIds(m_output);
  const auto resolvedRunning = app_identity::resolveRunningApps(running, desktopEntries());
  std::vector<WorkspaceModel> nextWorkspaces;
  std::unordered_map<std::string, std::vector<std::string>> runningByWorkspace;
  std::vector<WorkspaceWindowAssignment> workspaceAssignments;

  if (m_groupByWorkspace) {
    const auto workspaces = m_connection.workspaces(m_output);
    const auto displayKeys = m_connection.workspaceDisplayKeys(m_output);
    nextWorkspaces.reserve(workspaces.size());
    for (std::size_t i = 0; i < workspaces.size(); ++i) {
      WorkspaceModel item{};
      item.workspace = workspaces[i];
      item.key = i < displayKeys.size() && !displayKeys[i].empty() ? displayKeys[i] : workspaceLabel(item.workspace, i);
      item.label = item.key;
      nextWorkspaces.push_back(std::move(item));
    }
    runningByWorkspace = m_connection.appIdsByWorkspace(m_output);
    workspaceAssignments = m_connection.workspaceWindowAssignments(m_output);
    std::unordered_map<std::string, std::size_t> workspaceKeyToOrder;
    for (std::size_t i = 0; i < nextWorkspaces.size(); ++i) {
      workspaceKeyToOrder[nextWorkspaces[i].key] = i;
    }

    std::stable_sort(workspaceAssignments.begin(), workspaceAssignments.end(), [&](const auto& a, const auto& b) {
      if (a.workspaceKey != b.workspaceKey) {
        const auto itA = workspaceKeyToOrder.find(a.workspaceKey);
        const auto itB = workspaceKeyToOrder.find(b.workspaceKey);
        if (itA != workspaceKeyToOrder.end() && itB != workspaceKeyToOrder.end()) {
          return itA->second < itB->second;
        }
        return a.workspaceKey < b.workspaceKey;
      }
      if (a.x != b.x) {
        return a.x < b.x;
      }
      if (a.y != b.y) {
        return a.y < b.y;
      }
      return a.windowId < b.windowId;
    });
  }

  std::vector<TaskModel> nextTasks;
  std::unordered_set<std::uintptr_t> processedHandles;
  for (const auto& run : resolvedRunning) {
    const std::string idLower = !run.entry.id.empty() ? toLower(run.entry.id) : run.runningLower;
    const std::string startupLower = toLower(run.entry.startupWmClass);
    const std::string nameLower = !run.entry.nameLower.empty() ? run.entry.nameLower : run.runningLower;
    const std::string appId = !run.entry.id.empty() ? run.entry.id : run.runningAppId;

    const auto windows = m_connection.windowsForApp(idLower, startupLower, m_output);
    for (const auto& window : windows) {
      const auto handleKey = reinterpret_cast<std::uintptr_t>(window.handle);
      if (!processedHandles.insert(handleKey).second) {
        continue;
      }

      TaskModel task{};
      task.handleKey = handleKey;
      task.order = window.order;
      task.appId = !window.appId.empty() ? window.appId : appId;
      task.idLower = idLower;
      task.startupWmClassLower = startupLower;
      task.nameLower = nameLower;
      task.appIdLower = toLower(task.appId);
      task.title = window.title;
      task.active = activeHandle != nullptr && activeHandle == window.handle;
      task.firstHandle = window.handle;
      task.iconPath = resolveIconPath(task.appId, run.entry.icon);
      task.workspaceKey = {};
      nextTasks.push_back(std::move(task));
    }
  }

  std::stable_sort(nextTasks.begin(), nextTasks.end(), [](const TaskModel& a, const TaskModel& b) {
    if (a.order != b.order) {
      return a.order < b.order;
    }
    return a.handleKey < b.handleKey;
  });

  if (m_groupByWorkspace && !workspaceAssignments.empty()) {
    std::unordered_map<std::uintptr_t, std::string> previousWorkspaceByHandle;
    std::unordered_map<std::uintptr_t, std::string> previousWorkspaceWindowByHandle;
    previousWorkspaceByHandle.reserve(m_tasks.size());
    previousWorkspaceWindowByHandle.reserve(m_tasks.size());
    for (const auto& task : m_tasks) {
      if (!task.workspaceKey.empty()) {
        previousWorkspaceByHandle[task.handleKey] = task.workspaceKey;
      }
      if (!task.workspaceWindowId.empty()) {
        previousWorkspaceWindowByHandle[task.handleKey] = task.workspaceWindowId;
      }
    }
    std::unordered_map<std::string, const WorkspaceModel*> workspaceByAnyKey;
    workspaceByAnyKey.reserve(m_workspaces.size() * 3);
    for (const auto& ws : nextWorkspaces) {
      workspaceByAnyKey.emplace(ws.key, &ws);
      if (!ws.workspace.id.empty()) {
        workspaceByAnyKey.emplace(ws.workspace.id, &ws);
      }
      if (!ws.workspace.name.empty()) {
        workspaceByAnyKey.emplace(ws.workspace.name, &ws);
      }
    }
    auto isTransientWorkspace = [&](const std::string& workspaceKey) {
      const auto it = workspaceByAnyKey.find(workspaceKey);
      if (it == workspaceByAnyKey.end() || it->second == nullptr) {
        return false;
      }
      const auto& workspace = it->second->workspace;
      return !workspace.active && !workspace.occupied;
    };

    std::vector<bool> used(workspaceAssignments.size(), false);
    auto matchesApp = [&](const TaskModel& task, const WorkspaceWindowAssignment& assignment) {
      const std::string assignmentAppLower = toLower(assignment.appId);
      return assignmentAppLower == task.appIdLower || assignmentAppLower == task.idLower ||
             assignmentAppLower == task.startupWmClassLower || assignmentAppLower == task.nameLower;
    };

    auto assignMatch = [&](TaskModel& task, bool requireTitle,
                           const std::function<bool(const WorkspaceWindowAssignment&)>& extraPredicate) -> bool {
      for (std::size_t i = 0; i < workspaceAssignments.size(); ++i) {
        if (used[i]) {
          continue;
        }
        const auto& assignment = workspaceAssignments[i];
        if (!matchesApp(task, assignment)) {
          continue;
        }
        if (requireTitle && assignment.title.empty()) {
          continue;
        }
        if (requireTitle && assignment.title != task.title) {
          continue;
        }
        const auto previous = previousWorkspaceByHandle.find(task.handleKey);
        if (previous != previousWorkspaceByHandle.end() && assignment.workspaceKey != previous->second &&
            isTransientWorkspace(assignment.workspaceKey)) {
          continue;
        }
        if (!extraPredicate(assignment)) {
          continue;
        }
        task.workspaceKey = assignment.workspaceKey;
        task.workspaceWindowId = assignment.windowId;
        task.workspaceOrder = i;
        used[i] = true;
        return true;
      }
      return false;
    };

    for (auto& task : nextTasks) {
      const auto previous = previousWorkspaceWindowByHandle.find(task.handleKey);
      if (previous == previousWorkspaceWindowByHandle.end()) {
        continue;
      }
      for (std::size_t i = 0; i < workspaceAssignments.size(); ++i) {
        if (used[i]) {
          continue;
        }
        const auto& assignment = workspaceAssignments[i];
        if (assignment.windowId != previous->second || !matchesApp(task, assignment)) {
          continue;
        }
        task.workspaceKey = assignment.workspaceKey;
        task.workspaceWindowId = assignment.windowId;
        task.workspaceOrder = i;
        used[i] = true;
        break;
      }
    }

    for (auto& task : nextTasks) {
      if (!task.workspaceKey.empty()) {
        continue;
      }
      const auto previous = previousWorkspaceByHandle.find(task.handleKey);
      if (previous == previousWorkspaceByHandle.end()) {
        continue;
      }
      (void)assignMatch(task, true, [&](const WorkspaceWindowAssignment& assignment) {
        return assignment.workspaceKey == previous->second;
      });
    }

    for (auto& task : nextTasks) {
      if (!task.workspaceKey.empty()) {
        continue;
      }
      const auto previous = previousWorkspaceByHandle.find(task.handleKey);
      if (previous == previousWorkspaceByHandle.end()) {
        continue;
      }
      (void)assignMatch(task, false, [&](const WorkspaceWindowAssignment& assignment) {
        return assignment.workspaceKey == previous->second;
      });
    }

    for (auto& task : nextTasks) {
      if (!task.workspaceKey.empty()) {
        continue;
      }
      (void)assignMatch(task, true, [](const WorkspaceWindowAssignment&) { return true; });
    }

    for (auto& task : nextTasks) {
      if (!task.workspaceKey.empty()) {
        continue;
      }

      std::optional<std::size_t> matchIndex;
      for (std::size_t i = 0; i < workspaceAssignments.size(); ++i) {
        if (used[i]) {
          continue;
        }
        const auto& assignment = workspaceAssignments[i];
        if (!matchesApp(task, assignment)) {
          continue;
        }
        const auto previous = previousWorkspaceByHandle.find(task.handleKey);
        if (previous != previousWorkspaceByHandle.end() && assignment.workspaceKey != previous->second &&
            isTransientWorkspace(assignment.workspaceKey)) {
          continue;
        }
        if (matchIndex.has_value()) {
          matchIndex = std::nullopt;
          break;
        }
        matchIndex = i;
      }

      if (matchIndex.has_value()) {
        task.workspaceKey = workspaceAssignments[*matchIndex].workspaceKey;
        task.workspaceWindowId = workspaceAssignments[*matchIndex].windowId;
        task.workspaceOrder = *matchIndex;
        used[*matchIndex] = true;
      }
    }

    for (auto& task : nextTasks) {
      if (task.workspaceKey.empty() || task.workspaceOrder != std::numeric_limits<std::uint64_t>::max()) {
        continue;
      }

      for (std::size_t i = 0; i < workspaceAssignments.size(); ++i) {
        if (used[i]) {
          continue;
        }
        const auto& assignment = workspaceAssignments[i];
        const std::string assignmentAppLower = toLower(assignment.appId);
        if (assignmentAppLower != task.appIdLower && assignmentAppLower != task.idLower &&
            assignmentAppLower != task.startupWmClassLower && assignmentAppLower != task.nameLower) {
          continue;
        }
        if (assignment.workspaceKey != task.workspaceKey) {
          continue;
        }

        task.workspaceOrder = i;
        task.workspaceWindowId = assignment.windowId;
        used[i] = true;
        break;
      }
    }

    // Rebuild workspaceOrder from assignment stream order every frame so
    // left/right reorders are reflected even when toplevel `order` is static.
    for (auto& task : nextTasks) {
      task.workspaceOrder = std::numeric_limits<std::uint64_t>::max();
    }
    std::vector<bool> orderClaimed(nextTasks.size(), false);
    std::unordered_set<std::string> claimedWindowIds;
    for (std::size_t taskIndex = 0; taskIndex < nextTasks.size(); ++taskIndex) {
      auto& task = nextTasks[taskIndex];
      if (task.workspaceWindowId.empty()) {
        continue;
      }
      for (std::size_t assignmentIndex = 0; assignmentIndex < workspaceAssignments.size(); ++assignmentIndex) {
        const auto& assignment = workspaceAssignments[assignmentIndex];
        if (assignment.windowId != task.workspaceWindowId || !matchesApp(task, assignment)) {
          continue;
        }
        task.workspaceKey = assignment.workspaceKey;
        task.workspaceOrder = assignmentIndex;
        orderClaimed[taskIndex] = true;
        claimedWindowIds.insert(assignment.windowId);
        break;
      }
    }
    for (std::size_t assignmentIndex = 0; assignmentIndex < workspaceAssignments.size(); ++assignmentIndex) {
      const auto& assignment = workspaceAssignments[assignmentIndex];
      if (!assignment.windowId.empty() && claimedWindowIds.contains(assignment.windowId)) {
        continue;
      }
      const std::string assignmentAppLower = toLower(assignment.appId);

      auto appMatches = [&](const TaskModel& task) {
        return assignmentAppLower == task.appIdLower || assignmentAppLower == task.idLower ||
               assignmentAppLower == task.startupWmClassLower || assignmentAppLower == task.nameLower;
      };

      auto tryClaim = [&](bool requireWorkspace, bool requireTitle) -> bool {
        for (std::size_t i = 0; i < nextTasks.size(); ++i) {
          auto& task = nextTasks[i];
          if (orderClaimed[i] || !appMatches(task)) {
            continue;
          }
          if (requireWorkspace && task.workspaceKey != assignment.workspaceKey) {
            continue;
          }
          if (requireTitle && !assignment.title.empty() && assignment.title != task.title) {
            continue;
          }
          if (task.workspaceKey.empty()) {
            task.workspaceKey = assignment.workspaceKey;
          }
          task.workspaceWindowId = assignment.windowId;
          task.workspaceOrder = assignmentIndex;
          orderClaimed[i] = true;
          if (!assignment.windowId.empty()) {
            claimedWindowIds.insert(assignment.windowId);
          }
          return true;
        }
        return false;
      };

      if (tryClaim(true, true)) {
        continue;
      }
      if (tryClaim(true, false)) {
        continue;
      }
      if (tryClaim(false, true)) {
        continue;
      }
      (void)tryClaim(false, false);
    }
  }

  if (m_groupByWorkspace && workspaceAssignments.empty() && !runningByWorkspace.empty()) {
    std::unordered_map<std::uintptr_t, std::string> workspaceByHandle;
    std::unordered_map<std::string, std::size_t> appOccurrence;
    for (const auto& ws : nextWorkspaces) {
      const auto byKey = runningByWorkspace.find(ws.key);
      const auto byName = runningByWorkspace.find(ws.workspace.name);
      const auto byId = runningByWorkspace.find(ws.workspace.id);
      const auto* list =
          byKey != runningByWorkspace.end()
              ? &byKey->second
              : (byName != runningByWorkspace.end() ? &byName->second
                                                    : (byId != runningByWorkspace.end() ? &byId->second : nullptr));
      if (list == nullptr) {
        continue;
      }
      for (const auto& appId : *list) {
        const std::string appLower = toLower(appId);
        const std::string startupWmClassLower = toLower(appId);
        const auto windows = m_connection.windowsForApp(appLower, startupWmClassLower, m_output);
        if (windows.empty()) {
          continue;
        }
        const std::size_t index = appOccurrence[appLower]++;
        if (index < windows.size()) {
          workspaceByHandle[reinterpret_cast<std::uintptr_t>(windows[index].handle)] = ws.key;
        }
      }
    }
    for (auto& task : nextTasks) {
      if (const auto it = workspaceByHandle.find(task.handleKey);
          task.workspaceKey.empty() && it != workspaceByHandle.end()) {
        task.workspaceKey = it->second;
      }
    }
  }

  if (m_groupByWorkspace && !nextWorkspaces.empty()) {
    std::string activeWorkspaceKey;
    for (const auto& workspace : nextWorkspaces) {
      if (workspace.workspace.active) {
        activeWorkspaceKey = workspace.key;
        break;
      }
    }
    if (!activeWorkspaceKey.empty()) {
      for (auto& task : nextTasks) {
        if (task.active) {
          task.workspaceKey = activeWorkspaceKey;
          break;
        }
      }
    }
  }

  std::unordered_map<std::uintptr_t, std::string> previousWorkspaceByHandle;
  previousWorkspaceByHandle.reserve(m_tasks.size());
  for (const auto& task : m_tasks) {
    if (!task.workspaceKey.empty()) {
      previousWorkspaceByHandle[task.handleKey] = task.workspaceKey;
    }
  }
  std::unordered_set<std::uintptr_t> seenHandles;
  seenHandles.reserve(nextTasks.size());
  for (auto& task : nextTasks) {
    seenHandles.insert(task.handleKey);
    const auto previous = previousWorkspaceByHandle.find(task.handleKey);
    if (previous == previousWorkspaceByHandle.end() || previous->second.empty() || task.workspaceKey.empty()) {
      m_pendingWorkspaceTransitions.erase(task.handleKey);
      continue;
    }
    if (task.workspaceKey == previous->second) {
      m_pendingWorkspaceTransitions.erase(task.handleKey);
      continue;
    }

    auto& pending = m_pendingWorkspaceTransitions[task.handleKey];
    if (pending.targetWorkspaceKey != task.workspaceKey) {
      pending.targetWorkspaceKey = task.workspaceKey;
      pending.votes = 1;
    } else if (pending.votes < 255) {
      ++pending.votes;
    }

    if (pending.votes < 2) {
      task.workspaceKey = previous->second;
    } else {
      m_pendingWorkspaceTransitions.erase(task.handleKey);
    }
  }

  for (auto it = m_pendingWorkspaceTransitions.begin(); it != m_pendingWorkspaceTransitions.end();) {
    if (!seenHandles.contains(it->first)) {
      it = m_pendingWorkspaceTransitions.erase(it);
    } else {
      ++it;
    }
  }

  if (modelsEqual(nextTasks, nextWorkspaces)) {
    m_tasks = std::move(nextTasks);
    m_workspaces = std::move(nextWorkspaces);
    return;
  }
  m_tasks = std::move(nextTasks);
  m_workspaces = std::move(nextWorkspaces);
  m_rebuildPending = true;
  if (root() != nullptr) {
    root()->markLayoutDirty();
  }
}

bool TaskbarWidget::onPointerEvent(const PointerEvent& event) {
  if (m_contextMenuPopup == nullptr || !m_contextMenuPopup->isOpen()) {
    return false;
  }
  const bool consumed = m_contextMenuPopup->onPointerEvent(event);
  if (!consumed && event.type == PointerEvent::Type::Button && event.state == 1) {
    m_contextMenuPopup->close();
    return true;
  }
  return consumed;
}

void TaskbarWidget::openTaskContextMenu(const TaskModel& task, InputArea& area) {
  auto* renderContext = PanelManager::instance().renderContext();
  if (renderContext == nullptr) {
    return;
  }

  wl_surface* pointerSurface = m_connection.lastPointerSurface();
  auto* layerSurface = m_connection.layerSurfaceFor(pointerSurface);
  if (layerSurface == nullptr) {
    return;
  }

  const auto windows = m_connection.windowsForApp(task.idLower, task.startupWmClassLower, m_output);
  m_contextMenuHandles.clear();
  m_contextMenuHandles.reserve(windows.size());
  for (const auto& window : windows) {
    if (window.handle != nullptr) {
      m_contextMenuHandles.push_back(window.handle);
    }
  }
  m_contextMenuPrimaryHandle = task.firstHandle;

  std::vector<DesktopAction> entryActions;
  const auto& entriesIndex = desktopEntries();
  for (const auto& entry : entriesIndex) {
    if (entry.idLower == task.idLower || entry.idLower == task.appIdLower ||
        entry.startupWmClassLower == task.idLower || entry.startupWmClassLower == task.startupWmClassLower ||
        entry.nameLower == task.nameLower) {
      entryActions = entry.actions;
      break;
    }
  }

  // IDs 0..N-1 => desktop actions, -1 => close single, -2 => close all.
  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(entryActions.size() + 3);
  for (std::int32_t i = 0; i < static_cast<std::int32_t>(entryActions.size()); ++i) {
    entries.push_back(ContextMenuControlEntry{
        .id = i,
        .label = entryActions[static_cast<std::size_t>(i)].name,
        .enabled = true,
        .separator = false,
        .hasSubmenu = false,
    });
  }
  if (!m_contextMenuHandles.empty()) {
    if (!entries.empty()) {
      entries.push_back(
          ContextMenuControlEntry{.id = -3, .label = {}, .enabled = false, .separator = true, .hasSubmenu = false});
    }
    entries.push_back(ContextMenuControlEntry{
        .id = -1,
        .label = i18n::tr("dock.actions.close"),
        .enabled = m_contextMenuPrimaryHandle != nullptr,
        .separator = false,
        .hasSubmenu = false,
    });
    if (m_contextMenuHandles.size() > 1) {
      entries.push_back(ContextMenuControlEntry{
          .id = -2,
          .label = i18n::tr("dock.actions.close-all"),
          .enabled = true,
          .separator = false,
          .hasSubmenu = false,
      });
    }
  }

  if (entries.empty()) {
    return;
  }

  if (m_contextMenuPopup == nullptr) {
    m_contextMenuPopup = std::make_unique<ContextMenuPopup>(m_connection, *renderContext);
  }
  m_contextMenuPopup->setOnActivate([this, entryActions](const ContextMenuControlEntry& entry) {
    if (entry.id >= 0) {
      const auto idx = static_cast<std::size_t>(entry.id);
      if (idx < entryActions.size()) {
        const auto& action = entryActions[idx];
        std::string cmd;
        cmd.reserve(action.exec.size());
        for (std::size_t i = 0; i < action.exec.size(); ++i) {
          if (action.exec[i] == '%' && i + 1 < action.exec.size()) {
            ++i;
            continue;
          }
          cmd += action.exec[i];
        }
        while (!cmd.empty() && std::isspace(static_cast<unsigned char>(cmd.back()))) {
          cmd.pop_back();
        }
        if (!cmd.empty()) {
          DeferredCall::callLater([cmd]() { (void)process::runAsync(cmd); });
        }
      }
      return;
    }
    if (entry.id == -1) {
      if (m_contextMenuPrimaryHandle != nullptr) {
        m_connection.closeToplevel(m_contextMenuPrimaryHandle);
      }
      return;
    }
    if (entry.id == -2) {
      for (auto* handle : m_contextMenuHandles) {
        if (handle != nullptr) {
          m_connection.closeToplevel(handle);
        }
      }
    }
  });

  float absX = 0.0f;
  float absY = 0.0f;
  Node::absolutePosition(&area, absX, absY);
  const float anchorInset = std::round(std::max(6.0f, Style::spaceSm * m_contentScale));
  float anchorX = absX + anchorInset;
  float anchorY = absY + anchorInset;
  float anchorW = std::max(1.0f, area.width() - (anchorInset * 2.0f));
  float anchorH = std::max(1.0f, area.height() - (anchorInset * 2.0f));

  constexpr float kTaskMenuWidth = 240.0f;
  const float menuWidth = kTaskMenuWidth * m_contentScale;
  const float gap = std::round(std::max(2.0f, Style::spaceMd * m_contentScale));

  // Match tray-style placement intent (open away from bar side) while using the
  // shared ContextMenuPopup default positioner behavior.
  if (m_barPosition == "top") {
    anchorY = absY + area.height() + gap;
    anchorH = 1.0f;
  } else if (m_barPosition == "bottom") {
    anchorY = absY - gap;
    anchorH = 1.0f;
  } else if (m_barPosition == "left") {
    anchorX = absX + area.width() + (menuWidth * 0.5f) + gap;
    anchorW = 1.0f;
  } else if (m_barPosition == "right") {
    anchorX = absX - (menuWidth * 0.5f) - gap;
    anchorW = 1.0f;
  }

  m_contextMenuPopup->open(std::move(entries), menuWidth, 12, static_cast<std::int32_t>(std::round(anchorX)),
                           static_cast<std::int32_t>(std::round(anchorY)),
                           static_cast<std::int32_t>(std::round(anchorW)),
                           static_cast<std::int32_t>(std::round(anchorH)), layerSurface, m_output);
}

std::string TaskbarWidget::toLower(std::string value) { return StringUtils::toLower(std::move(value)); }

std::string TaskbarWidget::workspaceLabel(const Workspace& workspace, std::size_t index) {
  const auto parseLeadingNumber = [](const std::string& value) -> std::optional<std::size_t> {
    if (value.empty() || !std::isdigit(static_cast<unsigned char>(value.front()))) {
      return std::nullopt;
    }
    std::size_t parsed = 0;
    std::size_t i = 0;
    while (i < value.size() && std::isdigit(static_cast<unsigned char>(value[i]))) {
      parsed = parsed * 10 + static_cast<std::size_t>(value[i] - '0');
      ++i;
    }
    return parsed > 0 ? std::optional<std::size_t>(parsed) : std::nullopt;
  };

  if (const auto id = parseLeadingNumber(workspace.id); id.has_value()) {
    return std::to_string(*id);
  }
  if (const auto name = parseLeadingNumber(workspace.name); name.has_value()) {
    return std::to_string(*name);
  }
  if (!workspace.id.empty()) {
    return workspace.id;
  }
  if (!workspace.coordinates.empty()) {
    return std::to_string(static_cast<std::size_t>(workspace.coordinates.front()) + 1u);
  }
  return std::to_string(index + 1);
}

bool TaskbarWidget::modelsEqual(const std::vector<TaskModel>& tasks,
                                const std::vector<WorkspaceModel>& workspaces) const {
  if (tasks.size() != m_tasks.size() || workspaces.size() != m_workspaces.size()) {
    return false;
  }
  for (std::size_t i = 0; i < tasks.size(); ++i) {
    if (tasks[i].appId != m_tasks[i].appId || tasks[i].iconPath != m_tasks[i].iconPath ||
        tasks[i].active != m_tasks[i].active || tasks[i].firstHandle != m_tasks[i].firstHandle ||
        tasks[i].workspaceKey != m_tasks[i].workspaceKey || tasks[i].order != m_tasks[i].order ||
        tasks[i].workspaceOrder != m_tasks[i].workspaceOrder) {
      return false;
    }
  }
  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const auto& a = workspaces[i].workspace;
    const auto& b = m_workspaces[i].workspace;
    if (a.id != b.id || a.name != b.name || a.active != b.active || a.urgent != b.urgent || a.occupied != b.occupied ||
        workspaces[i].key != m_workspaces[i].key || workspaces[i].label != m_workspaces[i].label) {
      return false;
    }
  }
  return true;
}

void TaskbarWidget::buildDesktopIconIndex() {
  m_appIconsByLower.clear();
  const auto& entries = desktopEntries();
  for (const auto& entry : entries) {
    if (entry.icon.empty()) {
      continue;
    }
    if (!entry.id.empty()) {
      m_appIconsByLower[toLower(entry.id)] = entry.icon;
    }
    if (!entry.startupWmClass.empty()) {
      m_appIconsByLower[toLower(entry.startupWmClass)] = entry.icon;
    }
    if (!entry.nameLower.empty()) {
      m_appIconsByLower[entry.nameLower] = entry.icon;
    }
  }
  m_desktopEntriesVersion = desktopEntriesVersion();
}

std::string TaskbarWidget::resolveIconPath(const std::string& appId, const std::string& iconNameOrPath) {
  if (appId.empty()) {
    return {};
  }

  if (!iconNameOrPath.empty()) {
    return m_iconResolver.resolve(iconNameOrPath);
  }

  if (const auto internal = internal_apps::metadataForAppId(appId); internal.has_value()) {
    return internal->iconPath;
  }

  const std::string appIdLower = toLower(appId);
  const auto it = m_appIconsByLower.find(appIdLower);
  if (it != m_appIconsByLower.end()) {
    return m_iconResolver.resolve(it->second);
  }
  return m_iconResolver.resolve(appId);
}

bool TaskbarWidget::activeWorkspaceIndex(std::size_t& index) const {
  for (std::size_t i = 0; i < m_workspaces.size(); ++i) {
    if (m_workspaces[i].workspace.active) {
      index = i;
      return true;
    }
  }
  return false;
}

void TaskbarWidget::activateAdjacentWorkspace(int direction) {
  if (!m_groupByWorkspace || m_workspaces.empty() || direction == 0) {
    return;
  }

  std::size_t targetIndex = 0;
  std::size_t current = 0;
  if (!activeWorkspaceIndex(current)) {
    targetIndex = direction > 0 ? 0 : (m_workspaces.size() - 1);
  } else if (direction > 0) {
    if (current + 1 >= m_workspaces.size()) {
      return;
    }
    targetIndex = current + 1;
  } else {
    if (current == 0) {
      return;
    }
    targetIndex = current - 1;
  }

  m_connection.activateWorkspace(m_output, m_workspaces[targetIndex].workspace);
}
