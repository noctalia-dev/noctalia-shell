#pragma once

#include <chrono>
#include <functional>
#include <string>

// Called every poll iteration. Tracks both full-precision and seconds-precision
// time. The second callback fires once per second boundary.
class TimeService {
public:
    using Clock = std::chrono::system_clock;
    using TimePoint = Clock::time_point;
    using SecondPoint = std::chrono::time_point<Clock, std::chrono::seconds>;
    using TickCallback = std::function<void()>;

    void setTickSecondCallback(TickCallback callback);
    [[nodiscard]] int pollTimeoutMs() const;
    void tick();

    [[nodiscard]] TimePoint now() const noexcept { return m_now; }
    [[nodiscard]] std::string format(const char* fmt) const;

private:
    TickCallback m_secondCallback;
    TimePoint m_now{};
    SecondPoint m_nowSeconds{};
};
