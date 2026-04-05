#pragma once

#include "app/poll_source.h"
#include "config/state_service.h"

class StatePollSource final : public PollSource {
public:
  explicit StatePollSource(StateService& state) : m_state(state) {}

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    if (m_state.watchFd() >= 0 && (fds[startIdx].revents & POLLIN) != 0) {
      m_state.checkReload();
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override {
    if (m_state.watchFd() >= 0) {
      fds.push_back({.fd = m_state.watchFd(), .events = POLLIN, .revents = 0});
    }
  }

private:
  StateService& m_state;
};
