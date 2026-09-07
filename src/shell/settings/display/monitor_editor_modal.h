#pragma once

#include "compositors/display_backend.h"
#include "core/timer_manager.h"
#include "shell/settings/settings_modal_host.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>

class Flex;
class Renderer;

namespace settings::display {

  class DisplayService;
  class RevertDialogModal;

  struct MonitorEditorRequest {
    float scale = 1.0F;
    DisplayService* display = nullptr;
    std::function<void(const std::string&)> onOpenEdid;
    std::function<void()> onClosed;
  };

  class MonitorEditorModal {
  public:
    MonitorEditorModal() = default;
    ~MonitorEditorModal();

    void initialize(SettingsModalHost& host, std::function<void()> dismissSelectDropdown);
    void open(MonitorEditorRequest request);
    void close();

    [[nodiscard]] bool isOpen() const noexcept { return m_open; }
    [[nodiscard]] const std::string& selectedOutput() const { return m_selectedOutput; }
    void setSelectedOutput(std::string name);
    void markDirty() { m_dirty = true; }

    void requestLayout();
    void requestRedraw();

  private:
    [[nodiscard]] std::unique_ptr<Node> build();
    [[nodiscard]] LayoutSize measure(Renderer& renderer, const SettingsModalLayoutSpace& space);
    void arrange(Renderer& renderer, float width, float height);
    void update(Renderer& renderer);
    [[nodiscard]] std::unique_ptr<Flex> buildOutputCard(const compositors::display::OutputState& output);
    void clearNodePointers();

    std::shared_ptr<void> m_aliveGuard = std::make_shared<int>(0);
    SettingsModalHost* m_host = nullptr;
    std::optional<SettingsModalHost::ModalId> m_modalId;
    std::unique_ptr<RevertDialogModal> m_revertDialog;
    std::function<void()> m_dismissSelectDropdown;
    float m_scale = 1.0F;
    DisplayService* m_display = nullptr;
    std::function<void(const std::string&)> m_onOpenEdid;
    std::function<void()> m_onClosed;
    Flex* m_root = nullptr;
    bool m_open = false;
    bool m_dirty = false;
    std::string m_selectedOutput;
    Timer m_scaleDebounceTimer;
    std::string m_scaleDebounceOutput;
  };

} // namespace settings::display
