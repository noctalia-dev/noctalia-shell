#include "app/main_loop.h"

#include "app/application.h"
#include "app/poll_source.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "shell/bar/bar.h"
#include "wayland/surface.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <format>
#include <optional>
#include <poll.h>
#include <stdexcept>
#include <typeinfo>
#include <utility>
#include <wayland-client-core.h>

namespace {
  constexpr Logger kLog("main");
  constexpr float kSlowMainLoopOperationDebugMs = 50.0f;
  constexpr float kSlowMainLoopOperationWarnMs = 1000.0f;

  float elapsedSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - start).count();
  }

  template <typename... Args> void logSlowMainLoopOperation(float ms, std::format_string<Args...> fmt, Args&&... args) {
    if (ms >= kSlowMainLoopOperationWarnMs) {
      kLog.warn(fmt, std::forward<Args>(args)...);
    } else if (ms >= kSlowMainLoopOperationDebugMs) {
      kLog.debug(fmt, std::forward<Args>(args)...);
    }
  }
} // namespace

MainLoop::MainLoop(WaylandConnection& wayland, Bar& bar, PollSourcesProvider sourcesProvider)
    : m_wayland(wayland), m_bar(bar), m_sourcesProvider(std::move(sourcesProvider)) {}

void MainLoop::run() {
  while (!Application::s_shutdownRequested) {
    // Process deferred callbacks from the previous iteration
    auto& deferred = DeferredCall::queue();
    if (!deferred.empty()) {
      auto pending = std::move(deferred);
      deferred.clear();
      for (auto& fn : pending) {
        fn();
      }
    }

    auto opStart = std::chrono::steady_clock::now();
    while (wl_display_prepare_read(m_wayland.display()) != 0) {
      opStart = std::chrono::steady_clock::now();
      if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to dispatch pending Wayland events");
      }
      const float ms = elapsedSince(opStart);
      logSlowMainLoopOperation(ms, "wl_display_dispatch_pending took {:.1f}ms before poll", ms);
    }
    bool waylandReadPrepared = true;

    // Try to flush queued requests. If the kernel send buffer is full we get
    // EAGAIN; that is the standard Wayland backpressure signal, not a fatal
    // error. In that case ask poll() to also wake us when the fd is writable
    // and retry the flush before dispatching anything else.
    short waylandPollEvents = POLLIN;
    int flushRet = 0;
    opStart = std::chrono::steady_clock::now();
    do {
      flushRet = wl_display_flush(m_wayland.display());
    } while (flushRet < 0 && errno == EINTR);
    float ms = elapsedSince(opStart);
    logSlowMainLoopOperation(ms, "wl_display_flush took {:.1f}ms before poll", ms);
    const bool flushBlocked = flushRet < 0;
    if (flushBlocked) {
      if (errno != EAGAIN) {
        wl_display_cancel_read(m_wayland.display());
        waylandReadPrepared = false;
        throw std::runtime_error("failed to flush Wayland display");
      }
      waylandPollEvents |= POLLOUT;
    }

    // Collect poll fds and compute timeout from all sources. The source list is
    // fetched fresh each iteration so config reloads can add/remove poll sources
    // (e.g. polkit/brightness) without leaving stale pointers in the loop.
    const std::vector<PollSource*> sources = m_sourcesProvider ? m_sourcesProvider() : std::vector<PollSource*>{};
    std::vector<pollfd> pollFds;
    pollFds.push_back({.fd = wl_display_get_fd(m_wayland.display()), .events = waylandPollEvents, .revents = 0});

    int pollTimeout = -1;
    std::vector<std::size_t> sourceStartIndices;
    sourceStartIndices.reserve(sources.size());

    for (auto* source : sources) {
      sourceStartIndices.push_back(source->addPollFds(pollFds));

      const int t = source->pollTimeoutMs();
      if (t >= 0 && (pollTimeout < 0 || t < pollTimeout)) {
        pollTimeout = t;
      }
    }
    if (Surface::hasPendingFrameWork() || Surface::hasPendingRenders()) {
      pollTimeout = 0;
    }

    // If the flush was blocked, raise the timeout floor so we actually wait
    // for POLLOUT instead of tight-looping with a 0-timeout source on top of
    // a full kernel buffer. ~16ms caps the spin at one frame at 60Hz.
    if (flushBlocked && pollTimeout >= 0 && pollTimeout < 16) {
      pollTimeout = 16;
    }

#ifndef NDEBUG
    // Spin canary: if a source votes pollTimeoutMs()==0 for >100ms continuously,
    // the loop is hot-looping. Asymmetric guards between pollTimeoutMs() and
    // dispatch() are the usual cause. Throttled to one warn per 5s.
    {
      using SteadyClock = std::chrono::steady_clock;
      static std::optional<SteadyClock::time_point> s_zeroSince;
      static std::optional<SteadyClock::time_point> s_lastWarn;
      const auto now = SteadyClock::now();
      if (pollTimeout == 0) {
        if (!s_zeroSince) {
          s_zeroSince = now;
        } else if (now - *s_zeroSince > std::chrono::milliseconds(100) &&
                   (!s_lastWarn || now - *s_lastWarn > std::chrono::seconds(5))) {
          s_lastWarn = now;
          for (auto* src : sources) {
            if (src->pollTimeoutMs() == 0) {
              kLog.warn("main loop spin: {} keeps voting timeout=0", typeid(*src).name());
            }
          }
        }
      } else {
        s_zeroSince.reset();
      }
    }
#endif

    const int pollResult = ::poll(pollFds.data(), pollFds.size(), pollTimeout);
    if (pollResult < 0) {
      if (waylandReadPrepared) {
        wl_display_cancel_read(m_wayland.display());
        waylandReadPrepared = false;
      }
      if (errno == EINTR) {
        continue;
      }
      throw std::runtime_error("failed to poll fds");
    }

    // If we were waiting for the wayland fd to become writable, retry the
    // flush now. A persistent EAGAIN just defers to the next iteration.
    if ((waylandPollEvents & POLLOUT) != 0 && (pollFds[0].revents & POLLOUT) != 0) {
      opStart = std::chrono::steady_clock::now();
      do {
        flushRet = wl_display_flush(m_wayland.display());
      } while (flushRet < 0 && errno == EINTR);
      ms = elapsedSince(opStart);
      logSlowMainLoopOperation(ms, "wl_display_flush took {:.1f}ms after POLLOUT", ms);
      if (flushRet < 0 && errno != EAGAIN) {
        if (waylandReadPrepared) {
          wl_display_cancel_read(m_wayland.display());
          waylandReadPrepared = false;
        }
        throw std::runtime_error("failed to flush Wayland display");
      }
    }

    // Read and dispatch Wayland events. Keep socket reads separate from
    // callback dispatch so stalls identify which half is actually slow.
    const bool waylandReadable = (pollFds[0].revents & (POLLIN | POLLERR | POLLHUP)) != 0;
    if (waylandReadable) {
      opStart = std::chrono::steady_clock::now();
      if (wl_display_read_events(m_wayland.display()) < 0) {
        waylandReadPrepared = false;
        throw std::runtime_error("failed to read Wayland events");
      }
      ms = elapsedSince(opStart);
      logSlowMainLoopOperation(ms, "wl_display_read_events took {:.1f}ms", ms);
      waylandReadPrepared = false;
    } else {
      wl_display_cancel_read(m_wayland.display());
      waylandReadPrepared = false;
    }

    opStart = std::chrono::steady_clock::now();
    if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
      throw std::runtime_error("failed to dispatch pending Wayland events");
    }
    ms = elapsedSince(opStart);
    if (waylandReadable) {
      logSlowMainLoopOperation(ms, "wl_display_dispatch_pending took {:.1f}ms after read", ms);
    } else {
      logSlowMainLoopOperation(ms, "wl_display_dispatch_pending took {:.1f}ms after poll", ms);
    }

    // Dispatch all sources. A source callback (notably config reload) can
    // synchronously rebuild services and destroy optional poll sources (e.g.
    // polkit) mid-iteration. Re-check liveness before each dispatch to avoid
    // dereferencing a pointer that was valid when we built `sources` but was
    // freed by an earlier source in this same pass.
    for (std::size_t i = 0; i < sources.size(); ++i) {
      auto* source = sources[i];
      const std::vector<PollSource*> latestSources =
          m_sourcesProvider ? m_sourcesProvider() : std::vector<PollSource*>{};
      if (std::find(latestSources.begin(), latestSources.end(), source) == latestSources.end()) {
        continue;
      }
      opStart = std::chrono::steady_clock::now();
      source->dispatch(pollFds, sourceStartIndices[i]);
      ms = elapsedSince(opStart);
      logSlowMainLoopOperation(ms, "poll source {} dispatch took {:.1f}ms", typeid(*source).name(), ms);
    }

    opStart = std::chrono::steady_clock::now();
    Surface::drainPendingFrameWork();
    ms = elapsedSince(opStart);
    logSlowMainLoopOperation(ms, "queued surface frame work took {:.1f}ms", ms);

    opStart = std::chrono::steady_clock::now();
    Surface::drainPendingRenders();
    ms = elapsedSince(opStart);
    logSlowMainLoopOperation(ms, "queued surface rendering took {:.1f}ms", ms);
  }

  // Close all UI surfaces immediately and flush Wayland to make them disappear
  kLog.debug("closing bar surfaces for clean shutdown");
  m_bar.closeAllInstances();

  if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
    kLog.warn("failed to dispatch pending Wayland events during shutdown");
  }
  if (wl_display_flush(m_wayland.display()) < 0) {
    kLog.warn("failed to flush Wayland display during shutdown");
  }
}
