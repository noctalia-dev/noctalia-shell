#include "compositors/sway/sway_keyboard_backend.h"

#include "core/process.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <json.hpp>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace {

  [[nodiscard]] bool containsToken(std::string_view haystack, std::string_view needle) {
    if (haystack.empty() || needle.empty()) {
      return false;
    }
    std::string lhs(haystack);
    std::string rhs(needle);
    std::ranges::transform(lhs, lhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    std::ranges::transform(rhs, rhs.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return lhs.find(rhs) != std::string::npos;
  }

  [[nodiscard]] std::optional<std::string> runAndCapture(const std::vector<std::string>& args) {
    if (args.empty() || args.front().empty()) {
      return std::nullopt;
    }

    int pipefd[2];
    if (::pipe(pipefd) != 0) {
      return std::nullopt;
    }

    const pid_t pid = ::fork();
    if (pid < 0) {
      ::close(pipefd[0]);
      ::close(pipefd[1]);
      return std::nullopt;
    }

    if (pid == 0) {
      ::close(pipefd[0]);
      ::dup2(pipefd[1], STDOUT_FILENO);
      ::close(pipefd[1]);

      std::vector<char*> argv;
      argv.reserve(args.size() + 1);
      for (const auto& arg : args) {
        argv.push_back(const_cast<char*>(arg.c_str()));
      }
      argv.push_back(nullptr);
      ::execvp(argv[0], argv.data());
      ::_exit(127);
    }

    ::close(pipefd[1]);
    std::string output;
    char buffer[4096];
    ssize_t count = 0;
    while ((count = ::read(pipefd[0], buffer, sizeof(buffer))) > 0) {
      output.append(buffer, static_cast<std::size_t>(count));
    }
    ::close(pipefd[0]);

    int status = 0;
    if (::waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
      return std::nullopt;
    }

    return output;
  }

} // namespace

SwayKeyboardBackend::SwayKeyboardBackend(std::string_view compositorHint) {
  const bool hinted = containsToken(compositorHint, "sway");
  const char* swaySock = std::getenv("SWAYSOCK");
  m_enabled = hinted || (swaySock != nullptr && swaySock[0] != '\0');
  m_msgCommand = process::commandExists("swaymsg") ? "swaymsg" : "i3-msg";
}

bool SwayKeyboardBackend::isAvailable() const noexcept { return m_enabled && !m_msgCommand.empty(); }

bool SwayKeyboardBackend::cycleLayout() const {
  if (!isAvailable()) {
    return false;
  }
  return process::runSync({m_msgCommand, "input", "type:keyboard", "xkb_switch_layout", "next"});
}

std::optional<KeyboardLayoutState> SwayKeyboardBackend::layoutState() const {
  const auto current = currentLayoutName();
  if (!current.has_value()) {
    return std::nullopt;
  }
  return KeyboardLayoutState{{*current}, 0};
}

std::optional<std::string> SwayKeyboardBackend::currentLayoutName() const {
  if (!isAvailable()) {
    return std::nullopt;
  }

  const auto payload = runAndCapture({m_msgCommand, "-t", "get_inputs", "--raw"});
  if (!payload.has_value() || payload->empty()) {
    return std::nullopt;
  }

  try {
    const auto json = nlohmann::json::parse(*payload);
    if (!json.is_array()) {
      return std::nullopt;
    }
    for (const auto& input : json) {
      if (!input.is_object()) {
        continue;
      }
      if (input.value("type", "") != "keyboard") {
        continue;
      }
      const std::string layout = input.value("xkb_active_layout_name", "");
      if (!layout.empty()) {
        return layout;
      }
    }
  } catch (const nlohmann::json::exception&) {
    return std::nullopt;
  }

  return std::nullopt;
}
