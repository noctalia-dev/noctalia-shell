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
