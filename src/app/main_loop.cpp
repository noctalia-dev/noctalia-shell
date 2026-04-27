#include "app/main_loop.h"

#include "app/application.h"
#include "app/poll_source.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "shell/bar/bar.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cerrno>
#include <poll.h>
#include <stdexcept>
#include <wayland-client-core.h>

namespace {
  constexpr Logger kLog("main");
} // namespace

MainLoop::MainLoop(WaylandConnection& wayland, Bar& bar, PollSourcesProvider sourcesProvider)
    : m_wayland(wayland), m_bar(bar), m_sourcesProvider(std::move(sourcesProvider)) {}

void MainLoop::run() {
  while (m_bar.isRunning() && !Application::s_shutdownRequested) {
    // Process deferred callbacks from the previous iteration
    auto& deferred = DeferredCall::queue();
    if (!deferred.empty()) {
      auto pending = std::move(deferred);
      deferred.clear();
      for (auto& fn : pending) {
        fn();
      }
    }

    if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
      throw std::runtime_error("failed to dispatch pending Wayland events");
    }

    // Try to flush queued requests. If the kernel send buffer is full we get
    // EAGAIN; that is the standard Wayland backpressure signal, not a fatal
    // error. In that case ask poll() to also wake us when the fd is writable
    // and retry the flush before dispatching anything else.
    short waylandPollEvents = POLLIN;
    int flushRet = 0;
    do {
      flushRet = wl_display_flush(m_wayland.display());
    } while (flushRet < 0 && errno == EINTR);
    const bool flushBlocked = flushRet < 0;
    if (flushBlocked) {
      if (errno != EAGAIN) {
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

    // If the flush was blocked, raise the timeout floor so we actually wait
    // for POLLOUT instead of tight-looping with a 0-timeout source on top of
    // a full kernel buffer. ~16ms caps the spin at one frame at 60Hz.
    if (flushBlocked && pollTimeout >= 0 && pollTimeout < 16) {
      pollTimeout = 16;
    }

    const int pollResult = ::poll(pollFds.data(), pollFds.size(), pollTimeout);
    if (pollResult < 0) {
      if (errno == EINTR) {
        continue;
      }
      throw std::runtime_error("failed to poll fds");
    }

    // If we were waiting for the wayland fd to become writable, retry the
    // flush now. A persistent EAGAIN just defers to the next iteration.
    if ((waylandPollEvents & POLLOUT) != 0 && (pollFds[0].revents & POLLOUT) != 0) {
      do {
        flushRet = wl_display_flush(m_wayland.display());
      } while (flushRet < 0 && errno == EINTR);
      if (flushRet < 0 && errno != EAGAIN) {
        throw std::runtime_error("failed to flush Wayland display");
      }
    }

    // Dispatch Wayland events
    if ((pollFds[0].revents & POLLIN) != 0) {
      if (wl_display_dispatch(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
      }
    } else {
      if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to dispatch pending Wayland events");
      }
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
      source->dispatch(pollFds, sourceStartIndices[i]);
    }
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
