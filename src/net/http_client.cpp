#include "net/http_client.h"

#include <cstdio>
#include <filesystem>
#include <limits>
#include <string>

HttpClient::HttpClient() {
  curl_global_init(CURL_GLOBAL_DEFAULT);
  m_multi = curl_multi_init();
}

HttpClient::~HttpClient() {
  for (auto& [easy, transfer] : m_transfers) {
    curl_multi_remove_handle(m_multi, easy);
    curl_easy_cleanup(easy);
    if (transfer.file != nullptr) {
      std::fclose(transfer.file);
    }
    std::filesystem::remove(transfer.tempPath);
  }
  curl_multi_cleanup(m_multi);
  curl_global_cleanup();
}

void HttpClient::download(std::string_view url, const std::filesystem::path& destPath, CompletionCallback cb) {
  const std::string destKey = destPath.string();
  if (auto activeIt = m_activeByDest.find(destKey); activeIt != m_activeByDest.end()) {
    if (auto transferIt = m_transfers.find(activeIt->second); transferIt != m_transfers.end()) {
      transferIt->second.callbacks.push_back(std::move(cb));
      return;
    }
    m_activeByDest.erase(activeIt);
  }

  const auto tempPath = destPath.parent_path() / (destPath.filename().string() + ".part");

  FILE* f = std::fopen(tempPath.c_str(), "wb");
  if (f == nullptr) {
    cb(false);
    return;
  }

  CURL* easy = curl_easy_init();
  if (easy == nullptr) {
    std::fclose(f);
    cb(false);
    return;
  }

  const std::string urlStr(url);
  curl_easy_setopt(easy, CURLOPT_URL, urlStr.c_str());
  curl_easy_setopt(easy, CURLOPT_WRITEDATA, f);
  curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(easy, CURLOPT_FAILONERROR, 1L);
  curl_easy_setopt(easy, CURLOPT_TIMEOUT, 30L);
  curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);

  Transfer transfer{};
  transfer.destPath = destPath;
  transfer.tempPath = tempPath;
  transfer.file = f;
  transfer.callbacks.push_back(std::move(cb));
  transfer.destKey = destKey;
  m_transfers[easy] = std::move(transfer);
  m_activeByDest[destKey] = easy;
  curl_multi_add_handle(m_multi, easy);
  curl_multi_perform(m_multi, &m_running);
}

void HttpClient::addPollFds(std::vector<pollfd>& fds) {
  if (m_transfers.empty()) {
    return;
  }

  fd_set readfds, writefds, errfds;
  FD_ZERO(&readfds);
  FD_ZERO(&writefds);
  FD_ZERO(&errfds);
  int maxfd = -1;
  curl_multi_fdset(m_multi, &readfds, &writefds, &errfds, &maxfd);

  for (int fd = 0; fd <= maxfd; ++fd) {
    short events = 0;
    if (FD_ISSET(fd, &readfds)) {
      events |= POLLIN;
    }
    if (FD_ISSET(fd, &writefds)) {
      events |= POLLOUT;
    }
    if (events != 0) {
      fds.push_back({fd, events, 0});
    }
  }
}

int HttpClient::timeoutMs() const {
  if (m_transfers.empty()) {
    return -1;
  }
  long timeout = -1;
  curl_multi_timeout(m_multi, &timeout);
  if (timeout < 0) {
    return 1000; // poll at least every second while transfers are active
  }
  return static_cast<int>(std::min(timeout, static_cast<long>(std::numeric_limits<int>::max())));
}

void HttpClient::dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) {
  if (m_transfers.empty()) {
    return;
  }

  curl_multi_perform(m_multi, &m_running);

  CURLMsg* msg = nullptr;
  int msgsLeft = 0;
  while ((msg = curl_multi_info_read(m_multi, &msgsLeft)) != nullptr) {
    if (msg->msg == CURLMSG_DONE) {
      CURL* easy = msg->easy_handle;
      const bool success = (msg->data.result == CURLE_OK);
      finishTransfer(easy, success);
    }
  }
}

void HttpClient::finishTransfer(CURL* easy, bool success) {
  auto it = m_transfers.find(easy);
  if (it == m_transfers.end()) {
    curl_multi_remove_handle(m_multi, easy);
    curl_easy_cleanup(easy);
    return;
  }

  Transfer transfer = std::move(it->second);
  m_transfers.erase(it);
  m_activeByDest.erase(transfer.destKey);

  curl_multi_remove_handle(m_multi, easy);
  curl_easy_cleanup(easy);

  if (transfer.file != nullptr) {
    std::fclose(transfer.file);
    transfer.file = nullptr;
  }

  if (success) {
    std::error_code ec;
    std::filesystem::rename(transfer.tempPath, transfer.destPath, ec);
    if (ec) {
      std::filesystem::copy_file(transfer.tempPath, transfer.destPath,
                                 std::filesystem::copy_options::overwrite_existing, ec);
      std::filesystem::remove(transfer.tempPath);
      success = !ec;
    }
  } else {
    std::filesystem::remove(transfer.tempPath);
  }

  for (auto& callback : transfer.callbacks) {
    callback(success);
  }
}
