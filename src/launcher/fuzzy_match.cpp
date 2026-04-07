#include "launcher/fuzzy_match.h"

#include "launcher/desktop_entry.h"

#include <algorithm>
#include <cctype>

namespace FuzzyMatch {

namespace {

bool isWordBoundary(std::string_view text, std::size_t pos) {
  if (pos == 0) {
    return true;
  }
  char prev = text[pos - 1];
  char curr = text[pos];
  if (prev == ' ' || prev == '-' || prev == '_' || prev == '.') {
    return true;
  }
  // camelCase transition
  if (std::islower(static_cast<unsigned char>(prev)) && std::isupper(static_cast<unsigned char>(curr))) {
    return true;
  }
  return false;
}

} // namespace

int score(std::string_view pattern, std::string_view text) {
  if (pattern.empty()) {
    return 1; // Empty pattern matches everything with minimal score
  }
  if (text.empty()) {
    return 0;
  }

  // Lowercase both for comparison
  std::string patLower(pattern.size(), '\0');
  std::string textLower(text.size(), '\0');
  std::transform(pattern.begin(), pattern.end(), patLower.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  std::transform(text.begin(), text.end(), textLower.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

  // Quick check: all pattern chars must exist in text
  {
    std::size_t ti = 0;
    for (std::size_t pi = 0; pi < patLower.size(); ++pi) {
      bool found = false;
      while (ti < textLower.size()) {
        if (textLower[ti] == patLower[pi]) {
          ++ti;
          found = true;
          break;
        }
        ++ti;
      }
      if (!found) {
        return 0;
      }
    }
  }

  // Score the match using FZF-style greedy algorithm
  int totalScore = 0;
  std::size_t patIdx = 0;
  std::size_t textIdx = 0;
  int consecutive = 0;

  while (patIdx < patLower.size() && textIdx < textLower.size()) {
    if (textLower[textIdx] == patLower[patIdx]) {
      int charScore = 1;

      // Bonus for word boundary
      if (isWordBoundary(text, textIdx)) {
        charScore += 10;
      }

      // Bonus for consecutive match
      if (consecutive > 0) {
        charScore += 4 * consecutive;
      }

      // Bonus for matching at the start
      if (textIdx == 0) {
        charScore += 8;
      }

      // Exact case match bonus
      if (text[textIdx] == pattern[patIdx]) {
        charScore += 1;
      }

      totalScore += charScore;
      ++consecutive;
      ++patIdx;
    } else {
      consecutive = 0;
    }
    ++textIdx;
  }

  if (patIdx < patLower.size()) {
    return 0; // Not all pattern chars matched
  }

  // Bonus for shorter text (more specific match)
  if (text.size() <= pattern.size() + 2) {
    totalScore += 15;
  }

  return totalScore;
}

int scoreEntry(std::string_view pattern, const DesktopEntry& entry) {
  if (pattern.empty()) {
    return 1;
  }

  int nameScore = score(pattern, entry.nameLower) * 3;
  int genericScore = score(pattern, entry.genericNameLower) * 2;

  // Search keywords (semicolon-separated)
  int keywordScore = 0;
  if (!entry.keywordsLower.empty()) {
    std::string_view kw = entry.keywordsLower;
    std::size_t start = 0;
    while (start < kw.size()) {
      auto semi = kw.find(';', start);
      auto word = (semi == std::string_view::npos) ? kw.substr(start) : kw.substr(start, semi - start);
      if (!word.empty()) {
        keywordScore = std::max(keywordScore, score(pattern, word));
      }
      if (semi == std::string_view::npos) {
        break;
      }
      start = semi + 1;
    }
  }

  int catScore = 0;
  if (!entry.categoriesLower.empty()) {
    std::string_view cat = entry.categoriesLower;
    std::size_t start = 0;
    while (start < cat.size()) {
      auto semi = cat.find(';', start);
      auto word = (semi == std::string_view::npos) ? cat.substr(start) : cat.substr(start, semi - start);
      if (!word.empty()) {
        int s = score(pattern, word);
        catScore = std::max(catScore, s);
      }
      if (semi == std::string_view::npos) {
        break;
      }
      start = semi + 1;
    }
  }

  return std::max({nameScore, genericScore, keywordScore, catScore});
}

} // namespace FuzzyMatch
