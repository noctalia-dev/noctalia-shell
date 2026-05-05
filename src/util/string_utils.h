#pragma once

#include <algorithm>
#include <cctype>
#include <string>
#include <string_view>

namespace StringUtils {

  [[nodiscard]] inline std::string trim(std::string_view s) {
    std::size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start])) != 0) {
      ++start;
    }
    std::size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1])) != 0) {
      --end;
    }
    return std::string(s.substr(start, end - start));
  }

  [[nodiscard]] inline std::string toLower(std::string_view s) {
    std::string out(s);
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
  }

  inline void toLowerInPlace(std::string& s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  }

  [[nodiscard]] inline bool containsInsensitive(std::string_view haystack, std::string_view needle) {
    if (haystack.empty() || needle.empty()) {
      return false;
    }
    std::string lhs(haystack);
    std::string rhs(needle);
    toLowerInPlace(lhs);
    toLowerInPlace(rhs);
    return lhs.find(rhs) != std::string::npos;
  }

  [[nodiscard]] inline std::string trimLeadingBlankLines(std::string_view text) {
    if (text.empty()) {
      return {};
    }

    std::size_t start = 0;
    while (start < text.size()) {
      std::size_t lineEnd = text.find('\n', start);
      if (lineEnd == std::string_view::npos) {
        lineEnd = text.size();
      }
      const std::string_view line = text.substr(start, lineEnd - start);
      const bool blankLine =
          line.empty() || std::all_of(line.begin(), line.end(), [](unsigned char ch) { return std::isspace(ch) != 0; });
      if (!blankLine) {
        break;
      }
      if (lineEnd >= text.size()) {
        start = text.size();
        break;
      }
      start = lineEnd + 1;
    }

    return std::string(text.substr(start));
  }

  [[nodiscard]] inline std::string truncateByLines(std::string_view text, int maxLines, bool* didTruncate = nullptr) {
    if (didTruncate != nullptr) {
      *didTruncate = false;
    }
    if (maxLines <= 0 || text.empty()) {
      return std::string(text);
    }

    int seenLines = 1;
    std::size_t index = 0;
    while (index < text.size()) {
      if (text[index] == '\n') {
        ++seenLines;
        if (seenLines > maxLines) {
          if (didTruncate != nullptr) {
            *didTruncate = true;
          }
          return std::string(text.substr(0, index));
        }
      }
      ++index;
    }
    return std::string(text);
  }

  // Strip HTML/Pango tags and unescape XML entities.
  [[nodiscard]] inline std::string sanitizeMarkup(std::string_view s) {
    std::string out;
    out.reserve(s.size());

    size_t i = 0;
    while (i < s.size()) {
      if (s[i] == '<') {
        size_t close = s.find('>', i + 1);
        if (close != std::string_view::npos) {
          auto tag = toLower(s.substr(i + 1, close - i - 1));
          if (tag == "br" || tag == "br/" || tag == "br /") {
            out += '\n';
          }
          i = close + 1;
          continue;
        }
      }

      if (s[i] == '&') {
        std::string_view rest = s.substr(i);
        if (rest.substr(0, 4) == "&lt;") {
          out += '<';
          i += 4;
        } else if (rest.substr(0, 4) == "&gt;") {
          out += '>';
          i += 4;
        } else if (rest.substr(0, 5) == "&amp;") {
          out += '&';
          i += 5;
        } else if (rest.substr(0, 6) == "&quot;") {
          out += '"';
          i += 6;
        } else if (rest.substr(0, 6) == "&apos;") {
          out += '\'';
          i += 6;
        } else {
          out += s[i];
          ++i;
        }
      } else {
        out += s[i];
        ++i;
      }
    }

    return out;
  }

} // namespace StringUtils
