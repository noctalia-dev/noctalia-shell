#pragma once

#include "app/poll_source.h"
#include "render/core/texture_manager.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

// Async thumbnail loader for the wallpaper picker. Worker threads decode and
// downsample images off the main thread; the main loop uploads finished
// pixmaps to GL textures via uploadPending(). The service holds no unbounded
// cache: a texture lives only for the duration of an explicit request/release
// pair, so the panel can drop everything when it pages away or closes.
class ThumbnailService : public PollSource {
public:
  using ReadyCallback = std::function<void()>;

  ThumbnailService();
  ~ThumbnailService() override;

  ThumbnailService(const ThumbnailService&) = delete;
  ThumbnailService& operator=(const ThumbnailService&) = delete;

  void setReadyCallback(ReadyCallback callback);

  // Returns the uploaded handle if already decoded, or {0} if a decode is
  // pending. A first request enqueues a worker job; subsequent requests for
  // the same path are no-ops until the result arrives.
  [[nodiscard]] TextureHandle request(const std::string& path);

  // Destroys the GL texture for a path (if any) and cancels any pending
  // decode. Safe to call whether or not the path was previously requested.
  void release(const std::string& path);

  // Release every currently owned texture and cancel every pending decode.
  void releaseAll();

  // Uploads decoded pixmaps to GL textures. Must run on the main thread with
  // a GL context current. Called from WallpaperPanel::layout().
  void uploadPending();

  [[nodiscard]] int pollTimeoutMs() const override { return -1; }
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override;

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override;

private:
  struct DecodedJob {
    std::string path;
    std::vector<std::uint8_t> rgba;
    int width = 0;
    int height = 0;
    bool failed = false;
  };

  void workerLoop();
  void signalMain();
  void pushResult(DecodedJob job);
  void deleteAllTextures();

  int m_eventFd = -1;
  std::vector<std::thread> m_workers;
  std::atomic<bool> m_shutdown{false};

  mutable std::mutex m_queueMutex;
  std::condition_variable m_queueCv;
  std::deque<std::string> m_jobQueue;
  std::unordered_set<std::string> m_inFlight;
  std::unordered_set<std::string> m_canceled;

  mutable std::mutex m_resultMutex;
  std::deque<DecodedJob> m_results;

  // Main thread only state.
  std::unordered_map<std::string, TextureHandle> m_textures;
  std::unordered_set<std::string> m_failedPaths;
  ReadyCallback m_readyCallback;
};
