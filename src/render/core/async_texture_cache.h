#pragma once

#include "app/poll_source.h"
#include "render/core/texture_manager.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class GlSharedContext;

class AsyncTextureCache : public PollSource {
public:
  using ReadyCallback = std::function<void()>;

  AsyncTextureCache();
  ~AsyncTextureCache() override;

  AsyncTextureCache(const AsyncTextureCache&) = delete;
  AsyncTextureCache& operator=(const AsyncTextureCache&) = delete;

  void initialize(GlSharedContext* sharedGl);
  void setReadyCallback(ReadyCallback callback);

  [[nodiscard]] TextureHandle acquire(const std::string& path, int targetSize = 0, bool mipmap = false);
  [[nodiscard]] TextureHandle peek(const std::string& path, int targetSize = 0, bool mipmap = false) const;
  void release(const std::string& path, int targetSize = 0, bool mipmap = false);
  void trimUnused(std::size_t maxUnusedEntries = 0);

  [[nodiscard]] int pollTimeoutMs() const override { return -1; }
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override;

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override;

private:
  struct RequestKey {
    std::string path;
    int targetSize = 0;
    bool mipmap = false;

    [[nodiscard]] bool operator==(const RequestKey& other) const noexcept {
      return path == other.path && targetSize == other.targetSize && mipmap == other.mipmap;
    }
  };

  struct RequestKeyHash {
    [[nodiscard]] std::size_t operator()(const RequestKey& key) const noexcept;
  };

  struct Entry {
    TextureHandle handle;
    int refCount = 0;
    bool failed = false;
    std::uint64_t lastTouch = 0;
  };

  struct DecodedJob {
    RequestKey key;
    std::vector<std::uint8_t> rgba;
    int width = 0;
    int height = 0;
    bool failed = false;
  };

  void workerLoop();
  void signalMain();
  void pushResult(DecodedJob job);
  void makeCurrent();
  void touchEntry(Entry& entry);
  void pruneUnusedEntries(std::size_t maxUnusedEntries);

  [[nodiscard]] static RequestKey makeKey(const std::string& path, int targetSize, bool mipmap);

  GlSharedContext* m_sharedGl = nullptr;
  std::unique_ptr<TextureManager> m_textureManager;
  int m_eventFd = -1;
  std::vector<std::thread> m_workers;
  std::atomic<bool> m_shutdown{false};

  mutable std::mutex m_queueMutex;
  std::condition_variable m_queueCv;
  std::deque<RequestKey> m_jobQueue;
  std::unordered_set<RequestKey, RequestKeyHash> m_inFlight;
  std::unordered_set<RequestKey, RequestKeyHash> m_canceled;

  mutable std::mutex m_resultMutex;
  std::deque<DecodedJob> m_results;

  // Main thread only state.
  std::unordered_map<RequestKey, Entry, RequestKeyHash> m_entries;
  std::uint64_t m_touchSerial = 0;
  ReadyCallback m_readyCallback;
};
