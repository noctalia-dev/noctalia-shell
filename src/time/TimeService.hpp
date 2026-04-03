#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <string>

class TimeService {
public:
    using Clock = std::chrono::system_clock;
    using TimePoint = Clock::time_point;
    using TickCallback = std::function<void()>;

    void setTickCallback(TickCallback callback);
    [[nodiscard]] int pollTimeoutMs() const;
    void tick();

    [[nodiscard]] TimePoint now() const noexcept { return m_now; }
    [[nodiscard]] std::string format(const char* fmt) const;

private:
    TickCallback m_callback;
    TimePoint m_now{};
    std::int64_t m_lastSecond = -1;
};
