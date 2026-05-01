#include "shell/bar/widgets/taskbar_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "system/app_identity.h"
#include "system/desktop_entry.h"
#include "system/internal_app_metadata.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/wayland_toplevels.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <limits>
#include <linux/input-event-codes.h>
#include <memory>
#include <optional>
#include <unordered_map>

TaskbarWidget::TaskbarWidget(WaylandConnection& connection, wl_output* output, bool groupByWorkspace)
    : m_connection(connection), m_output(output), m_groupByWorkspace(groupByWorkspace) {
  buildDesktopIconIndex();
}

void TaskbarWidget::create() {
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
  setRoot(std::move(root));
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
  const float indicatorSize = std::max(2.0f, Style::spaceXs * 0.4f * m_contentScale);
  auto createTaskTile = [&](const TaskModel& task) {
    auto area = std::make_unique<InputArea>();
    area->setFrameSize(tileSize, tileSize);
    if (task.firstHandle != nullptr) {
      area->setOnClick([this, handle = task.firstHandle](const InputArea::PointerData& data) {
        if (data.button == BTN_LEFT) {
          m_connection.activateToplevel(handle);
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
      auto indicator = std::make_unique<Box>();
      indicator->setFill(roleColor(ColorRole::Primary));
      indicator->setRadius(indicatorSize * 0.5f);
      indicator->setFrameSize(indicatorSize, indicatorSize);
      indicator->setPosition(std::round((tileSize - indicatorSize) * 0.5f), std::round(tileSize - indicatorSize));
      area->addChild(std::move(indicator));
    }
    return area;
  };

  if (m_groupByWorkspace && !m_workspaces.empty()) {
    const float capsuleRadius = Style::radiusLg * m_contentScale;
    const float groupGap = Style::spaceXs * m_contentScale;
    const float groupPadY = Style::spaceXs * 0.35f * m_contentScale;
    const float groupPadRight = Style::spaceXs * 0.55f * m_contentScale;
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
      if (tasks.empty()) {
        continue;
      }

      const auto badgeMetrics = renderer.measureText(ws.label, badgeFontSize, true);
      const float badgeTextWidth = std::max(0.0f, badgeMetrics.right - badgeMetrics.left);
      const float badgeWidth = std::round(std::max(badgeBase, badgeTextWidth + (Style::spaceXs * m_contentScale)));
      const float groupPadLeft = std::round(std::max(groupPadRight, badgeWidth * 0.68f));
      const float groupWidth = std::round(groupPadLeft + groupPadRight + (tileSize * static_cast<float>(tasks.size())) +
                                          (groupGap * static_cast<float>(tasks.size() - 1)));
      const float groupHeight = std::round(tileSize + (groupPadY * 2.0f));

      auto group = std::make_unique<Box>();
      group->setFrameSize(groupWidth, groupHeight);
      group->setFill(roleColor(ColorRole::SurfaceVariant, ws.workspace.active ? 0.52f : 0.18f));
      group->setBorder(roleColor(ColorRole::Primary, ws.workspace.active ? 0.65f : 0.16f), Style::borderWidth);
      group->setRadius(capsuleRadius);
      auto* groupPtr = static_cast<Box*>(m_taskStrip->addChild(std::move(group)));

      for (std::size_t i = 0; i < tasks.size(); ++i) {
        auto tile = createTaskTile(*tasks[i]);
        tile->setPosition(std::round(groupPadLeft + (tileSize + groupGap) * static_cast<float>(i)),
                          std::round(groupPadY));
        groupPtr->addChild(std::move(tile));
      }

      auto badge = std::make_unique<Box>();
      badge->setFrameSize(badgeWidth, badgeBase);
      badge->setRadius(badgeBase * 0.5f);
      badge->setFill(roleColor(ws.workspace.active ? ColorRole::Primary : ColorRole::Surface));
      badge->setBorder(roleColor(ColorRole::Outline, 0.45f), Style::borderWidth);
      badge->setPosition(std::round(badgeWidth * -0.32f), std::round(badgeBase * -0.22f));
      auto* badgePtr = static_cast<Box*>(groupPtr->addChild(std::move(badge)));

      auto badgeText = std::make_unique<Label>();
      badgeText->setText(ws.label);
      badgeText->setBold(true);
      badgeText->setFontSize(badgeFontSize);
      badgeText->setColor(roleColor(ws.workspace.active ? ColorRole::OnPrimary : ColorRole::OnSurface));
      badgeText->measure(renderer);
      badgeText->setPosition(std::round((badgeWidth - badgeText->width()) * 0.5f),
                             std::round((badgeBase - badgeText->height()) * 0.5f));
      badgePtr->addChild(std::move(badgeText));
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
  }

  std::vector<TaskModel> nextTasks;
  for (const auto& run : resolvedRunning) {
    const std::string idLower = !run.entry.id.empty() ? toLower(run.entry.id) : run.runningLower;
    const std::string startupLower = toLower(run.entry.startupWmClass);
    const std::string nameLower = !run.entry.nameLower.empty() ? run.entry.nameLower : run.runningLower;
    const std::string appId = !run.entry.id.empty() ? run.entry.id : run.runningAppId;

    const auto windows = m_connection.windowsForApp(idLower, startupLower, m_output);
    for (const auto& window : windows) {
      TaskModel task{};
      task.handleKey = reinterpret_cast<std::uintptr_t>(window.handle);
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

  if (m_groupByWorkspace && !workspaceAssignments.empty()) {
    std::vector<bool> used(workspaceAssignments.size(), false);
    auto assignByTitle = [&](TaskModel& task, bool requireTitle) -> bool {
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
        if (requireTitle && assignment.title.empty()) {
          continue;
        }
        if (requireTitle && assignment.title != task.title) {
          continue;
        }
        task.workspaceKey = assignment.workspaceKey;
        used[i] = true;
        return true;
      }
      return false;
    };

    for (auto& task : nextTasks) {
      (void)assignByTitle(task, true);
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
        const std::string assignmentAppLower = toLower(assignment.appId);
        if (assignmentAppLower != task.appIdLower && assignmentAppLower != task.idLower &&
            assignmentAppLower != task.startupWmClassLower && assignmentAppLower != task.nameLower) {
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
        used[*matchIndex] = true;
      }
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

  // Keep task positions stable by first-seen toplevel handle order.
  for (const auto& task : nextTasks) {
    if (!m_taskOrder.contains(task.handleKey)) {
      m_taskOrder[task.handleKey] = m_nextTaskOrder++;
    }
  }
  std::stable_sort(nextTasks.begin(), nextTasks.end(), [this](const TaskModel& a, const TaskModel& b) {
    const auto aIt = m_taskOrder.find(a.handleKey);
    const auto bIt = m_taskOrder.find(b.handleKey);
    const std::size_t aOrder = aIt != m_taskOrder.end() ? aIt->second : std::numeric_limits<std::size_t>::max();
    const std::size_t bOrder = bIt != m_taskOrder.end() ? bIt->second : std::numeric_limits<std::size_t>::max();
    if (aOrder != bOrder) {
      return aOrder < bOrder;
    }
    return a.handleKey < b.handleKey;
  });

  if (modelsEqual(nextTasks, nextWorkspaces)) {
    return;
  }
  m_tasks = std::move(nextTasks);
  m_workspaces = std::move(nextWorkspaces);
  m_rebuildPending = true;
  if (root() != nullptr) {
    root()->markLayoutDirty();
  }
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
        tasks[i].workspaceKey != m_tasks[i].workspaceKey || tasks[i].title != m_tasks[i].title) {
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
