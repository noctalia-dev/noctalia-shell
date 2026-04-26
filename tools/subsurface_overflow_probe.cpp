#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iostream>
#include <linux/memfd.h>
#include <memory>
#include <poll.h>
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

      fd = createMemfd("noctalia-subsurface-overflow-probe");
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

    static std::uint32_t premul(std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t a) {
      const auto scale = [a](std::uint8_t c) -> std::uint8_t {
        return static_cast<std::uint8_t>((static_cast<unsigned>(c) * static_cast<unsigned>(a) + 127u) / 255u);
      };
      return (static_cast<std::uint32_t>(a) << 24u) | (static_cast<std::uint32_t>(scale(r)) << 16u) |
             (static_cast<std::uint32_t>(scale(g)) << 8u) | static_cast<std::uint32_t>(scale(b));
    }

    static std::uint32_t over(std::uint32_t src, std::uint32_t dst) {
      const std::uint32_t srcA = (src >> 24u) & 0xffu;
      const std::uint32_t invA = 255u - srcA;
      const std::uint32_t dstA = (dst >> 24u) & 0xffu;
      const std::uint32_t srcR = (src >> 16u) & 0xffu;
      const std::uint32_t srcG = (src >> 8u) & 0xffu;
      const std::uint32_t srcB = src & 0xffu;
      const std::uint32_t dstR = (dst >> 16u) & 0xffu;
      const std::uint32_t dstG = (dst >> 8u) & 0xffu;
      const std::uint32_t dstB = dst & 0xffu;
      const std::uint32_t outA = srcA + (dstA * invA + 127u) / 255u;
      const std::uint32_t outR = srcR + (dstR * invA + 127u) / 255u;
      const std::uint32_t outG = srcG + (dstG * invA + 127u) / 255u;
      const std::uint32_t outB = srcB + (dstB * invA + 127u) / 255u;
      return (outA << 24u) | (outR << 16u) | (outG << 8u) | outB;
    }

    void blendPixel(int x, int y, std::uint32_t color) {
      if (data == MAP_FAILED || x < 0 || y < 0 || x >= width || y >= height) {
        return;
      }
      auto* pixels = static_cast<std::uint32_t*>(data);
      auto& dst = pixels[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)];
      dst = over(color, dst);
    }

    void fillVisualPolicyParent(int barY, int barHeight, int badX,
                                const std::vector<std::pair<int, std::uint32_t>>& cleanMarkers, int childWidth) {
      if (data == MAP_FAILED || width <= 0 || height <= 0) {
        return;
      }

      auto* pixels = static_cast<std::uint32_t*>(data);
      std::fill(pixels, pixels + static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0x00000000u);

      const int barX = 32;
      const int barW = width - 64;
      const int shadowStart = barY + barHeight - 2;
      for (int y = shadowStart; y < height; ++y) {
        const int dy = y - shadowStart;
        const std::uint8_t alpha = static_cast<std::uint8_t>(std::max(0, 96 - dy * 4));
        for (int x = barX; x < barX + barW; ++x) {
          const bool suppressedForCleanPolicy =
              std::any_of(cleanMarkers.begin(), cleanMarkers.end(), [x, childWidth](const auto& marker) {
                return x >= marker.first && x < marker.first + childWidth;
              });
          if (!suppressedForCleanPolicy) {
            blendPixel(x, y, premul(0, 0, 0, alpha));
          }
        }
      }

      const std::uint32_t bar = premul(20, 23, 31, 218);
      for (int y = barY; y < barY + barHeight; ++y) {
        for (int x = barX; x < barX + barW; ++x) {
          blendPixel(x, y, bar);
        }
      }

      const auto drawChip = [&](int x, std::uint32_t color) {
        for (int y = barY + 12; y < barY + barHeight - 12; ++y) {
          for (int px = x; px < x + childWidth; ++px) {
            if (px >= barX && px < barX + barW) {
              blendPixel(px, y, color);
            }
          }
        }
      };
      drawChip(badX, premul(239, 68, 68, 96));
      for (const auto& marker : cleanMarkers) {
        drawChip(marker.first, marker.second);
      }
    }

    void fillVisualPolicyPanel(bool cleanPolicy, int bridgeRows) {
      if (data == MAP_FAILED || width <= 0 || height <= 0) {
        return;
      }

      auto* pixels = static_cast<std::uint32_t*>(data);
      std::fill(pixels, pixels + static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0x00000000u);

      const std::uint32_t bg = cleanPolicy ? premul(20, 23, 31, 218) : premul(36, 42, 56, 214);
      const std::uint32_t border = premul(255, 255, 255, 160);
      const std::uint32_t line = premul(255, 255, 255, 32);

      for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
          const bool transparentCorner = (x < 12 && y < 12) || (x >= width - 12 && y < 12);
          if (transparentCorner) {
            continue;
          }
          if (cleanPolicy && y < bridgeRows) {
            blendPixel(x, y, premul(20, 23, 31, 255));
          } else {
            blendPixel(x, y, bg);
          }
          if (!cleanPolicy && (x < 2 || y < 2 || x >= width - 2 || y >= height - 2)) {
            blendPixel(x, y, border);
          }
          if (!cleanPolicy && y < 9) {
            blendPixel(x, y, premul(239, 68, 68, 180));
          }
          if (y > 30 && y % 34 == 0 && x > 24 && x < width - 24) {
            blendPixel(x, y, line);
          }
        }
      }
    }
  };

  struct OutputInfo {
    std::uint32_t name = 0;
    wl_output* output = nullptr;
  };

  struct Client {
    wl_display* display = nullptr;
    wl_registry* registry = nullptr;
    wl_compositor* compositor = nullptr;
    wl_subcompositor* subcompositor = nullptr;
    wl_shm* shm = nullptr;
    zwlr_layer_shell_v1* layerShell = nullptr;
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
      } else if (iface == zwlr_layer_shell_v1_interface.name) {
        self->layerShell = static_cast<zwlr_layer_shell_v1*>(
            wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, std::min(version, 4u)));
      }
    }

    static void handleGlobalRemove(void* data, wl_registry* /*registry*/, std::uint32_t name) {
      auto* self = static_cast<Client*>(data);
      std::erase_if(self->outputs, [name](const OutputInfo& output) { return output.name == name; });
    }

    static constexpr wl_registry_listener kRegistryListener = {
        .global = &Client::handleGlobal,
        .global_remove = &Client::handleGlobalRemove,
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

  struct OverflowSurface {
    static constexpr int kParentWidth = 1680;
    static constexpr int kParentHeight = 98;
    static constexpr int kBarY = 16;
    static constexpr int kBarHeight = 48;
    static constexpr int kChildWidth = 340;
    static constexpr int kChildHeight = 260;
    static constexpr int kBadChildX = 52;
    static constexpr int kBadChildY = kBarY + kBarHeight - 8;
    static constexpr int kCleanChildY = kBarY + kBarHeight;
    static constexpr int kExactChildX = 448;
    static constexpr int kGuard1ChildX = 844;
    static constexpr int kGuard2ChildX = 1240;

    struct ChildPanel {
      wl_surface* surface = nullptr;
      wl_subsurface* subsurface = nullptr;
      ShmBuffer buffer;
      bool mapped = false;
      bool cleanPolicy = false;
      int bridgeRows = 0;

      ~ChildPanel() { destroy(); }

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
    };

    Client* client = nullptr;
    wl_output* output = nullptr;
    wl_surface* parentSurface = nullptr;
    zwlr_layer_surface_v1* layerSurface = nullptr;
    ShmBuffer parentBuffer;
    std::vector<std::unique_ptr<ChildPanel>> children;
    bool configured = false;
    bool closed = false;

    ~OverflowSurface() { destroy(); }

    bool start(Client& nextClient, wl_output* nextOutput) {
      client = &nextClient;
      output = nextOutput;

      parentSurface = wl_compositor_create_surface(client->compositor);
      if (parentSurface == nullptr) {
        std::cerr << "failed to create parent wl_surface\n";
        return false;
      }

      layerSurface =
          zwlr_layer_shell_v1_get_layer_surface(client->layerShell, parentSurface, output,
                                                ZWLR_LAYER_SHELL_V1_LAYER_TOP, "noctalia-subsurface-overflow-probe");
      if (layerSurface == nullptr) {
        std::cerr << "failed to create parent layer surface\n";
        return false;
      }

      zwlr_layer_surface_v1_add_listener(layerSurface, &kListener, this);
      zwlr_layer_surface_v1_set_anchor(layerSurface,
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
      zwlr_layer_surface_v1_set_size(layerSurface, kParentWidth, kParentHeight);
      zwlr_layer_surface_v1_set_exclusive_zone(layerSurface, -1);
      zwlr_layer_surface_v1_set_margin(layerSurface, 80, 0, 0, 120);
      zwlr_layer_surface_v1_set_keyboard_interactivity(layerSurface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
      wl_surface_commit(parentSurface);
      return true;
    }

    void destroy() {
      for (auto& child : children) {
        if (child != nullptr) {
          child->destroy();
        }
      }
      children.clear();
      parentBuffer.reset();
      if (layerSurface != nullptr) {
        zwlr_layer_surface_v1_destroy(layerSurface);
        layerSurface = nullptr;
      }
      if (parentSurface != nullptr) {
        wl_surface_destroy(parentSurface);
        parentSurface = nullptr;
      }
      configured = false;
    }

    [[nodiscard]] bool childrenMapped() const {
      return children.size() == 4 && std::all_of(children.begin(), children.end(),
                                                 [](const auto& child) { return child != nullptr && child->mapped; });
    }

    void mapChild(int x, int y, bool cleanPolicy, int bridgeRows) {
      if (parentSurface == nullptr || client == nullptr) {
        return;
      }

      auto child = std::make_unique<ChildPanel>();
      child->cleanPolicy = cleanPolicy;
      child->bridgeRows = bridgeRows;
      child->surface = wl_compositor_create_surface(client->compositor);
      if (child->surface == nullptr) {
        std::cerr << "failed to create child wl_surface\n";
        return;
      }

      child->subsurface = wl_subcompositor_get_subsurface(client->subcompositor, child->surface, parentSurface);
      if (child->subsurface == nullptr) {
        std::cerr << "failed to create child wl_subsurface\n";
        return;
      }

      wl_subsurface_set_position(child->subsurface, x, y);
      wl_subsurface_place_above(child->subsurface, parentSurface);
      wl_subsurface_set_desync(child->subsurface);

      if (!child->buffer.create(client->shm, kChildWidth, kChildHeight, 0x00000000)) {
        return;
      }
      child->buffer.fillVisualPolicyPanel(cleanPolicy, bridgeRows);
      wl_surface_attach(child->surface, child->buffer.buffer, 0, 0);
      wl_surface_damage(child->surface, 0, 0, kChildWidth, kChildHeight);
      wl_surface_commit(child->surface);
      wl_surface_commit(parentSurface);
      child->mapped = true;
      children.push_back(std::move(child));
    }

    void mapChildren() {
      if (childrenMapped()) {
        return;
      }
      children.clear();
      mapChild(kBadChildX, kBadChildY, false, 0);
      mapChild(kExactChildX, kCleanChildY, true, 0);
      mapChild(kGuard1ChildX, kCleanChildY - 1, true, 1);
      mapChild(kGuard2ChildX, kCleanChildY - 2, true, 2);
    }

    static void handleConfigure(void* data, zwlr_layer_surface_v1* layerSurface, std::uint32_t serial,
                                std::uint32_t width, std::uint32_t height) {
      auto* self = static_cast<OverflowSurface*>(data);
      zwlr_layer_surface_v1_ack_configure(layerSurface, serial);

      const int parentWidth = static_cast<int>(width == 0 ? kParentWidth : width);
      const int parentHeight = static_cast<int>(height == 0 ? kParentHeight : height);
      if (self->client == nullptr ||
          !self->parentBuffer.create(self->client->shm, parentWidth, parentHeight, 0x00000000)) {
        return;
      }
      const std::vector<std::pair<int, std::uint32_t>> cleanMarkers{
          {kExactChildX, ShmBuffer::premul(34, 197, 94, 64)},
          {kGuard1ChildX, ShmBuffer::premul(14, 165, 233, 64)},
          {kGuard2ChildX, ShmBuffer::premul(168, 85, 247, 64)},
      };
      self->parentBuffer.fillVisualPolicyParent(kBarY, kBarHeight, kBadChildX, cleanMarkers, kChildWidth);
      wl_surface_attach(self->parentSurface, self->parentBuffer.buffer, 0, 0);
      wl_surface_damage(self->parentSurface, 0, 0, parentWidth, parentHeight);
      wl_surface_commit(self->parentSurface);
      self->configured = true;
      self->mapChildren();
    }

    static void handleClosed(void* data, zwlr_layer_surface_v1* /*layerSurface*/) {
      auto* self = static_cast<OverflowSurface*>(data);
      self->closed = true;
    }

    static constexpr zwlr_layer_surface_v1_listener kListener = {
        .configure = &OverflowSurface::handleConfigure,
        .closed = &OverflowSurface::handleClosed,
    };
  };

} // namespace

int main() {
  std::signal(SIGINT, handleSignal);
  std::signal(SIGTERM, handleSignal);

  Client client;
  if (!client.connect()) {
    return 1;
  }
  if (client.compositor == nullptr || client.subcompositor == nullptr || client.shm == nullptr ||
      client.layerShell == nullptr) {
    std::cerr << "missing required Wayland globals: compositor=" << (client.compositor != nullptr)
              << " subcompositor=" << (client.subcompositor != nullptr) << " shm=" << (client.shm != nullptr)
              << " layer-shell=" << (client.layerShell != nullptr) << "\n";
    return 1;
  }
  if (client.outputs.empty()) {
    std::cerr << "no Wayland outputs advertised\n";
    return 1;
  }

  std::vector<std::unique_ptr<OverflowSurface>> surfaces;
  surfaces.reserve(client.outputs.size());
  for (const auto& output : client.outputs) {
    auto surface = std::make_unique<OverflowSurface>();
    if (!surface->start(client, output.output)) {
      return 1;
    }
    surfaces.push_back(std::move(surface));
  }
  wl_display_flush(client.display);

  const auto allMapped = [&surfaces]() {
    return std::all_of(surfaces.begin(), surfaces.end(), [](const auto& surface) {
      return surface != nullptr && (surface->childrenMapped() || surface->closed);
    });
  };
  std::cout << "created " << surfaces.size()
            << " visual-policy parent strip(s); waiting for attached panel subsurfaces...\n";
  if (!dispatchUntil(client, allMapped, std::chrono::seconds(3))) {
    if (client.hasDisplayError()) {
      client.reportDisplayError("subsurface overflow probe failed");
    } else {
      std::cerr << "timed out waiting for attached panel subsurfaces to map\n";
    }
    return 1;
  }

  const std::size_t mapped =
      static_cast<std::size_t>(std::count_if(surfaces.begin(), surfaces.end(), [](const auto& surface) {
        return surface != nullptr && surface->childrenMapped() && !surface->closed;
      }));
  std::cout << "mapped " << mapped
            << " visual mockup(s); left is intentional overlap/shadow, right is flush with shadow suppressed.\n";
  std::cout << "holding for visual inspection...\n";

  const bool closed = dispatchUntil(
      client,
      [&client, &surfaces]() {
        return client.hasDisplayError() || std::any_of(surfaces.begin(), surfaces.end(), [](const auto& surface) {
                 return surface == nullptr || surface->closed;
               });
      },
      std::chrono::seconds(12));
  if (closed) {
    if (client.hasDisplayError()) {
      client.reportDisplayError("subsurface overflow probe failed during hold");
    } else {
      std::cerr << "compositor closed at least one parent layer surface during hold\n";
    }
    return 1;
  }

  std::cout << "result: attached panel wl_subsurfaces stayed alive for visual inspection\n";
  return 0;
}
