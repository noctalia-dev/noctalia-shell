#include "launcher/math_provider.h"

#include "tinyexpr.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <unistd.h>

namespace {

bool looksLikeMath(std::string_view text) {
  if (text.empty()) {
    return false;
  }

  bool hasOperator = false;
  bool hasDigit = false;

  for (char c : text) {
    if (c >= '0' && c <= '9') {
      hasDigit = true;
    } else if (c == '+' || c == '*' || c == '/' || c == '^' || c == '%') {
      hasOperator = true;
    } else if (c == '-') {
      // Could be unary minus or subtraction
      hasOperator = true;
    } else if (c == '(' || c == ')' || c == '.' || c == ' ' || c == ',') {
      // Allowed in math expressions
    } else if (std::isalpha(static_cast<unsigned char>(c))) {
      // Allow function names like sin, cos, sqrt, pi, e
    } else {
      return false;
    }
  }

  return hasDigit && hasOperator;
}

std::string formatResult(double value) {
  if (std::isnan(value) || std::isinf(value)) {
    return {};
  }

  // If it's an integer, show without decimals
  if (value == std::floor(value) && std::abs(value) < 1e15) {
    std::ostringstream oss;
    oss.precision(0);
    oss << std::fixed << value;
    return oss.str();
  }

  // Otherwise show with reasonable precision
  std::ostringstream oss;
  oss.precision(10);
  oss << value;
  std::string s = oss.str();

  // Trim trailing zeros after decimal point
  if (s.find('.') != std::string::npos) {
    while (s.back() == '0') {
      s.pop_back();
    }
    if (s.back() == '.') {
      s.pop_back();
    }
  }

  return s;
}

} // namespace

std::vector<LauncherResult> MathProvider::query(std::string_view text) const {
  if (!looksLikeMath(text)) {
    return {};
  }

  std::string expr(text);
  int err = 0;
  double result = te_interp(expr.c_str(), &err);

  if (err != 0) {
    return {};
  }

  std::string formatted = formatResult(result);
  if (formatted.empty()) {
    return {};
  }

  LauncherResult r;
  r.id = "math";
  r.title = "= " + formatted;
  r.subtitle = std::string(text);
  r.iconName = "calculator";
  r.score = 10000;

  return {std::move(r)};
}

bool MathProvider::activate(const LauncherResult& result) {
  if (result.id != "math") {
    return false;
  }

  // Copy the result (without "= " prefix) to clipboard via wl-copy
  std::string value = result.title.substr(2);

  pid_t pid = fork();
  if (pid == 0) {
    execlp("wl-copy", "wl-copy", value.c_str(), nullptr);
    _exit(1);
  }

  return true;
}
