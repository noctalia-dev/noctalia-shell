#pragma once

#include "render/animation/Animation.hpp"

#include <cstdint>
#include <functional>
#include <vector>

class AnimationManager {
public:
    using Id = std::uint32_t;

    AnimationManager() = default;

    Id animate(float from, float to, float durationMs, Easing easing,
              std::function<void(float)> setter,
              std::function<void()> onComplete = {});
    void cancel(Id id);
    void tick(float deltaMs);
    [[nodiscard]] bool hasActive() const;

private:
    struct Entry {
        Id id = 0;
        Animation animation;
    };

    std::vector<Entry> m_animations;
    Id m_nextId = 1;
};
