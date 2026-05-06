#pragma once

#include "app/poll_source.h"
#include "system/icon_resolver.h"

#include <algorithm>
#include <chrono>
#include <functional>
#include <utility>

class IconThemePollSource final : public PollSource {
private:
  using Clock = std::chrono::steady_clock;

  static constexpr std::chrono::seconds kCheckInterval{60};

public:
  void setChangeCallback(std::function<void()> callback) { m_changeCallback = std::move(callback); }

  [[nodiscard]] int pollTimeoutMs() const override {
    const auto now = Clock::now();
    if (now >= m_nextCheck) {
      return 0;
    }
    return static_cast<int>(std::chrono::ceil<std::chrono::milliseconds>(m_nextCheck - now).count());
  }

  void dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) override {
    const auto now = Clock::now();
    if (now < m_nextCheck) {
      return;
    }

    m_nextCheck = now + kCheckInterval;
    if (IconResolver::checkThemeChanged() && m_changeCallback) {
      m_changeCallback();
    }
  }

protected:
  void doAddPollFds(std::vector<pollfd>& /*fds*/) override {}

private:
  std::function<void()> m_changeCallback;
  Clock::time_point m_nextCheck = Clock::now() + kCheckInterval;
};
