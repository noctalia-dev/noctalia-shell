#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace i18n::detail {

  [[nodiscard]] std::string normalizeLanguageTag(std::string_view raw);
  [[nodiscard]] std::vector<std::string> catalogLanguageCandidates(std::string_view raw);

} // namespace i18n::detail
