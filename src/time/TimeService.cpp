#include "time/TimeService.hpp"

#include <format>

void TimeService::setTickSecondCallback(TickCallback callback) {
    m_secondCallback = std::move(callback);
}

int TimeService::pollTimeoutMs() const {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto ms = duration_cast<milliseconds>(now.time_since_epoch()).count() % 1000;
    return static_cast<int>(1000 - ms);
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

std::string TimeService::format(const char* fmt) const {
    const auto local = std::chrono::current_zone()->to_local(m_nowSeconds);
    return std::vformat(fmt, std::make_format_args(local));
}
