#include "time/TimeService.hpp"

void TimeService::setTickCallback(TickCallback callback) {
    m_callback = std::move(callback);
}

int TimeService::pollTimeoutMs() const {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto ms = duration_cast<milliseconds>(now.time_since_epoch()).count() % 1000;
    return static_cast<int>(1000 - ms);
}

void TimeService::tick() {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto sec = duration_cast<seconds>(now.time_since_epoch()).count();

    if (sec != m_lastSecond) {
        m_lastSecond = sec;
        if (m_callback) {
            m_callback();
        }
    }
}
