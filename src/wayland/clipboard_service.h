#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

struct wl_registry;
struct wl_seat;

struct ClipboardEntry {
  std::vector<std::string> mimeTypes;
  std::vector<std::uint8_t> data;
  std::string textPreview;
  std::chrono::steady_clock::time_point timestamp;

  [[nodiscard]] bool isImage() const;
};

struct DataControlOps {
  const char* managerInterfaceName = nullptr;

  void* (*bindManager)(wl_registry* registry, std::uint32_t name, std::uint32_t version) = nullptr;
  void (*destroyManager)(void* manager) = nullptr;

  void* (*getDataDevice)(void* manager, wl_seat* seat) = nullptr;
  void (*destroyDevice)(void* device) = nullptr;
  int (*addDeviceListener)(void* device, const void* listener, void* data) = nullptr;

  void* (*createDataSource)(void* manager) = nullptr;
  void (*destroySource)(void* source) = nullptr;
  int (*addSourceListener)(void* source, const void* listener, void* data) = nullptr;
  void (*sourceOffer)(void* source, const char* mimeType) = nullptr;

  void (*deviceSetSelection)(void* device, void* source) = nullptr;

  void (*destroyOffer)(void* offer) = nullptr;
  int (*addOfferListener)(void* offer, const void* listener, void* data) = nullptr;
  void (*offerReceive)(void* offer, const char* mimeType, int fd) = nullptr;
};

[[nodiscard]] const DataControlOps* extDataControlOps();
[[nodiscard]] const DataControlOps* wlrDataControlOps();

class ClipboardService {
public:
  using ChangeCallback = std::function<void()>;

  ClipboardService();
  ~ClipboardService();

  ClipboardService(const ClipboardService&) = delete;
  ClipboardService& operator=(const ClipboardService&) = delete;

  bool bind(void* manager, const DataControlOps* ops, wl_seat* seat);
  void cleanup();

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] int activeReadFd() const noexcept;
  [[nodiscard]] const std::deque<ClipboardEntry>& history() const noexcept;

  bool copyText(std::string text);
  void setChangeCallback(ChangeCallback callback);
  void dispatchReadEvents(short revents);

  // Protocol callback entrypoints used by the generated listeners.
  void handleDataOffer(void* offer);
  void handleOfferMimeType(void* offer, const char* mimeType);
  void handleSelection(void* offer);
  void handlePrimarySelection(void* offer);
  void handleDeviceFinished();
  void handleSourceSend(void* source, const char* mimeType, int fd);
  void handleSourceCancelled(void* source);

private:
  struct OfferState {
    void* offer = nullptr;
    std::vector<std::string> mimeTypes;
  };

  struct ActiveRead {
    int fd = -1;
    void* offer = nullptr;
    std::string mimeType;
    std::vector<std::uint8_t> buffer;
    std::vector<std::string> offeredMimeTypes;
  };

  struct OutgoingSource {
    void* source = nullptr;
    std::string text;
  };

  [[nodiscard]] const OfferState* findOffer(void* offer) const;
  OfferState* findOffer(void* offer);
  void destroyOffer(void* offer);
  void clearOffers();
  void cancelActiveRead();
  bool startReceive(void* offer);
  void finishRead(bool discard);
  void addToHistory(ClipboardEntry entry);
  [[nodiscard]] std::string chooseMimeType(const OfferState& offer) const;
  [[nodiscard]] static bool isTextMimeType(std::string_view mimeType);
  [[nodiscard]] static std::string buildTextPreview(const std::vector<std::uint8_t>& data);
  void notifyChanged() const;

  void* m_manager = nullptr;
  const DataControlOps* m_ops = nullptr;
  wl_seat* m_seat = nullptr;
  void* m_device = nullptr;

  std::vector<OfferState> m_offers;
  void* m_selectionOffer = nullptr;
  ActiveRead m_activeRead;
  std::vector<OutgoingSource> m_outgoingSources;

  std::deque<ClipboardEntry> m_history;
  std::size_t m_historyBytes = 0;
  ChangeCallback m_changeCallback;
};
