#pragma once

#include "app/poll_source.h"
#include "shell/desktop/desktop_widgets_controller.h"

class DesktopWidgetsPollSource final : public PollSource {
public:
  explicit DesktopWidgetsPollSource(DesktopWidgetsController& controller) : m_controller(controller) {}

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    if (m_controller.watchFd() >= 0 && (fds[startIdx].revents & POLLIN) != 0) {
      m_controller.checkReload();
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override {
    if (m_controller.watchFd() >= 0) {
      fds.push_back({.fd = m_controller.watchFd(), .events = POLLIN, .revents = 0});
    }
  }

private:
  DesktopWidgetsController& m_controller;
};
