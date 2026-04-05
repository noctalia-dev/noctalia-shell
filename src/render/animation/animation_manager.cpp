#include "render/animation/animation_manager.h"

#include <algorithm>

AnimationManager::Id AnimationManager::animate(float from, float to, float durationMs, Easing easing,
                                               std::function<void(float)> setter, std::function<void()> onComplete) {
  Id id = m_nextId++;
  m_animations.push_back(Entry{
      .id = id,
      .animation =
          Animation{
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

void AnimationManager::cancelAll() { m_animations.clear(); }

void AnimationManager::tick(float deltaMs) {
  // Collect completed callbacks separately — onComplete may call animate()
  // which would push_back and invalidate iterators during iteration.
  std::vector<std::function<void()>> completedCallbacks;

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
      completedCallbacks.push_back(std::move(anim.onComplete));
    }
  }

  std::erase_if(m_animations, [](const Entry& e) { return e.animation.finished; });

  for (auto& cb : completedCallbacks) {
    cb();
  }
}

bool AnimationManager::hasActive() const { return !m_animations.empty(); }
