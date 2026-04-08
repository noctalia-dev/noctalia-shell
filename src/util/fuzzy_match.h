#pragma once

#include <string_view>

namespace FuzzyMatch {

  int score(std::string_view pattern, std::string_view text);

} // namespace FuzzyMatch
