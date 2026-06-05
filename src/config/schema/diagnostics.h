#pragma once

#include <string>
#include <utility>
#include <vector>

namespace noctalia::config::schema {

  // Accumulates issues found while reading or validating a config table. The
  // same sink feeds the reload pipeline (warnings) and `noctalia config validate`
  // (errors). `path` is the dotted key path, e.g. "shell.animation.style".
  struct Diagnostics {
    enum class Severity { Warning, Error };

    struct Entry {
      Severity severity;
      std::string path;
      std::string message;
    };

    std::vector<Entry> entries;

    void warn(std::string path, std::string message) {
      entries.push_back({Severity::Warning, std::move(path), std::move(message)});
    }
    void error(std::string path, std::string message) {
      entries.push_back({Severity::Error, std::move(path), std::move(message)});
    }

    [[nodiscard]] bool hasErrors() const {
      for (const auto& e : entries) {
        if (e.severity == Severity::Error) {
          return true;
        }
      }
      return false;
    }
  };

  // Joins a parent path and a key into a dotted path, skipping the leading dot
  // when the parent is empty (top level).
  inline std::string joinPath(std::string_view parent, std::string_view key) {
    if (parent.empty()) {
      return std::string(key);
    }
    std::string out;
    out.reserve(parent.size() + 1 + key.size());
    out.append(parent);
    out.push_back('.');
    out.append(key);
    return out;
  }

} // namespace noctalia::config::schema
