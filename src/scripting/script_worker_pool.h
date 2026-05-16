#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace scripting {

  class ScriptWorkerPool {
  public:
    static ScriptWorkerPool& instance();

    ScriptWorkerPool(const ScriptWorkerPool&) = delete;
    ScriptWorkerPool& operator=(const ScriptWorkerPool&) = delete;

    void post(std::function<void()> task);

  private:
    explicit ScriptWorkerPool(std::size_t workerCount = 4);
    ~ScriptWorkerPool();

    void runWorker();

    std::mutex m_mutex;
    std::condition_variable m_cv;
    std::deque<std::function<void()>> m_tasks;
    std::vector<std::thread> m_workers;
    bool m_stopping = false;
  };

} // namespace scripting
