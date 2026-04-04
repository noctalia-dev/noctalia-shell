#pragma once

#include <chrono>
#include <functional>
#include <string>

// Fires a callback once per second boundary. m_nowSeconds is a seconds-precision
// time point, so it may lag real time by up to ~999ms.
class TimeService {
public:
    using Clock = std::chrono::system_clock;
    using SecondPoint = std::chrono::time_point<Clock, std::chrono::seconds>;
    using TickCallback = std::function<void()>;

    void setTickSecondCallback(TickCallback callback);
    [[nodiscard]] int pollTimeoutMs() const;
    void tickSecond();

    [[nodiscard]] SecondPoint now() const noexcept { return m_nowSeconds; }
    [[nodiscard]] std::string format(const char* fmt) const;

private:
    TickCallback m_secondCallback;
    SecondPoint m_nowSeconds{};
};
