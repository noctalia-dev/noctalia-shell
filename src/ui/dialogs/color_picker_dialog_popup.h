#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/dialogs/layer_popup_host.h"

#include <memory>

class Box;
class ColorPickerSheet;
class ConfigService;
class Node;
class PopupSurface;
class RenderContext;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct wl_surface;

class ColorPickerDialogPopup final : public ColorPickerDialogPresenter {
public:
  void initialize(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext,
                  LayerPopupHostRegistry& popupHosts);

  [[nodiscard]] bool openColorPicker() override;
  void closeColorPickerWithoutResult() override;
  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);
  void requestFontLayout();
  void requestThemeRedraw();
  [[nodiscard]] bool isOpen() const noexcept { return m_surface != nullptr; }
  [[nodiscard]] wl_surface* wlSurface() const noexcept;

private:
  enum class CaptureCoordinateSpace : std::uint8_t {
    None,
    PopupLocal,
    ParentMapped,
  };

  void accept(const Color& result);
  void cancel();
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void buildScene(std::uint32_t width, std::uint32_t height);
  void layoutScene(float width, float height);
  void destroyPopup();
  [[nodiscard]] wl_surface* resolveEventSurface(const PointerEvent& event) const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> resolveParentContext() const;
  [[nodiscard]] bool mapPointerEvent(const PointerEvent& event, float& localX, float& localY) const noexcept;
  void syncPointerStateFromCurrentPosition();
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const noexcept;
  [[nodiscard]] float uiScale() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  LayerPopupHostRegistry* m_popupHosts = nullptr;

  std::unique_ptr<PopupSurface> m_surface;
  AnimationManager m_animations;
  std::unique_ptr<Node> m_sceneRoot;
  Box* m_bgNode = nullptr;
  Node* m_contentNode = nullptr;
  ColorPickerSheet* m_sheet = nullptr;
  InputDispatcher m_inputDispatcher;
  bool m_attachedToHost = false;
  wl_surface* m_parentSurface = nullptr;
  CaptureCoordinateSpace m_captureCoordinateSpace = CaptureCoordinateSpace::None;
  bool m_pointerInside = false;
};
