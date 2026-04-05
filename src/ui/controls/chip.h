#pragma once

#include "ui/controls/flex.h"

#include <string_view>

class Label;

// Compact label + rounded fill for inline chips (e.g. workspace).
// Not a Button — no pointer/press semantics
class Chip : public Flex {
public:
  Chip();

  void setText(std::string_view text);
  void setActive(bool active);

  [[nodiscard]] Label* label() const noexcept { return m_label; }

private:
  Label* m_label = nullptr;
};
