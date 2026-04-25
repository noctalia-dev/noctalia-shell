#pragma once

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
  // cb is called on the main loop thread when the transfer completes or fails.
  void download(std::string_view url, const std::filesystem::path& destPath, CompletionCallback cb);

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
  };

  void finishTransfer(CURL* easy, bool success);

  CURLM* m_multi = nullptr;
  int m_running = 0;
  bool m_offlineMode = false;
  std::unordered_map<CURL*, Transfer> m_transfers;
  std::unordered_map<std::string, CURL*> m_activeByDest;
};
