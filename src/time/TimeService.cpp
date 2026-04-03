#include "time/TimeService.hpp"

#include <format>

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
        m_now = now;
        if (m_callback) {
            m_callback();
        }
    }
}

std::string TimeService::format(const char* fmt) const {
    const auto truncated = std::chrono::floor<std::chrono::seconds>(m_now);
    const auto local = std::chrono::current_zone()->to_local(truncated);
    return std::vformat(fmt, std::make_format_args(local));
}
