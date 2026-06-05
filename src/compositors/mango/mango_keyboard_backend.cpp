#include "compositors/mango/mango_keyboard_backend.h"

#include "compositors/mango/mango_runtime.h"

MangoKeyboardBackend::MangoKeyboardBackend(compositors::mango::MangoRuntime& runtime) : m_runtime(runtime) {}

bool MangoKeyboardBackend::isAvailable() const noexcept { return m_runtime.available(); }

bool MangoKeyboardBackend::cycleLayout() const { return m_runtime.dispatch("switch_keyboard_layout"); }

std::optional<KeyboardLayoutState> MangoKeyboardBackend::layoutState() const {
  const auto current = currentLayoutName();
  if (!current.has_value()) {
    return std::nullopt;
  }
  return KeyboardLayoutState{{*current}, 0};
}

std::optional<std::string> MangoKeyboardBackend::currentLayoutName() const {
  const auto response = m_runtime.request("get keyboardlayout");
  if (!response.has_value() || !response->is_object()) {
    return std::nullopt;
  }
  const auto layoutIt = response->find("layout");
  if (layoutIt == response->end() || !layoutIt->is_string()) {
    return std::nullopt;
  }
  return layoutIt->get<std::string>();
}
