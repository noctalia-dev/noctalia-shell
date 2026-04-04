#pragma once

#include "ui/controls/Box.h"

#include <string_view>

class Label;

// Compact label + rounded fill for inline chips (e.g. workspace). Not a Button — no
// pointer/press semantics; chrome matches borderless shadcn-style chips.
class Chip : public Box {
public:
  Chip();

  void setText(std::string_view text);
  void setWorkspaceActive(bool active);

  [[nodiscard]] Label* label() const noexcept { return m_label; }

private:
  Label* m_label = nullptr;
};
