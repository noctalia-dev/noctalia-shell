#pragma once

#include <chrono>
#include <cstdint>
#include <functional>

class TimeService {
public:
    using TickCallback = std::function<void()>;

    void setTickCallback(TickCallback callback);
    [[nodiscard]] int pollTimeoutMs() const;
    void tick();

private:
    TickCallback m_callback;
    std::int64_t m_lastSecond = -1;
};
