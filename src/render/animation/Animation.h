#pragma once

#include <cstdint>
#include <functional>

enum class Easing : std::uint8_t {
  Linear,
  EaseInQuad,
  EaseOutQuad,
  EaseInOutQuad,
  EaseOutCubic,
  EaseInOutCubic,
  EaseOutBack,
};

float applyEasing(Easing easing, float t);

namespace AnimDuration {
inline constexpr float Fast = 100.0f;
inline constexpr float Normal = 200.0f;
inline constexpr float Slow = 400.0f;
} // namespace AnimDuration

struct Animation {
  float startValue = 0.0f;
  float endValue = 0.0f;
  float durationMs = 0.0f;
  float elapsedMs = 0.0f;
  Easing easing = Easing::EaseOutQuad;
  std::function<void(float)> setter;
  std::function<void()> onComplete;
  bool finished = false;
};
