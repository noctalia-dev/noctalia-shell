#include "ext-session-lock-v1-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <linux/memfd.h>
#include <memory>
#include <poll.h>
#include <string>
#include <string_view>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>

namespace {

  volatile std::sig_atomic_t g_interrupted = 0;

  void handleSignal(int /*signal*/) { g_interrupted = 1; }

  int createMemfd(const char* name) {
#ifdef SYS_memfd_create
    return static_cast<int>(::syscall(SYS_memfd_create, name, MFD_CLOEXEC));
#else
    errno = ENOSYS;
    return -1;
#endif
  }

  struct ShmBuffer {
    wl_buffer* buffer = nullptr;
    void* data = MAP_FAILED;
    std::size_t size = 0;
    int fd = -1;
    int width = 0;
    int height = 0;

    ShmBuffer() = default;
    ShmBuffer(const ShmBuffer&) = delete;
    ShmBuffer& operator=(const ShmBuffer&) = delete;

    ~ShmBuffer() { reset(); }

    void reset() {
      if (buffer != nullptr) {
        wl_buffer_destroy(buffer);
        buffer = nullptr;
      }
      if (data != MAP_FAILED) {
        ::munmap(data, size);
        data = MAP_FAILED;
      }
      if (fd >= 0) {
        ::close(fd);
        fd = -1;
      }
      size = 0;
      width = 0;
      height = 0;
    }

    bool create(wl_shm* shm, int nextWidth, int nextHeight, std::uint32_t color) {
      reset();
      if (shm == nullptr || nextWidth <= 0 || nextHeight <= 0) {
        return false;
      }

      constexpr int kBytesPerPixel = 4;
      width = nextWidth;
      height = nextHeight;
      const int stride = width * kBytesPerPixel;
      size = static_cast<std::size_t>(stride) * static_cast<std::size_t>(height);

      fd = createMemfd("noctalia-lockscreen-layer-probe");
      if (fd < 0) {
        std::cerr << "memfd_create failed: " << std::strerror(errno) << "\n";
        reset();
        return false;
      }
      if (::ftruncate(fd, static_cast<off_t>(size)) != 0) {
        std::cerr << "ftruncate failed: " << std::strerror(errno) << "\n";
        reset();
        return false;
      }

      data = ::mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
      if (data == MAP_FAILED) {
        std::cerr << "mmap failed: " << std::strerror(errno) << "\n";
        reset();
        return false;
      }

      auto* pixels = static_cast<std::uint32_t*>(data);
      const std::size_t pixelCount = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
      for (std::size_t i = 0; i < pixelCount; ++i) {
        pixels[i] = color;
      }

      wl_shm_pool* pool = wl_shm_create_pool(shm, fd, static_cast<int>(size));
      if (pool == nullptr) {
        std::cerr << "wl_shm_create_pool failed\n";
        reset();
        return false;
      }
      buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
      wl_shm_pool_destroy(pool);
      if (buffer == nullptr) {
        std::cerr << "wl_shm_pool_create_buffer failed\n";
        reset();
        return false;
      }
      return true;
    }

    void fillProbePattern() {
      if (data == MAP_FAILED || width <= 0 || height <= 0) {
        return;
      }

      auto* pixels = static_cast<std::uint32_t*>(data);
      for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
          const bool border = x < 8 || y < 8 || x >= width - 8 || y >= height - 8;
          const bool diagonal = std::abs(x - y) < 4 || std::abs((width - x) - y) < 4;
          const bool stripe = ((x / 18) + (y / 18)) % 2 == 0;
          std::uint32_t color = stripe ? 0xff00d1ff : 0xffff2d75;
          if (diagonal) {
            color = 0xffffffff;
          }
          if (border) {
            color = 0xff101014;
          }
          pixels[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = color;
        }
      }
    }

    void fillLockPattern() {
      if (data == MAP_FAILED || width <= 0 || height <= 0) {
        return;
      }

      auto* pixels = static_cast<std::uint32_t*>(data);
      for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
          const bool grid = x % 96 < 3 || y % 96 < 3;
          const bool band = y > height / 2 - 64 && y < height / 2 + 64;
          std::uint32_t color = 0xff101014;
          if (grid) {
            color = 0xff272733;
          }
          if (band) {
            color = ((x / 32) % 2 == 0) ? 0xff2dd4bf : 0xfffb7185;
          }
          pixels[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = color;
        }
      }
    }
  };

  struct OutputInfo {
    std::uint32_t name = 0;
    wl_output* output = nullptr;
    int scale = 1;
    int width = 1920;
    int height = 1080;
  };

  struct Client {
    wl_display* display = nullptr;
    wl_registry* registry = nullptr;
    wl_compositor* compositor = nullptr;
    wl_subcompositor* subcompositor = nullptr;
    wl_shm* shm = nullptr;
    zwlr_layer_shell_v1* layerShell = nullptr;
    ext_session_lock_manager_v1* lockManager = nullptr;
    std::deque<OutputInfo> outputs;

    bool connect() {
      display = wl_display_connect(nullptr);
      if (display == nullptr) {
        std::cerr << "failed to connect to Wayland display\n";
        return false;
      }

      registry = wl_display_get_registry(display);
      if (registry == nullptr) {
        std::cerr << "failed to get Wayland registry\n";
        return false;
      }
      wl_registry_add_listener(registry, &kRegistryListener, this);

      if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0) {
        reportDisplayError("registry roundtrip failed");
        return false;
      }
      return true;
    }

    void disconnect() {
      for (auto& output : outputs) {
        if (output.output != nullptr) {
          wl_output_destroy(output.output);
          output.output = nullptr;
        }
      }
      outputs.clear();
      if (lockManager != nullptr) {
        ext_session_lock_manager_v1_destroy(lockManager);
        lockManager = nullptr;
      }
      if (layerShell != nullptr) {
        zwlr_layer_shell_v1_destroy(layerShell);
        layerShell = nullptr;
      }
      if (shm != nullptr) {
        wl_shm_destroy(shm);
        shm = nullptr;
      }
      if (subcompositor != nullptr) {
        wl_subcompositor_destroy(subcompositor);
        subcompositor = nullptr;
      }
      if (compositor != nullptr) {
        wl_compositor_destroy(compositor);
        compositor = nullptr;
      }
      if (registry != nullptr) {
        wl_registry_destroy(registry);
        registry = nullptr;
      }
      if (display != nullptr) {
        wl_display_disconnect(display);
        display = nullptr;
      }
    }

    ~Client() { disconnect(); }

    [[nodiscard]] bool hasDisplayError() const { return display == nullptr || wl_display_get_error(display) != 0; }

    void reportDisplayError(std::string_view prefix) const {
      if (display == nullptr) {
        std::cerr << prefix << ": display is not connected\n";
        return;
      }

      const int err = wl_display_get_error(display);
      if (err == EPROTO) {
        const wl_interface* interface = nullptr;
        std::uint32_t id = 0;
        const int code = wl_display_get_protocol_error(display, &interface, &id);
        std::cerr << prefix << ": Wayland protocol error";
        if (interface != nullptr) {
          std::cerr << " on " << interface->name << "@" << id;
        }
        std::cerr << " code " << code << "\n";
        return;
      }
      if (err != 0) {
        std::cerr << prefix << ": " << std::strerror(err) << "\n";
        return;
      }
      std::cerr << prefix << "\n";
    }

    static void handleGlobal(void* data, wl_registry* registry, std::uint32_t name, const char* interface,
                             std::uint32_t version) {
      auto* self = static_cast<Client*>(data);
      const std::string_view iface(interface != nullptr ? interface : "");

      if (iface == wl_compositor_interface.name) {
        self->compositor = static_cast<wl_compositor*>(
            wl_registry_bind(registry, name, &wl_compositor_interface, std::min(version, 4u)));
      } else if (iface == wl_subcompositor_interface.name) {
        self->subcompositor =
            static_cast<wl_subcompositor*>(wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
      } else if (iface == wl_shm_interface.name) {
        self->shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
      } else if (iface == wl_output_interface.name) {
        auto* output =
            static_cast<wl_output*>(wl_registry_bind(registry, name, &wl_output_interface, std::min(version, 2u)));
        self->outputs.push_back(OutputInfo{.name = name, .output = output});
        wl_output_add_listener(output, &kOutputListener, &self->outputs.back());
      } else if (iface == zwlr_layer_shell_v1_interface.name) {
        self->layerShell = static_cast<zwlr_layer_shell_v1*>(
            wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, std::min(version, 4u)));
      } else if (iface == ext_session_lock_manager_v1_interface.name) {
        self->lockManager = static_cast<ext_session_lock_manager_v1*>(
            wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, 1));
      }
    }

    static void handleGlobalRemove(void* data, wl_registry* /*registry*/, std::uint32_t name) {
      auto* self = static_cast<Client*>(data);
      std::erase_if(self->outputs, [name](const OutputInfo& output) { return output.name == name; });
    }

    static void handleOutputGeometry(void* /*data*/, wl_output* /*output*/, std::int32_t /*x*/, std::int32_t /*y*/,
                                     std::int32_t /*physicalWidth*/, std::int32_t /*physicalHeight*/,
                                     std::int32_t /*subpixel*/, const char* /*make*/, const char* /*model*/,
                                     std::int32_t /*transform*/) {}

    static void handleOutputMode(void* data, wl_output* /*output*/, std::uint32_t flags, std::int32_t width,
                                 std::int32_t height, std::int32_t /*refresh*/) {
      if ((flags & WL_OUTPUT_MODE_CURRENT) == 0 || width <= 0 || height <= 0) {
        return;
      }
      auto* out = static_cast<OutputInfo*>(data);
      out->width = width;
      out->height = height;
    }

    static void handleOutputDone(void* /*data*/, wl_output* /*output*/) {}

    static void handleOutputScale(void* data, wl_output* /*output*/, std::int32_t factor) {
      auto* out = static_cast<OutputInfo*>(data);
      out->scale = std::max(1, factor);
    }

    static void handleOutputName(void* /*data*/, wl_output* /*output*/, const char* /*name*/) {}

    static void handleOutputDescription(void* /*data*/, wl_output* /*output*/, const char* /*description*/) {}

    static constexpr wl_registry_listener kRegistryListener = {
        .global = &Client::handleGlobal,
        .global_remove = &Client::handleGlobalRemove,
    };

    static constexpr wl_output_listener kOutputListener = {
        .geometry = &Client::handleOutputGeometry,
        .mode = &Client::handleOutputMode,
        .done = &Client::handleOutputDone,
        .scale = &Client::handleOutputScale,
        .name = &Client::handleOutputName,
        .description = &Client::handleOutputDescription,
    };
  };

  template <typename Predicate>
  bool dispatchUntil(Client& client, Predicate predicate, std::chrono::milliseconds timeout) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (!g_interrupted && !predicate()) {
      if (wl_display_prepare_read(client.display) != 0) {
        if (wl_display_dispatch_pending(client.display) < 0) {
          client.reportDisplayError("wl_display_dispatch_pending failed");
          return false;
        }
        continue;
      }

      while (wl_display_flush(client.display) < 0 && errno == EAGAIN) {
        pollfd writable{.fd = wl_display_get_fd(client.display), .events = POLLOUT, .revents = 0};
        if (::poll(&writable, 1, 100) < 0 && errno != EINTR) {
          wl_display_cancel_read(client.display);
          std::cerr << "poll while flushing failed: " << std::strerror(errno) << "\n";
          return false;
        }
      }
      if (client.hasDisplayError()) {
        wl_display_cancel_read(client.display);
        client.reportDisplayError("wl_display_flush failed");
        return false;
      }

      const auto now = std::chrono::steady_clock::now();
      if (now >= deadline) {
        wl_display_cancel_read(client.display);
        return predicate();
      }

      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
      pollfd readable{.fd = wl_display_get_fd(client.display), .events = POLLIN, .revents = 0};
      const int pollResult = ::poll(&readable, 1, static_cast<int>(remaining.count()));
      if (pollResult < 0) {
        wl_display_cancel_read(client.display);
        if (errno == EINTR) {
          continue;
        }
        std::cerr << "poll failed: " << std::strerror(errno) << "\n";
        return false;
      }
      if (pollResult == 0) {
        wl_display_cancel_read(client.display);
        return predicate();
      }

      if (wl_display_read_events(client.display) < 0) {
        client.reportDisplayError("wl_display_read_events failed");
        return false;
      }
      if (wl_display_dispatch_pending(client.display) < 0) {
        client.reportDisplayError("wl_display_dispatch_pending failed");
        return false;
      }
    }

    return predicate();
  }

  struct LockClient;

  struct SubsurfaceProbe {
    wl_surface* surface = nullptr;
    wl_subsurface* subsurface = nullptr;
    ShmBuffer buffer;
    bool mapped = false;

    bool create(Client& client, wl_surface* parent) {
      if (client.compositor == nullptr || client.subcompositor == nullptr || client.shm == nullptr ||
          parent == nullptr) {
        std::cerr << "missing required globals for subsurface probe: compositor=" << (client.compositor != nullptr)
                  << " subcompositor=" << (client.subcompositor != nullptr) << " shm=" << (client.shm != nullptr)
                  << "\n";
        return false;
      }

      surface = wl_compositor_create_surface(client.compositor);
      if (surface == nullptr) {
        std::cerr << "failed to create subsurface wl_surface\n";
        return false;
      }

      subsurface = wl_subcompositor_get_subsurface(client.subcompositor, surface, parent);
      if (subsurface == nullptr) {
        std::cerr << "failed to create wl_subsurface\n";
        return false;
      }

      wl_subsurface_set_position(subsurface, 72, 72);
      wl_subsurface_set_desync(subsurface);

      constexpr int kWidth = 360;
      constexpr int kHeight = 180;
      if (!buffer.create(client.shm, kWidth, kHeight, 0xffa3e635)) {
        return false;
      }
      fillSubsurfacePattern();
      wl_surface_attach(surface, buffer.buffer, 0, 0);
      wl_surface_damage(surface, 0, 0, kWidth, kHeight);
      wl_surface_commit(surface);
      mapped = wl_display_flush(client.display) >= 0;
      return mapped;
    }

    void destroy() {
      buffer.reset();
      if (subsurface != nullptr) {
        wl_subsurface_destroy(subsurface);
        subsurface = nullptr;
      }
      if (surface != nullptr) {
        wl_surface_destroy(surface);
        surface = nullptr;
      }
      mapped = false;
    }

    void fillSubsurfacePattern() {
      if (buffer.data == MAP_FAILED || buffer.width <= 0 || buffer.height <= 0) {
        return;
      }

      auto* pixels = static_cast<std::uint32_t*>(buffer.data);
      for (int y = 0; y < buffer.height; ++y) {
        for (int x = 0; x < buffer.width; ++x) {
          const bool border = x < 10 || y < 10 || x >= buffer.width - 10 || y >= buffer.height - 10;
          const bool cross = std::abs(x - buffer.width / 2) < 6 || std::abs(y - buffer.height / 2) < 6;
          const bool stripe = (x / 24) % 2 == 0;
          std::uint32_t color = stripe ? 0xffa3e635 : 0xfffacc15;
          if (cross) {
            color = 0xff000000;
          }
          if (border) {
            color = 0xffffffff;
          }
          pixels[static_cast<std::size_t>(y) * static_cast<std::size_t>(buffer.width) + static_cast<std::size_t>(x)] =
              color;
        }
      }
    }
  };

  struct LockSurfaceProbe {
    LockClient* owner = nullptr;
    wl_surface* surface = nullptr;
    ext_session_lock_surface_v1* lockSurface = nullptr;
    std::unique_ptr<SubsurfaceProbe> subsurfaceProbe;
    ShmBuffer buffer;
    int fallbackWidth = 1920;
    int fallbackHeight = 1080;
    bool configured = false;
    bool mapped = false;

    void destroy() {
      if (subsurfaceProbe != nullptr) {
        subsurfaceProbe->destroy();
        subsurfaceProbe.reset();
      }
      buffer.reset();
      if (lockSurface != nullptr) {
        ext_session_lock_surface_v1_destroy(lockSurface);
        lockSurface = nullptr;
      }
      if (surface != nullptr) {
        wl_surface_destroy(surface);
        surface = nullptr;
      }
    }

    static void handleConfigure(void* data, ext_session_lock_surface_v1* lockSurface, std::uint32_t serial,
                                std::uint32_t width, std::uint32_t height);

    static constexpr ext_session_lock_surface_v1_listener kListener = {
        .configure = &LockSurfaceProbe::handleConfigure,
    };
  };

  struct LockClient {
    Client client;
    ext_session_lock_v1* lock = nullptr;
    std::vector<std::unique_ptr<LockSurfaceProbe>> surfaces;
    bool locked = false;
    bool finished = false;

    ~LockClient() {
      for (auto& surface : surfaces) {
        if (surface != nullptr) {
          surface->destroy();
        }
      }
      surfaces.clear();
      if (lock != nullptr) {
        if (locked) {
          ext_session_lock_v1_unlock_and_destroy(lock);
          wl_display_flush(client.display);
        } else {
          ext_session_lock_v1_destroy(lock);
        }
        lock = nullptr;
      }
    }

    bool start() {
      if (!client.connect()) {
        return false;
      }
      if (client.compositor == nullptr || client.shm == nullptr || client.lockManager == nullptr) {
        std::cerr << "missing required Wayland globals: compositor=" << (client.compositor != nullptr)
                  << " shm=" << (client.shm != nullptr) << " ext-session-lock=" << (client.lockManager != nullptr)
                  << "\n";
        return false;
      }
      if (client.outputs.empty()) {
        std::cerr << "no Wayland outputs advertised\n";
        return false;
      }

      lock = ext_session_lock_manager_v1_lock(client.lockManager);
      if (lock == nullptr) {
        std::cerr << "failed to create ext_session_lock_v1\n";
        return false;
      }
      ext_session_lock_v1_add_listener(lock, &kListener, this);

      surfaces.reserve(client.outputs.size());
      for (const auto& output : client.outputs) {
        auto probe = std::make_unique<LockSurfaceProbe>();
        probe->owner = this;
        probe->fallbackWidth = output.width;
        probe->fallbackHeight = output.height;
        probe->surface = wl_compositor_create_surface(client.compositor);
        if (probe->surface == nullptr) {
          std::cerr << "failed to create lock wl_surface\n";
          return false;
        }
        probe->lockSurface = ext_session_lock_v1_get_lock_surface(lock, probe->surface, output.output);
        if (probe->lockSurface == nullptr) {
          std::cerr << "failed to create ext_session_lock_surface_v1\n";
          return false;
        }
        ext_session_lock_surface_v1_add_listener(probe->lockSurface, &LockSurfaceProbe::kListener, probe.get());
        surfaces.push_back(std::move(probe));
      }

      return wl_display_flush(client.display) >= 0;
    }

    bool waitLocked(std::chrono::milliseconds timeout) {
      return dispatchUntil(client, [this]() { return locked || finished; }, timeout) && locked && !finished;
    }

    bool createSubsurfaceProbes() {
      bool allCreated = true;
      for (auto& surface : surfaces) {
        if (surface == nullptr || surface->surface == nullptr) {
          allCreated = false;
          continue;
        }

        auto probe = std::make_unique<SubsurfaceProbe>();
        if (!probe->create(client, surface->surface)) {
          allCreated = false;
          continue;
        }
        surface->subsurfaceProbe = std::move(probe);
      }
      return allCreated;
    }

    bool hold(std::chrono::milliseconds timeout) {
      return dispatchUntil(
                 client, [this]() { return client.hasDisplayError() || finished; }, timeout) == false &&
             !client.hasDisplayError() && !finished;
    }

    void unlock() {
      if (lock == nullptr) {
        return;
      }
      if (locked) {
        ext_session_lock_v1_unlock_and_destroy(lock);
        lock = nullptr;
        locked = false;
        wl_display_roundtrip(client.display);
      } else {
        ext_session_lock_v1_destroy(lock);
        lock = nullptr;
      }
    }

    static void handleLocked(void* data, ext_session_lock_v1* /*lock*/) {
      auto* self = static_cast<LockClient*>(data);
      self->locked = true;
    }

    static void handleFinished(void* data, ext_session_lock_v1* /*lock*/) {
      auto* self = static_cast<LockClient*>(data);
      self->finished = true;
    }

    static constexpr ext_session_lock_v1_listener kListener = {
        .locked = &LockClient::handleLocked,
        .finished = &LockClient::handleFinished,
    };
  };

  void LockSurfaceProbe::handleConfigure(void* data, ext_session_lock_surface_v1* lockSurface, std::uint32_t serial,
                                         std::uint32_t width, std::uint32_t height) {
    auto* self = static_cast<LockSurfaceProbe*>(data);
    ext_session_lock_surface_v1_ack_configure(lockSurface, serial);

    const int bufferWidth = static_cast<int>(width == 0 ? static_cast<std::uint32_t>(self->fallbackWidth) : width);
    const int bufferHeight = static_cast<int>(height == 0 ? static_cast<std::uint32_t>(self->fallbackHeight) : height);
    if (self->owner == nullptr ||
        !self->buffer.create(self->owner->client.shm, bufferWidth, bufferHeight, 0xff101014)) {
      return;
    }
    self->buffer.fillLockPattern();
    wl_surface_attach(self->surface, self->buffer.buffer, 0, 0);
    wl_surface_damage(self->surface, 0, 0, bufferWidth, bufferHeight);
    wl_surface_commit(self->surface);
    self->configured = true;
    self->mapped = true;
  }

  struct LayerProbe {
    Client client;
    wl_surface* surface = nullptr;
    zwlr_layer_surface_v1* layerSurface = nullptr;
    ShmBuffer buffer;
    bool configured = false;
    bool mapped = false;
    bool closed = false;

    ~LayerProbe() {
      buffer.reset();
      if (layerSurface != nullptr) {
        zwlr_layer_surface_v1_destroy(layerSurface);
        layerSurface = nullptr;
      }
      if (surface != nullptr) {
        wl_surface_destroy(surface);
        surface = nullptr;
      }
    }

    bool start(std::size_t outputIndex) {
      if (!client.connect()) {
        return false;
      }
      if (client.compositor == nullptr || client.shm == nullptr || client.layerShell == nullptr) {
        std::cerr << "second client missing required Wayland globals: compositor=" << (client.compositor != nullptr)
                  << " shm=" << (client.shm != nullptr) << " layer-shell=" << (client.layerShell != nullptr) << "\n";
        return false;
      }

      wl_output* output = nullptr;
      if (outputIndex < client.outputs.size()) {
        output = client.outputs[outputIndex].output;
      }
      surface = wl_compositor_create_surface(client.compositor);
      if (surface == nullptr) {
        std::cerr << "failed to create probe wl_surface\n";
        return false;
      }

      layerSurface = zwlr_layer_shell_v1_get_layer_surface(
          client.layerShell, surface, output, ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "noctalia-lockscreen-layer-probe");
      if (layerSurface == nullptr) {
        std::cerr << "failed to create probe layer surface\n";
        return false;
      }
      zwlr_layer_surface_v1_add_listener(layerSurface, &kListener, this);
      zwlr_layer_surface_v1_set_anchor(layerSurface,
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
      zwlr_layer_surface_v1_set_size(layerSurface, 360, 180);
      zwlr_layer_surface_v1_set_exclusive_zone(layerSurface, -1);
      zwlr_layer_surface_v1_set_margin(layerSurface, 72, 0, 0, 500);
      zwlr_layer_surface_v1_set_keyboard_interactivity(layerSurface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
      wl_surface_commit(surface);
      return wl_display_flush(client.display) >= 0;
    }

    bool waitMapped(std::chrono::milliseconds timeout) {
      return dispatchUntil(
                 client, [this]() { return mapped || closed || client.hasDisplayError(); }, timeout) &&
             mapped && !closed && !client.hasDisplayError();
    }

    bool hold(std::chrono::milliseconds timeout) {
      return dispatchUntil(
                 client, [this]() { return closed || client.hasDisplayError(); }, timeout) == false &&
             !closed && !client.hasDisplayError();
    }

    static void handleConfigure(void* data, zwlr_layer_surface_v1* layerSurface, std::uint32_t serial,
                                std::uint32_t width, std::uint32_t height) {
      auto* self = static_cast<LayerProbe*>(data);
      zwlr_layer_surface_v1_ack_configure(layerSurface, serial);

      const int bufferWidth = static_cast<int>(width == 0 ? 360 : width);
      const int bufferHeight = static_cast<int>(height == 0 ? 180 : height);
      if (!self->buffer.create(self->client.shm, bufferWidth, bufferHeight, 0xff30cfd0)) {
        return;
      }
      self->buffer.fillProbePattern();
      wl_surface_attach(self->surface, self->buffer.buffer, 0, 0);
      wl_surface_damage(self->surface, 0, 0, bufferWidth, bufferHeight);
      wl_surface_commit(self->surface);
      self->configured = true;
      self->mapped = true;
    }

    static void handleClosed(void* data, zwlr_layer_surface_v1* /*layerSurface*/) {
      auto* self = static_cast<LayerProbe*>(data);
      self->closed = true;
    }

    static constexpr zwlr_layer_surface_v1_listener kListener = {
        .configure = &LayerProbe::handleConfigure,
        .closed = &LayerProbe::handleClosed,
    };
  };

} // namespace

int main() {
  std::signal(SIGINT, handleSignal);
  std::signal(SIGTERM, handleSignal);

  LockClient lockClient;
  if (!lockClient.start()) {
    return 1;
  }

  std::cout << "locking session and mapping required lock surfaces...\n";
  if (!lockClient.waitLocked(std::chrono::seconds(5))) {
    if (lockClient.finished) {
      std::cerr << "compositor finished the lock request instead of locking\n";
    } else {
      std::cerr << "timed out waiting for ext_session_lock_v1.locked\n";
    }
    return 1;
  }

  std::cout << "session locked; creating widget-sized wl_subsurface markers on every lock surface...\n";
  const bool subsurfacesCreated = lockClient.createSubsurfaceProbes();

  std::cout << "creating desktop-widget-style layer-shell markers on every advertised output...\n";
  std::vector<std::unique_ptr<LayerProbe>> layerProbes;
  layerProbes.reserve(lockClient.client.outputs.size());
  std::size_t mappedLayerProbes = 0;
  for (std::size_t i = 0; i < lockClient.client.outputs.size(); ++i) {
    auto probe = std::make_unique<LayerProbe>();
    if (probe->start(i) && probe->waitMapped(std::chrono::seconds(3))) {
      ++mappedLayerProbes;
    } else if (probe->client.hasDisplayError()) {
      probe->client.reportDisplayError("layer probe failed");
    } else if (probe->closed) {
      std::cerr << "compositor closed a layer surface before it mapped\n";
    } else {
      std::cerr << "timed out waiting for a layer surface configure/map\n";
    }
    layerProbes.push_back(std::move(probe));
  }

  std::cout << "mapped " << mappedLayerProbes << " layer-shell marker(s); holding for visual inspection...\n";
  const bool ok = subsurfacesCreated && lockClient.hold(std::chrono::seconds(10));
  if (lockClient.client.hasDisplayError()) {
    lockClient.client.reportDisplayError("subsurface probe failed");
  }

  lockClient.unlock();
  if (!ok) {
    std::cerr << "result: failed to keep widget-sized wl_subsurfaces alive on every lock surface\n";
    return 1;
  }

  std::cout << "result: successfully created and committed widget-sized wl_subsurfaces while locked\n";
  return 0;
}
