#include "time/time_service.h"

#include <chrono>
#include <utility>

TimeService::TimeService() {
  using namespace std::chrono;
  m_now = system_clock::now();
  m_nowSeconds = floor<seconds>(m_now);
}

void TimeService::setTickSecondCallback(TickCallback callback) { m_secondCallback = std::move(callback); }

int TimeService::pollTimeoutMs() const {
  using namespace std::chrono;
  const auto now = system_clock::now();
  const auto nextSecond = floor<seconds>(now) + seconds{1};
  const auto remaining = duration_cast<milliseconds>(nextSecond - now).count();
  return static_cast<int>(std::max<std::int64_t>(1, remaining));
}

void TimeService::tick() {
  using namespace std::chrono;
  m_now = system_clock::now();
  const auto floored = floor<seconds>(m_now);

  if (floored != m_nowSeconds) {
    m_nowSeconds = floored;
    if (m_secondCallback) {
      m_secondCallback();
    }
  }
}
