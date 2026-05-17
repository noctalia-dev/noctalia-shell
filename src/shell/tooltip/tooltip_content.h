#pragma once

#include <string>
#include <variant>
#include <vector>

struct TooltipRow {
  std::string key;
  std::string value;
};

using TooltipContent = std::variant<std::monostate, std::string, std::vector<TooltipRow>>;
