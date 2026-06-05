#pragma once

#include <atomic>

namespace scripting {

  class ScriptApiContext {
  public:
    [[nodiscard]] bool isDarkMode() const noexcept { return m_darkMode.load(std::memory_order_relaxed); }
    void setDarkMode(bool dark) noexcept { m_darkMode.store(dark, std::memory_order_relaxed); }

  private:
    std::atomic<bool> m_darkMode{true};
  };

} // namespace scripting
