#pragma once

#include <memory>
#include <mutex>
#include <string_view>

namespace scripting::plugin_source_locks {

  class SourceLock {
  public:
    explicit SourceLock(std::shared_ptr<std::recursive_mutex> mutex);
    SourceLock(SourceLock&&) noexcept = default;
    SourceLock& operator=(SourceLock&&) noexcept = delete;

    SourceLock(const SourceLock&) = delete;
    SourceLock& operator=(const SourceLock&) = delete;

  private:
    std::shared_ptr<std::recursive_mutex> m_mutex;
    std::unique_lock<std::recursive_mutex> m_lock;
  };

  [[nodiscard]] SourceLock acquire(std::string_view sourceName);

} // namespace scripting::plugin_source_locks
