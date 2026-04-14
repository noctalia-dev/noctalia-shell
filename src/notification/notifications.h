#pragma once

#include "notification/notification_manager.h"

#include <string>
#include <utility>

namespace notify {

  inline NotificationManager*& instancePtr() {
    static NotificationManager* ptr = nullptr;
    return ptr;
  }

  inline void setInstance(NotificationManager* manager) { instancePtr() = manager; }

  inline NotificationManager* instance() { return instancePtr(); }

  inline void error(std::string app, std::string title, std::string body) {
    if (auto* m = instancePtr()) {
      m->addInternal(std::move(app), std::move(title), std::move(body), Urgency::Critical);
    }
  }

  inline void info(std::string app, std::string title, std::string body) {
    if (auto* m = instancePtr()) {
      m->addInternal(std::move(app), std::move(title), std::move(body));
    }
  }

} // namespace notify
