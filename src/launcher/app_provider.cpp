#include "launcher/app_provider.h"

#include "util/fuzzy_match.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string_view>
#include <unistd.h>

namespace {

int scoreEntry(std::string_view pattern, const DesktopEntry& entry) {
  if (pattern.empty()) {
    return 1;
  }

  int nameScore = FuzzyMatch::score(pattern, entry.nameLower) * 3;
  int genericScore = FuzzyMatch::score(pattern, entry.genericNameLower) * 2;

  auto scoreList = [&](std::string_view list) {
    int best = 0;
    std::size_t start = 0;
    while (start < list.size()) {
      auto semi = list.find(';', start);
      auto word = (semi == std::string_view::npos) ? list.substr(start) : list.substr(start, semi - start);
      if (!word.empty()) {
        best = std::max(best, FuzzyMatch::score(pattern, word));
      }
      if (semi == std::string_view::npos)
        break;
      start = semi + 1;
    }
    return best;
  };

  int keywordScore = scoreList(entry.keywordsLower);
  int catScore = scoreList(entry.categoriesLower);

  return std::max({nameScore, genericScore, keywordScore, catScore});
}

std::string stripFieldCodes(const std::string& exec) {
  std::string result;
  result.reserve(exec.size());
  for (std::size_t i = 0; i < exec.size(); ++i) {
    if (exec[i] == '%' && i + 1 < exec.size()) {
      char next = exec[i + 1];
      if (next == 'f' || next == 'F' || next == 'u' || next == 'U' || next == 'd' || next == 'D' || next == 'n' ||
          next == 'N' || next == 'i' || next == 'c' || next == 'k') {
        ++i; // Skip the field code
        // Also skip trailing space
        if (i + 1 < exec.size() && exec[i + 1] == ' ') {
          ++i;
        }
        continue;
      }
      if (next == '%') {
        result += '%';
        ++i;
        continue;
      }
    }
    result += exec[i];
  }

  // Trim trailing whitespace
  while (!result.empty() && result.back() == ' ') {
    result.pop_back();
  }
  return result;
}

std::vector<std::string> tokenize(const std::string& cmd) {
  std::vector<std::string> args;
  std::string current;
  bool inSingle = false;
  bool inDouble = false;

  for (std::size_t i = 0; i < cmd.size(); ++i) {
    char c = cmd[i];

    if (c == '\'' && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (c == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (c == ' ' && !inSingle && !inDouble) {
      if (!current.empty()) {
        args.push_back(std::move(current));
        current.clear();
      }
      continue;
    }
    current += c;
  }
  if (!current.empty()) {
    args.push_back(std::move(current));
  }
  return args;
}

void launchCommand(const std::string& exec, bool terminal, const std::string& activationToken) {
  std::string cleanExec = stripFieldCodes(exec);

  if (terminal) {
    const char* term = std::getenv("TERMINAL");
    if (term == nullptr) {
      term = "xterm";
    }
    cleanExec = std::string(term) + " -e " + cleanExec;
  }

  pid_t pid = fork();
  if (pid < 0) {
    return;
  }

  if (pid == 0) {
    // Child process
    setsid();

    // Set activation token so the compositor can focus the app's window
    if (!activationToken.empty()) {
      setenv("XDG_ACTIVATION_TOKEN", activationToken.c_str(), 1);
      setenv("DESKTOP_STARTUP_ID", activationToken.c_str(), 1);
    }

    // Close stdin/stdout/stderr
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO) {
        close(devnull);
      }
    }

    auto args = tokenize(cleanExec);
    if (args.empty()) {
      _exit(1);
    }

    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (auto& arg : args) {
      argv.push_back(arg.data());
    }
    argv.push_back(nullptr);

    execvp(argv[0], argv.data());
    _exit(1);
  }

  // Parent: fire and forget. Child is session leader.
  // We intentionally do not waitpid — the child is its own session.
}

} // namespace

AppProvider::AppProvider(WaylandConnection* wayland) : m_wayland(wayland) {}

void AppProvider::initialize() { m_entries = scanDesktopEntries(); }

std::vector<LauncherResult> AppProvider::query(std::string_view text) const {
  auto buildResult = [&](const DesktopEntry& entry, int s) {
    LauncherResult result;
    result.id = entry.path;
    result.title = entry.name;
    result.subtitle = entry.genericName.empty() ? entry.comment : entry.genericName;
    result.iconPath = m_iconResolver.resolve(entry.icon);
    if (result.iconPath.empty()) {
      result.iconPath = m_iconResolver.resolve("application-x-executable");
    }
    result.iconName = result.iconPath.empty() ? "app-window" : "";
    result.score = s;
    return result;
  };

  // Empty query: return all entries in alphabetical order (as stored)
  if (text.empty()) {
    std::vector<LauncherResult> results;
    results.reserve(std::min(m_entries.size(), std::size_t(50)));
    for (std::size_t i = 0; i < m_entries.size() && i < 50; ++i) {
      results.push_back(buildResult(m_entries[i], 0));
    }
    return results;
  }

  std::vector<std::pair<int, const DesktopEntry*>> scored;
  for (const auto& entry : m_entries) {
    int s = scoreEntry(text, entry);
    if (s > 0) {
      scored.emplace_back(s, &entry);
    }
  }
  std::sort(scored.begin(), scored.end(), [](const auto& a, const auto& b) { return a.first > b.first; });

  std::vector<LauncherResult> results;
  results.reserve(std::min(scored.size(), std::size_t(50)));
  for (std::size_t i = 0; i < scored.size() && i < 50; ++i) {
    const auto& [s, entry] = scored[i];
    results.push_back(buildResult(*entry, s));
  }
  return results;
}

bool AppProvider::activate(const LauncherResult& result) {
  for (const auto& entry : m_entries) {
    if (entry.path == result.id) {
      std::string token;
      if (m_wayland != nullptr && m_wayland->hasXdgActivation()) {
        token = m_wayland->requestActivationToken(nullptr);
      }
      launchCommand(entry.exec, entry.terminal, token);
      return true;
    }
  }
  return false;
}
