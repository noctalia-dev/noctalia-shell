#include "render/animation/AnimationManager.hpp"

#include <algorithm>

AnimationManager::Id AnimationManager::animate(float from, float to, float durationMs,
                                                Easing easing,
                                                std::function<void(float)> setter,
                                                std::function<void()> onComplete) {
    Id id = m_nextId++;
    m_animations.push_back(Entry{
        .id = id,
        .animation = Animation{
            .startValue = from,
            .endValue = to,
            .durationMs = durationMs,
            .easing = easing,
            .setter = std::move(setter),
            .onComplete = std::move(onComplete),
        },
    });
    return id;
}

void AnimationManager::cancel(Id id) {
    std::erase_if(m_animations, [id](const Entry& e) { return e.id == id; });
}

void AnimationManager::tick(float deltaMs) {
    for (auto& entry : m_animations) {
        auto& anim = entry.animation;
        if (anim.finished) {
            continue;
        }

        anim.elapsedMs += deltaMs;
        float t = anim.durationMs > 0.0f ? anim.elapsedMs / anim.durationMs : 1.0f;

        if (t >= 1.0f) {
            t = 1.0f;
            anim.finished = true;
        }

        float easedT = applyEasing(anim.easing, t);
        float value = anim.startValue + (anim.endValue - anim.startValue) * easedT;

        if (anim.setter) {
            anim.setter(value);
        }

        if (anim.finished && anim.onComplete) {
            anim.onComplete();
        }
    }

    std::erase_if(m_animations, [](const Entry& e) { return e.animation.finished; });
}

bool AnimationManager::hasActive() const {
    return !m_animations.empty();
}
