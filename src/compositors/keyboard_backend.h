#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

struct KeyboardLayoutState {
  std::vector<std::string> names;
  int currentIndex = -1;
};

class KeyboardBackend {
public:
  class Impl;

  KeyboardBackend();
  ~KeyboardBackend();

  KeyboardBackend(const KeyboardBackend&) = delete;
  KeyboardBackend& operator=(const KeyboardBackend&) = delete;
  KeyboardBackend(KeyboardBackend&&) noexcept;
  KeyboardBackend& operator=(KeyboardBackend&&) noexcept;

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] bool cycleLayout() const;
  [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const;
  [[nodiscard]] std::optional<std::string> currentLayoutName() const;

private:
  std::unique_ptr<Impl> m_impl;
};
