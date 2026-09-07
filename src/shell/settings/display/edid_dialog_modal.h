#pragma once

#include "shell/settings/settings_modal_host.h"

#include <functional>
#include <memory>
#include <optional>
#include <string>

class ClipboardService;
class Flex;
class Renderer;

namespace settings::display {

  class DisplayService;

  struct EdidDialogRequest {
    float scale = 1.0F;
    std::string outputName;
    DisplayService* display = nullptr;
    ClipboardService* clipboard = nullptr;
  };

  class EdidDialogModal {
  public:
    EdidDialogModal() = default;
    ~EdidDialogModal();

    void initialize(SettingsModalHost& host);
    void open(EdidDialogRequest request);
    void close();

    [[nodiscard]] bool isOpen() const noexcept { return m_open; }
    void markDirty() { m_dirty = true; }
    void requestLayout();

  private:
    [[nodiscard]] std::unique_ptr<Node> build();
    [[nodiscard]] LayoutSize measure(Renderer& renderer, const SettingsModalLayoutSpace& space);
    void arrange(Renderer& renderer, float width, float height);
    void update(Renderer& renderer);
    [[nodiscard]] std::string contentText() const;
    [[nodiscard]] std::string copyPayload() const;

    std::shared_ptr<void> m_aliveGuard = std::make_shared<int>(0);
    SettingsModalHost* m_host = nullptr;
    std::optional<SettingsModalHost::ModalId> m_modalId;
    DisplayService* m_display = nullptr;
    ClipboardService* m_clipboard = nullptr;
    std::string m_outputName;
    float m_scale = 1.0F;
    Flex* m_root = nullptr;
    bool m_open = false;
    bool m_dirty = false;
    bool m_showRaw = false;
  };

} // namespace settings::display
