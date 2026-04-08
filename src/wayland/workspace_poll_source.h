#pragma once

#include "app/poll_source.h"
#include "wayland/wayland_connection.h"

class WorkspacePollSource final : public PollSource {
public:
  explicit WorkspacePollSource(WaylandConnection& connection) : m_connection(connection) {}

  [[nodiscard]] int pollTimeoutMs() const override { return m_connection.workspacePollTimeoutMs(); }

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    if (startIdx < fds.size() && fds[startIdx].fd == m_connection.workspacePollFd()) {
      m_connection.dispatchWorkspacePoll(fds[startIdx].revents);
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override {
    if (m_connection.workspacePollFd() >= 0) {
      fds.push_back({.fd = m_connection.workspacePollFd(), .events = m_connection.workspacePollEvents(), .revents = 0});
    }
  }

private:
  WaylandConnection& m_connection;
};
