#pragma once

#include <array>
#include <chrono>
#include <curl/curl.h>
#include <filesystem>
#include <functional>
#include <poll.h>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class HttpClient {
public:
  using CompletionCallback = std::function<void(bool success)>;

  HttpClient();
  ~HttpClient();

  HttpClient(const HttpClient&) = delete;
  HttpClient& operator=(const HttpClient&) = delete;

  void setOfflineMode(bool offline) { m_offlineMode = offline; }

  // Start an async download of url to destPath.
  // cb is always invoked on the main loop thread on a later iteration — never
  // synchronously from inside this call, even when offline mode or an early
  // local error means the request is never issued. Callers can rely on this
  // to avoid reentrant state mutation.
  void download(std::string_view url, const std::filesystem::path& destPath, CompletionCallback cb);

  // Fire-and-forget async POST. Same callback semantics as download().
  void post(std::string_view url, std::string body, std::string_view contentType, CompletionCallback cb);

  // PollSource integration — called by HttpClientPollSource.
  void addPollFds(std::vector<pollfd>& fds);
  [[nodiscard]] int timeoutMs() const;
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx);

private:
  struct Transfer {
    std::filesystem::path destPath;
    std::filesystem::path tempPath;
    FILE* file = nullptr;
    std::vector<CompletionCallback> callbacks;
    std::string destKey;
    std::string url;
    std::array<char, CURL_ERROR_SIZE> errorBuffer{};
  };

  struct PostTransfer {
    std::string body;
    curl_slist* headers = nullptr;
    CompletionCallback callback;
    std::string url;
    std::array<char, CURL_ERROR_SIZE> errorBuffer{};
  };

  void finishTransfer(CURL* easy, CURLcode result);
  void finishPostTransfer(CURL* easy, CURLcode result);
  void performMulti(const char* reason);
  [[nodiscard]] bool hasActiveTransfers() const;

  CURLM* m_multi = nullptr;
  int m_running = 0;
  std::chrono::steady_clock::time_point m_lastServiceAt{};
  bool m_offlineMode = false;
  std::unordered_map<CURL*, Transfer> m_transfers;
  std::unordered_map<CURL*, PostTransfer> m_postTransfers;
  std::unordered_map<std::string, CURL*> m_activeByDest;
};
