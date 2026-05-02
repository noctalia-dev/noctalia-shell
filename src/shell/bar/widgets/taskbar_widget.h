#pragma once

#include "shell/bar/widget.h"
#include "system/icon_resolver.h"
#include "wayland/wayland_connection.h"

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

class Flex;
struct wl_output;
struct zwlr_foreign_toplevel_handle_v1;

class TaskbarWidget : public Widget {
public:
  TaskbarWidget(WaylandConnection& connection, wl_output* output, bool groupByWorkspace);

  void create() override;

private:
  struct TaskModel {
    std::uintptr_t handleKey = 0;
    std::uint64_t order = 0;
    std::string appId;
    std::string idLower;
    std::string startupWmClassLower;
    std::string nameLower;
    std::string appIdLower;
    std::string title;
    std::string iconPath;
    std::string workspaceKey;
    bool active = false;
    zwlr_foreign_toplevel_handle_v1* firstHandle = nullptr;
  };

  struct WorkspaceModel {
    Workspace workspace;
    std::string key;
    std::string label;
  };

  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;

  void rebuild(Renderer& renderer);
  void clearChildren(Flex* flex) const;
  void buildTaskButtons(Renderer& renderer);
  void updateModels();
  [[nodiscard]] static std::string toLower(std::string value);
  [[nodiscard]] static std::string workspaceLabel(const Workspace& workspace, std::size_t index);
  [[nodiscard]] bool modelsEqual(const std::vector<TaskModel>& tasks,
                                 const std::vector<WorkspaceModel>& workspaces) const;
  void buildDesktopIconIndex();
  [[nodiscard]] std::string resolveIconPath(const std::string& appId, const std::string& iconNameOrPath);
  void activateAdjacentWorkspace(int direction);
  [[nodiscard]] bool activeWorkspaceIndex(std::size_t& index) const;

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  bool m_groupByWorkspace = false;
  bool m_rebuildPending = true;
  bool m_vertical = false;

  Flex* m_root = nullptr;
  Flex* m_taskStrip = nullptr;

  std::vector<TaskModel> m_tasks;
  std::vector<WorkspaceModel> m_workspaces;
  std::unordered_map<std::string, std::string> m_appIconsByLower;
  std::uint64_t m_desktopEntriesVersion = 0;
  IconResolver m_iconResolver;
};
