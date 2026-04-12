#include "render/animation/motion_service.h"

#include "render/animation/animation_manager.h"

#include <algorithm>

MotionService& MotionService::instance() {
  static MotionService service;
  return service;
}

void MotionService::registerManager(AnimationManager* manager) {
  if (manager == nullptr) {
    return;
  }
  m_managers.insert(manager);
}

void MotionService::unregisterManager(AnimationManager* manager) {
  if (manager == nullptr) {
    return;
  }
  m_managers.erase(manager);
}

void MotionService::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  if (!m_enabled) {
    for (auto* manager : m_managers) {
      if (manager != nullptr) {
        manager->cancelAll();
      }
    }
  }
}

void MotionService::setSpeed(float speed) { m_speed = std::clamp(speed, 0.05f, 4.0f); }
