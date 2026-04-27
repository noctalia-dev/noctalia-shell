#include "compositors/keyboard_backend.h"

#include "compositors/compositor_detect.h"
#include "compositors/hyprland/hyprland_keyboard_backend.h"
#include "compositors/mango/mango_keyboard_backend.h"
#include "compositors/niri/niri_keyboard_backend.h"
#include "compositors/sway/sway_keyboard_backend.h"

#include <memory>
#include <optional>
#include <string>
#include <string_view>

class KeyboardBackend::Impl {
public:
  virtual ~Impl() = default;
  [[nodiscard]] virtual bool isAvailable() const noexcept = 0;
  [[nodiscard]] virtual bool cycleLayout() const = 0;
  [[nodiscard]] virtual std::optional<KeyboardLayoutState> layoutState() const = 0;
  [[nodiscard]] virtual std::optional<std::string> currentLayoutName() const = 0;
};

namespace {

  template <typename BackendT> class BackendAdapter final : public KeyboardBackend::Impl {
  public:
    explicit BackendAdapter(std::string_view compositorHint) : m_backend(compositorHint) {}

    [[nodiscard]] bool isAvailable() const noexcept override { return m_backend.isAvailable(); }
    [[nodiscard]] bool cycleLayout() const override { return m_backend.cycleLayout(); }
    [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const override { return m_backend.layoutState(); }
    [[nodiscard]] std::optional<std::string> currentLayoutName() const override {
      return m_backend.currentLayoutName();
    }

  private:
    BackendT m_backend;
  };

} // namespace

KeyboardBackend::KeyboardBackend() {
  const std::string compositorHint(compositors::envHint());

  switch (compositors::detect()) {
  case compositors::CompositorKind::Niri:
    m_impl = std::make_unique<BackendAdapter<NiriKeyboardBackend>>(compositorHint);
    return;
  case compositors::CompositorKind::Hyprland:
    m_impl = std::make_unique<BackendAdapter<HyprlandKeyboardBackend>>(compositorHint);
    return;
  case compositors::CompositorKind::Mango:
    m_impl = std::make_unique<BackendAdapter<MangoKeyboardBackend>>(compositorHint);
    return;
  case compositors::CompositorKind::Sway:
    m_impl = std::make_unique<BackendAdapter<SwayKeyboardBackend>>(compositorHint);
    return;
  case compositors::CompositorKind::Unknown:
    break;
  }
}

KeyboardBackend::~KeyboardBackend() = default;
KeyboardBackend::KeyboardBackend(KeyboardBackend&&) noexcept = default;
KeyboardBackend& KeyboardBackend::operator=(KeyboardBackend&&) noexcept = default;

bool KeyboardBackend::isAvailable() const noexcept { return m_impl != nullptr && m_impl->isAvailable(); }

bool KeyboardBackend::cycleLayout() const { return m_impl != nullptr && m_impl->cycleLayout(); }

std::optional<KeyboardLayoutState> KeyboardBackend::layoutState() const {
  if (m_impl == nullptr) {
    return std::nullopt;
  }
  return m_impl->layoutState();
}

std::optional<std::string> KeyboardBackend::currentLayoutName() const {
  if (m_impl == nullptr) {
    return std::nullopt;
  }
  return m_impl->currentLayoutName();
}
