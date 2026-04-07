#pragma once

#include "app/poll_source.h"
#include "system/desktop_entry.h"

class DesktopEntryPollSource final : public PollSource {
public:
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    if (desktopEntryWatchFd() >= 0 && (fds[startIdx].revents & POLLIN) != 0) {
      checkDesktopEntryReload();
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override {
    if (desktopEntryWatchFd() >= 0) {
      fds.push_back({.fd = desktopEntryWatchFd(), .events = POLLIN, .revents = 0});
    }
  }
};
