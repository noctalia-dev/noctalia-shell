#include "compositors/keyboard_backend.h"

#include "compositors/hyprland/hyprland_keyboard_backend.h"
#include "compositors/mango/mango_keyboard_backend.h"
#include "compositors/niri/niri_keyboard_backend.h"
#include "compositors/sway/sway_keyboard_backend.h"
#include "util/string_utils.h"

#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace {

  [[nodiscard]] std::string compositorHintFromEnv() {
    constexpr const char* vars[] = {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION"};
    std::string hint;
    for (const char* var : vars) {
      const char* value = std::getenv(var);
      if (value == nullptr || value[0] == '\0') {
        continue;
      }
      if (!hint.empty()) {
        hint += ':';
      }
      hint += value;
    }
    return hint;
  }

} // namespace

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
  const std::string compositorHint = compositorHintFromEnv();

  if (StringUtils::containsInsensitive(compositorHint, "niri") || std::getenv("NIRI_SOCKET") != nullptr) {
    m_impl = std::make_unique<BackendAdapter<NiriKeyboardBackend>>(compositorHint);
    return;
  }

  if (StringUtils::containsInsensitive(compositorHint, "hyprland") ||
      StringUtils::containsInsensitive(compositorHint, "hypr") ||
      std::getenv("HYPRLAND_INSTANCE_SIGNATURE") != nullptr) {
    m_impl = std::make_unique<BackendAdapter<HyprlandKeyboardBackend>>(compositorHint);
    return;
  }

  if (StringUtils::containsInsensitive(compositorHint, "mango") ||
      StringUtils::containsInsensitive(compositorHint, "dwl")) {
    m_impl = std::make_unique<BackendAdapter<MangoKeyboardBackend>>(compositorHint);
    return;
  }

  if (StringUtils::containsInsensitive(compositorHint, "sway") || std::getenv("SWAYSOCK") != nullptr) {
    m_impl = std::make_unique<BackendAdapter<SwayKeyboardBackend>>(compositorHint);
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
