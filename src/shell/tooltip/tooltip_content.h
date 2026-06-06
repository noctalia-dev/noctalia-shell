#pragma once

#include <string>
#include <variant>
#include <vector>

struct TooltipRow {
  std::string key;
  std::string value;
};

enum class TooltipPlacement : std::uint8_t {
  Default,
  Above,
  Below,
  Left,
  Right,
};

struct TooltipAnchorInsets {
  float top = 0.0f;
  float right = 0.0f;
  float bottom = 0.0f;
  float left = 0.0f;
};

using TooltipContent = std::variant<std::monostate, std::string, std::vector<TooltipRow>>;
