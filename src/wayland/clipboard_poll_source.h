#pragma once

#include "app/poll_source.h"
#include "wayland/clipboard_service.h"

class ClipboardPollSource final : public PollSource {
public:
  explicit ClipboardPollSource(ClipboardService& clipboard) : m_clipboard(clipboard) {}

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    if (startIdx < fds.size() && fds[startIdx].fd == m_clipboard.activeReadFd()) {
      m_clipboard.dispatchReadEvents(fds[startIdx].revents);
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override {
    if (m_clipboard.activeReadFd() >= 0) {
      fds.push_back({.fd = m_clipboard.activeReadFd(), .events = POLLIN | POLLHUP | POLLERR, .revents = 0});
    }
  }

private:
  ClipboardService& m_clipboard;
};
