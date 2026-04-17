#pragma once

#include <cmath>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace noctalia::ipc {

  inline std::vector<std::string> splitWords(std::string_view text) {
    std::vector<std::string> words;
    std::istringstream stream{std::string(text)};
    std::string word;
    while (stream >> word) {
      words.push_back(std::move(word));
    }
    return words;
  }

  inline std::optional<float> parseNormalizedOrPercent(std::string_view token, float maxPercent = 100.0f) {
    std::string value(token);
    bool isPercent = false;
    if (!value.empty() && value.back() == '%') {
      isPercent = true;
      value.pop_back();
    }
    if (value.empty()) {
      return std::nullopt;
    }

    std::size_t parsed = 0;
    float amount = 0.0f;
    try {
      amount = std::stof(value, &parsed);
    } catch (...) {
      return std::nullopt;
    }
    if (parsed != value.size() || !std::isfinite(amount)) {
      return std::nullopt;
    }

    if (isPercent || value.find('.') == std::string::npos) {
      if (amount < 0.0f || amount > maxPercent) {
        return std::nullopt;
      }
      return amount / 100.0f;
    }

    if (amount >= 0.0f && amount <= 1.0f) {
      return amount;
    }
    if (amount > 1.0f && amount <= maxPercent) {
      return amount / 100.0f;
    }

    return std::nullopt;
  }

} // namespace noctalia::ipc
