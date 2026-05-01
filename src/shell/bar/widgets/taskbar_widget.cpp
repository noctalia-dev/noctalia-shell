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
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/wayland_toplevels.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <linux/input-event-codes.h>
#include <memory>
#include <unordered_map>

TaskbarWidget::TaskbarWidget(WaylandConnection& connection, wl_output* output)
    : m_connection(connection), m_output(output) {
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
  auto appendTaskTile = [&](Flex* parent, const TaskModel& task) {
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
    parent->addChild(std::move(area));
  };

  for (const auto& task : m_tasks) {
    appendTaskTile(m_taskStrip, task);
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
      task.active = activeHandle != nullptr && activeHandle == window.handle;
      task.firstHandle = window.handle;
      task.iconPath = resolveIconPath(task.appId, run.entry.icon);
      nextTasks.push_back(std::move(task));
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

  if (modelsEqual(nextTasks)) {
    return;
  }
  m_tasks = std::move(nextTasks);
  m_rebuildPending = true;
  if (root() != nullptr) {
    root()->markLayoutDirty();
  }
}

std::string TaskbarWidget::toLower(std::string value) { return StringUtils::toLower(std::move(value)); }

bool TaskbarWidget::modelsEqual(const std::vector<TaskModel>& tasks) const {
  if (tasks.size() != m_tasks.size()) {
    return false;
  }
  for (std::size_t i = 0; i < tasks.size(); ++i) {
    if (tasks[i].appId != m_tasks[i].appId || tasks[i].iconPath != m_tasks[i].iconPath ||
        tasks[i].active != m_tasks[i].active || tasks[i].firstHandle != m_tasks[i].firstHandle) {
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
