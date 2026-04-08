#include "core/log.h"

#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <mutex>
#include <string>
#include <system_error>

namespace {

LogLevel gMinLevel = LogLevel::Info;
FILE* gLogFile = nullptr;
std::mutex gLogMutex;

constexpr std::size_t kMaxLogBytes = 1 * 1024 * 1024; // 1 MB

const char* levelTagAnsi(LogLevel level) {
  switch (level) {
  case LogLevel::Debug:
    return "\033[36mDBG\033[0m";
  case LogLevel::Info:
    return "\033[32mINF\033[0m";
  case LogLevel::Warn:
    return "\033[33mWRN\033[0m";
  case LogLevel::Error:
    return "\033[31mERR\033[0m";
  }
  return "???";
}

const char* levelTagPlain(LogLevel level) {
  switch (level) {
  case LogLevel::Debug:
    return "DBG";
  case LogLevel::Info:
    return "INF";
  case LogLevel::Warn:
    return "WRN";
  case LogLevel::Error:
    return "ERR";
  }
  return "???";
}

} // namespace

void initLogFile() {
  const char* cacheHome = std::getenv("XDG_CACHE_HOME");
  const char* home = std::getenv("HOME");

  std::string dir;
  if (cacheHome != nullptr && cacheHome[0] != '\0') {
    dir = std::string(cacheHome) + "/noctalia";
  } else if (home != nullptr && home[0] != '\0') {
    dir = std::string(home) + "/.cache/noctalia";
  } else {
    return; // no writable location available
  }

  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  if (ec) {
    return;
  }

  const std::string logPath = dir + "/noctalia.log";
  const std::string backupPath = dir + "/noctalia.log.1";

  const auto size = std::filesystem::file_size(logPath, ec);
  if (!ec && size > kMaxLogBytes) {
    std::filesystem::rename(logPath, backupPath, ec);
  }

  std::lock_guard lock(gLogMutex);
  gLogFile = std::fopen(logPath.c_str(), "a");
}

namespace detail {

void logMessage(LogLevel level, const char* section, std::string_view msg) {
  std::timespec ts{};
  std::timespec_get(&ts, TIME_UTC);
  std::tm tm{};
  localtime_r(&ts.tv_sec, &tm);

  std::lock_guard lock(gLogMutex);

  // Console: respects gMinLevel, ANSI colours, time only
  if (level >= gMinLevel) {
    if (section != nullptr && section[0] != '\0') {
      std::fprintf(stderr, "%02d:%02d:%02d.%03ld [%s] [\033[34m%s\033[0m] %.*s\n", tm.tm_hour, tm.tm_min, tm.tm_sec,
                   ts.tv_nsec / 1'000'000, levelTagAnsi(level), section, static_cast<int>(msg.size()), msg.data());
    } else {
      std::fprintf(stderr, "%02d:%02d:%02d.%03ld [%s] %.*s\n", tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1'000'000,
                   levelTagAnsi(level), static_cast<int>(msg.size()), msg.data());
    }
  }

  // File: always unfiltered, no ANSI, full date for context
  if (gLogFile != nullptr) {
    if (section != nullptr && section[0] != '\0') {
      std::fprintf(gLogFile, "%04d-%02d-%02d %02d:%02d:%02d.%03ld [%s] [%s] %.*s\n", tm.tm_year + 1900, tm.tm_mon + 1,
                   tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1'000'000, levelTagPlain(level), section,
                   static_cast<int>(msg.size()), msg.data());
    } else {
      std::fprintf(gLogFile, "%04d-%02d-%02d %02d:%02d:%02d.%03ld [%s] %.*s\n", tm.tm_year + 1900, tm.tm_mon + 1,
                   tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1'000'000, levelTagPlain(level),
                   static_cast<int>(msg.size()), msg.data());
    }
    std::fflush(gLogFile);
  }
}

} // namespace detail

void setLogLevel(LogLevel level) { gMinLevel = level; }
