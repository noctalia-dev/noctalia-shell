#pragma once

#include "shell/settings/settings_modal_host.h"

#include <functional>
#include <memory>
#include <optional>

class Flex;
class Renderer;

namespace settings::display {

  class DisplayService;

  // "Keep these display settings?" countdown stacked above the monitor editor.
  class RevertDialogModal {
  public:
    RevertDialogModal() = default;
    ~RevertDialogModal();

    void initialize(SettingsModalHost& host);
    void open(DisplayService& display, float scale);
    void close();

    [[nodiscard]] bool isOpen() const noexcept { return m_open; }
    void requestLayout();

  private:
    [[nodiscard]] std::unique_ptr<Node> build();
    [[nodiscard]] LayoutSize measure(Renderer& renderer, const SettingsModalLayoutSpace& space);
    void arrange(Renderer& renderer, float width, float height);
    void update(Renderer& renderer);

    std::shared_ptr<void> m_aliveGuard = std::make_shared<int>(0);
    SettingsModalHost* m_host = nullptr;
    std::optional<SettingsModalHost::ModalId> m_modalId;
    DisplayService* m_display = nullptr;
    float m_scale = 1.0F;
    Flex* m_root = nullptr;
    bool m_open = false;
    int m_lastCountdown = -1;
  };

} // namespace settings::display
