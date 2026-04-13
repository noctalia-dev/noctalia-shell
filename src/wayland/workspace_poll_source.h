#pragma once

#include "app/poll_source.h"
#include "wayland/wayland_connection.h"

class WorkspacePollSource final : public PollSource {
public:
  explicit WorkspacePollSource(WaylandConnection& connection) : m_connection(connection) {}

  [[nodiscard]] int pollTimeoutMs() const override { return m_connection.workspacePollTimeoutMs(); }

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    m_connection.dispatchWorkspacePoll(fds, startIdx);
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override { (void)m_connection.addWorkspacePollFds(fds); }

private:
  WaylandConnection& m_connection;
};
