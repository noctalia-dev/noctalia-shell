#pragma once

#include <memory>
#include <string>
#include <string_view>

class Box;
class Node;
class Panel;
class PanelManager;
class Renderer;
struct wl_output;

/// Layer-shell integration: open the registered `color-picker` panel as a modal over the
/// current panel without destroying the host scene. All scene mutations live here, not in
/// `PanelManager`.
class PanelColorPickerModal {
public:
  [[nodiscard]] static std::unique_ptr<PanelColorPickerModal>
  openOverHost(PanelManager& pm, wl_output* output, float anchorX, float anchorY, std::string_view context);

  void prepareFrame(PanelManager& pm, bool needsUpdate, bool needsLayout);
  void close(PanelManager& pm);
  void prepareForDestroyPanel(PanelManager& pm);
  void frameTickHostIfPresent(PanelManager& pm, float deltaMs) const;

private:
  PanelColorPickerModal() = default;

  void attach(PanelManager& pm);
  void layoutScene(PanelManager& pm, float w, float h, Renderer& renderer);
  void shrinkSurfaceToHost(PanelManager& pm) const;

  std::string m_hostPanelId;
  Panel* m_hostPanel = nullptr;
  Node* m_modalRoot = nullptr;
  Box* m_modalBg = nullptr;
};
