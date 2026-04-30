#include "util/fuzzy_match.h"

#include "match.h"

#include <cmath>
#include <string>

namespace FuzzyMatch {

  double score(std::string_view pattern, std::string_view text) {
    if (pattern.empty()) {
      return 0.0;
    }
    if (text.empty()) {
      return noMatchScore;
    }

    const std::string needle(pattern);
    const std::string haystack(text);
    if (has_match(needle.c_str(), haystack.c_str()) == 0) {
      return noMatchScore;
    }

    const score_t rawScore = match(needle.c_str(), haystack.c_str());
    if (rawScore == SCORE_MAX) {
      return 1024.0;
    }
    if (rawScore == SCORE_MIN || !std::isfinite(rawScore)) {
      return -1024.0;
    }
    return rawScore;
  }

} // namespace FuzzyMatch
