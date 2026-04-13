#pragma once

#include "render/animation/animation.h"

#include <cstdint>
#include <functional>
#include <vector>

class AnimationManager {
public:
  using Id = std::uint32_t;

  AnimationManager();
  ~AnimationManager();

  AnimationManager(const AnimationManager&) = delete;
  AnimationManager& operator=(const AnimationManager&) = delete;
  AnimationManager(AnimationManager&&) = delete;
  AnimationManager& operator=(AnimationManager&&) = delete;

  Id animate(float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
             std::function<void()> onComplete = {}, const void* owner = nullptr);
  void cancel(Id id);
  void cancelAll();
  // Cancels any animations tagged with the given owner. Called from Node's destructor so that
  // animations holding a raw pointer to a scene node can never outlive their target.
  void cancelForOwner(const void* owner);
  void tick(float deltaMs);
  [[nodiscard]] bool hasActive() const;

private:
  struct Entry {
    Id id = 0;
    const void* owner = nullptr;
    Animation animation;
  };

  std::vector<Entry> m_animations;
  Id m_nextId = 1;
};
