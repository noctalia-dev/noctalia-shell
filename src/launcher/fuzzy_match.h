#pragma once

#include <string_view>

struct DesktopEntry;

namespace FuzzyMatch {

int score(std::string_view pattern, std::string_view text);

int scoreEntry(std::string_view pattern, const DesktopEntry& entry);

} // namespace FuzzyMatch
