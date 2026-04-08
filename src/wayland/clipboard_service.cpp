#include "wayland/clipboard_service.h"

#include "core/log.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <json.hpp>
#include <poll.h>
#include <ranges>
#include <sstream>
#include <string_view>
#include <unistd.h>
#include <unordered_set>

#include <wayland-client-core.h>
#include <wayland-client.h>

#include "ext-data-control-v1-client-protocol.h"
#include "wlr-data-control-unstable-v1-client-protocol.h"

namespace {

  constexpr std::size_t kMaxHistoryEntries = 50;
  constexpr std::size_t kMaxHistoryBytes = 64u * 1024u * 1024u;
  constexpr std::size_t kMaxEntryBytes = 10u * 1024u * 1024u;
  constexpr std::size_t kPreviewBytes = 200;

  constexpr std::array kTextMimeTypes = {
      std::string_view{"text/plain;charset=utf-8"},
      std::string_view{"text/plain"},
      std::string_view{"UTF8_STRING"},
  };

  constexpr std::array kImageMimeTypes = {
      std::string_view{"image/png"},
      std::string_view{"image/jpeg"},
  };

  constexpr Logger kLog("clipboard");
  std::uint64_t gStorageCounter = 0;

  void closeFd(int& fd) {
    if (fd >= 0) {
      close(fd);
      fd = -1;
    }
  }

  void* bindExtManager(wl_registry* registry, std::uint32_t name, std::uint32_t version) {
    const auto bindVersion = std::min(version, 1u);
    return wl_registry_bind(registry, name, &ext_data_control_manager_v1_interface, bindVersion);
  }

  void destroyExtManager(void* manager) {
    ext_data_control_manager_v1_destroy(static_cast<ext_data_control_manager_v1*>(manager));
  }

  void* getExtDataDevice(void* manager, wl_seat* seat) {
    return ext_data_control_manager_v1_get_data_device(static_cast<ext_data_control_manager_v1*>(manager), seat);
  }

  void destroyExtDevice(void* device) {
    ext_data_control_device_v1_destroy(static_cast<ext_data_control_device_v1*>(device));
  }

  int addExtDeviceListener(void* device, const void* listener, void* data) {
    return ext_data_control_device_v1_add_listener(static_cast<ext_data_control_device_v1*>(device),
                                                   static_cast<const ext_data_control_device_v1_listener*>(listener),
                                                   data);
  }

  void* createExtDataSource(void* manager) {
    return ext_data_control_manager_v1_create_data_source(static_cast<ext_data_control_manager_v1*>(manager));
  }

  void destroyExtSource(void* source) {
    ext_data_control_source_v1_destroy(static_cast<ext_data_control_source_v1*>(source));
  }

  int addExtSourceListener(void* source, const void* listener, void* data) {
    return ext_data_control_source_v1_add_listener(static_cast<ext_data_control_source_v1*>(source),
                                                   static_cast<const ext_data_control_source_v1_listener*>(listener),
                                                   data);
  }

  void extSourceOffer(void* source, const char* mimeType) {
    ext_data_control_source_v1_offer(static_cast<ext_data_control_source_v1*>(source), mimeType);
  }

  void extDeviceSetSelection(void* device, void* source) {
    ext_data_control_device_v1_set_selection(static_cast<ext_data_control_device_v1*>(device),
                                             static_cast<ext_data_control_source_v1*>(source));
  }

  void destroyExtOffer(void* offer) {
    ext_data_control_offer_v1_destroy(static_cast<ext_data_control_offer_v1*>(offer));
  }

  int addExtOfferListener(void* offer, const void* listener, void* data) {
    return ext_data_control_offer_v1_add_listener(static_cast<ext_data_control_offer_v1*>(offer),
                                                  static_cast<const ext_data_control_offer_v1_listener*>(listener),
                                                  data);
  }

  void extOfferReceive(void* offer, const char* mimeType, int fd) {
    ext_data_control_offer_v1_receive(static_cast<ext_data_control_offer_v1*>(offer), mimeType, fd);
  }

  void* bindWlrManager(wl_registry* registry, std::uint32_t name, std::uint32_t version) {
    const auto bindVersion = std::min(version, 2u);
    return wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface, bindVersion);
  }

  void destroyWlrManager(void* manager) {
    zwlr_data_control_manager_v1_destroy(static_cast<zwlr_data_control_manager_v1*>(manager));
  }

  void* getWlrDataDevice(void* manager, wl_seat* seat) {
    return zwlr_data_control_manager_v1_get_data_device(static_cast<zwlr_data_control_manager_v1*>(manager), seat);
  }

  void destroyWlrDevice(void* device) {
    zwlr_data_control_device_v1_destroy(static_cast<zwlr_data_control_device_v1*>(device));
  }

  int addWlrDeviceListener(void* device, const void* listener, void* data) {
    return zwlr_data_control_device_v1_add_listener(static_cast<zwlr_data_control_device_v1*>(device),
                                                    static_cast<const zwlr_data_control_device_v1_listener*>(listener),
                                                    data);
  }

  void* createWlrDataSource(void* manager) {
    return zwlr_data_control_manager_v1_create_data_source(static_cast<zwlr_data_control_manager_v1*>(manager));
  }

  void destroyWlrSource(void* source) {
    zwlr_data_control_source_v1_destroy(static_cast<zwlr_data_control_source_v1*>(source));
  }

  int addWlrSourceListener(void* source, const void* listener, void* data) {
    return zwlr_data_control_source_v1_add_listener(static_cast<zwlr_data_control_source_v1*>(source),
                                                    static_cast<const zwlr_data_control_source_v1_listener*>(listener),
                                                    data);
  }

  void wlrSourceOffer(void* source, const char* mimeType) {
    zwlr_data_control_source_v1_offer(static_cast<zwlr_data_control_source_v1*>(source), mimeType);
  }

  void wlrDeviceSetSelection(void* device, void* source) {
    zwlr_data_control_device_v1_set_selection(static_cast<zwlr_data_control_device_v1*>(device),
                                              static_cast<zwlr_data_control_source_v1*>(source));
  }

  void destroyWlrOffer(void* offer) {
    zwlr_data_control_offer_v1_destroy(static_cast<zwlr_data_control_offer_v1*>(offer));
  }

  int addWlrOfferListener(void* offer, const void* listener, void* data) {
    return zwlr_data_control_offer_v1_add_listener(static_cast<zwlr_data_control_offer_v1*>(offer),
                                                   static_cast<const zwlr_data_control_offer_v1_listener*>(listener),
                                                   data);
  }

  void wlrOfferReceive(void* offer, const char* mimeType, int fd) {
    zwlr_data_control_offer_v1_receive(static_cast<zwlr_data_control_offer_v1*>(offer), mimeType, fd);
  }

  const DataControlOps kExtDataControlOps = {
      .managerInterfaceName = ext_data_control_manager_v1_interface.name,
      .bindManager = &bindExtManager,
      .destroyManager = &destroyExtManager,
      .getDataDevice = &getExtDataDevice,
      .destroyDevice = &destroyExtDevice,
      .addDeviceListener = &addExtDeviceListener,
      .createDataSource = &createExtDataSource,
      .destroySource = &destroyExtSource,
      .addSourceListener = &addExtSourceListener,
      .sourceOffer = &extSourceOffer,
      .deviceSetSelection = &extDeviceSetSelection,
      .destroyOffer = &destroyExtOffer,
      .addOfferListener = &addExtOfferListener,
      .offerReceive = &extOfferReceive,
  };

  const DataControlOps kWlrDataControlOps = {
      .managerInterfaceName = zwlr_data_control_manager_v1_interface.name,
      .bindManager = &bindWlrManager,
      .destroyManager = &destroyWlrManager,
      .getDataDevice = &getWlrDataDevice,
      .destroyDevice = &destroyWlrDevice,
      .addDeviceListener = &addWlrDeviceListener,
      .createDataSource = &createWlrDataSource,
      .destroySource = &destroyWlrSource,
      .addSourceListener = &addWlrSourceListener,
      .sourceOffer = &wlrSourceOffer,
      .deviceSetSelection = &wlrDeviceSetSelection,
      .destroyOffer = &destroyWlrOffer,
      .addOfferListener = &addWlrOfferListener,
      .offerReceive = &wlrOfferReceive,
  };

  void handleExtDataOffer(void* data, ext_data_control_device_v1* /*device*/, ext_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handleDataOffer(offer);
  }

  void handleExtSelection(void* data, ext_data_control_device_v1* /*device*/, ext_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handleSelection(offer);
  }

  void handleExtFinished(void* data, ext_data_control_device_v1* /*device*/) {
    static_cast<ClipboardService*>(data)->handleDeviceFinished();
  }

  void handleExtPrimarySelection(void* data, ext_data_control_device_v1* /*device*/, ext_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handlePrimarySelection(offer);
  }

  const ext_data_control_device_v1_listener kExtDeviceListener = {
      .data_offer = &handleExtDataOffer,
      .selection = &handleExtSelection,
      .finished = &handleExtFinished,
      .primary_selection = &handleExtPrimarySelection,
  };

  void handleExtOfferMimeType(void* data, ext_data_control_offer_v1* offer, const char* mimeType) {
    static_cast<ClipboardService*>(data)->handleOfferMimeType(offer, mimeType);
  }

  const ext_data_control_offer_v1_listener kExtOfferListener = {
      .offer = &handleExtOfferMimeType,
  };

  void handleExtSourceSend(void* data, ext_data_control_source_v1* source, const char* mimeType, int fd) {
    static_cast<ClipboardService*>(data)->handleSourceSend(source, mimeType, fd);
  }

  void handleExtSourceCancelled(void* data, ext_data_control_source_v1* source) {
    static_cast<ClipboardService*>(data)->handleSourceCancelled(source);
  }

  const ext_data_control_source_v1_listener kExtSourceListener = {
      .send = &handleExtSourceSend,
      .cancelled = &handleExtSourceCancelled,
  };

  void handleWlrDataOffer(void* data, zwlr_data_control_device_v1* /*device*/, zwlr_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handleDataOffer(offer);
  }

  void handleWlrSelection(void* data, zwlr_data_control_device_v1* /*device*/, zwlr_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handleSelection(offer);
  }

  void handleWlrFinished(void* data, zwlr_data_control_device_v1* /*device*/) {
    static_cast<ClipboardService*>(data)->handleDeviceFinished();
  }

  void handleWlrPrimarySelection(void* data, zwlr_data_control_device_v1* /*device*/,
                                 zwlr_data_control_offer_v1* offer) {
    static_cast<ClipboardService*>(data)->handlePrimarySelection(offer);
  }

  const zwlr_data_control_device_v1_listener kWlrDeviceListener = {
      .data_offer = &handleWlrDataOffer,
      .selection = &handleWlrSelection,
      .finished = &handleWlrFinished,
      .primary_selection = &handleWlrPrimarySelection,
  };

  void handleWlrOfferMimeType(void* data, zwlr_data_control_offer_v1* offer, const char* mimeType) {
    static_cast<ClipboardService*>(data)->handleOfferMimeType(offer, mimeType);
  }

  const zwlr_data_control_offer_v1_listener kWlrOfferListener = {
      .offer = &handleWlrOfferMimeType,
  };

  void handleWlrSourceSend(void* data, zwlr_data_control_source_v1* source, const char* mimeType, int fd) {
    static_cast<ClipboardService*>(data)->handleSourceSend(source, mimeType, fd);
  }

  void handleWlrSourceCancelled(void* data, zwlr_data_control_source_v1* source) {
    static_cast<ClipboardService*>(data)->handleSourceCancelled(source);
  }

  const zwlr_data_control_source_v1_listener kWlrSourceListener = {
      .send = &handleWlrSourceSend,
      .cancelled = &handleWlrSourceCancelled,
  };

  const void* deviceListenerFor(const DataControlOps& ops) {
    return &ops == &kExtDataControlOps ? static_cast<const void*>(&kExtDeviceListener)
                                       : static_cast<const void*>(&kWlrDeviceListener);
  }

  const void* offerListenerFor(const DataControlOps& ops) {
    return &ops == &kExtDataControlOps ? static_cast<const void*>(&kExtOfferListener)
                                       : static_cast<const void*>(&kWlrOfferListener);
  }

  const void* sourceListenerFor(const DataControlOps& ops) {
    return &ops == &kExtDataControlOps ? static_cast<const void*>(&kExtSourceListener)
                                       : static_cast<const void*>(&kWlrSourceListener);
  }

} // namespace

ClipboardService::ClipboardService() { loadPersistedHistory(); }
ClipboardService::~ClipboardService() { cleanup(); }

const DataControlOps* extDataControlOps() { return &kExtDataControlOps; }

const DataControlOps* wlrDataControlOps() { return &kWlrDataControlOps; }

bool ClipboardEntry::isImage() const {
  return std::ranges::any_of(mimeTypes, [](const std::string& mimeType) { return mimeType.rfind("image/", 0) == 0; });
}

bool ClipboardService::bind(void* manager, const DataControlOps* ops, wl_seat* seat) {
  if (manager == nullptr || ops == nullptr || seat == nullptr) {
    cleanup();
    return false;
  }

  if (m_manager == manager && m_ops == ops && m_seat == seat && m_device != nullptr) {
    return true;
  }

  cleanup();

  m_manager = manager;
  m_ops = ops;
  m_seat = seat;
  m_device = m_ops->getDataDevice(m_manager, m_seat);
  if (m_device == nullptr) {
    kLog.warn("failed to create data control device");
    return false;
  }

  if (m_ops->addDeviceListener(m_device, deviceListenerFor(*m_ops), this) != 0) {
    kLog.warn("failed to attach clipboard device listener");
    cleanup();
    return false;
  }

  kLog.info("clipboard service bound via {}", m_ops->managerInterfaceName);
  return true;
}

void ClipboardService::cleanup() {
  cancelActiveRead();
  clearOffers();

  if (m_ops != nullptr) {
    for (auto& outgoing : m_outgoingSources) {
      if (outgoing.source != nullptr) {
        m_ops->destroySource(outgoing.source);
      }
    }
  }
  m_outgoingSources.clear();

  if (m_device != nullptr && m_ops != nullptr) {
    m_ops->destroyDevice(m_device);
  }

  m_device = nullptr;
  m_selectionOffer = nullptr;
  m_seat = nullptr;
  m_ops = nullptr;
  m_manager = nullptr;
}

bool ClipboardService::isAvailable() const noexcept { return m_device != nullptr; }

int ClipboardService::activeReadFd() const noexcept { return m_activeRead.fd; }

const std::deque<ClipboardEntry>& ClipboardService::history() const noexcept { return m_history; }

std::uint64_t ClipboardService::changeSerial() const noexcept { return m_changeSerial; }

bool ClipboardService::ensureEntryLoaded(std::size_t index) {
  if (index >= m_history.size()) {
    return false;
  }
  return loadEntryPayload(m_history[index]);
}

bool ClipboardService::copyText(std::string text) {
  std::vector<std::uint8_t> data(text.begin(), text.end());
  return copyData({"text/plain;charset=utf-8", "text/plain"}, std::move(data));
}

bool ClipboardService::copyEntry(const ClipboardEntry& entry) {
  if (entry.data.empty() || entry.dataMimeType.empty()) {
    return false;
  }

  std::vector<std::string> mimeTypes;
  mimeTypes.push_back(entry.dataMimeType);
  if (isTextMimeType(entry.dataMimeType)) {
    if (std::ranges::find(mimeTypes, std::string("text/plain;charset=utf-8")) == mimeTypes.end()) {
      mimeTypes.push_back("text/plain;charset=utf-8");
    }
    if (std::ranges::find(mimeTypes, std::string("text/plain")) == mimeTypes.end()) {
      mimeTypes.push_back("text/plain");
    }
  }
  return copyData(std::move(mimeTypes), entry.data);
}

bool ClipboardService::promoteEntry(std::size_t index) {
  if (index >= m_history.size()) {
    return false;
  }
  if (index == 0) {
    return true;
  }

  ClipboardEntry entry = std::move(m_history[index]);
  m_history.erase(m_history.begin() + static_cast<std::ptrdiff_t>(index));
  entry.capturedAt = std::chrono::system_clock::now();
  entry.timestamp = std::chrono::steady_clock::now();
  m_history.push_front(std::move(entry));
  ++m_changeSerial;
  persistHistory();
  notifyChanged();
  return true;
}

bool ClipboardService::copyData(std::vector<std::string> mimeTypes, std::vector<std::uint8_t> data) {
  if (m_device == nullptr || m_ops == nullptr) {
    return false;
  }
  if (mimeTypes.empty() || data.empty()) {
    return false;
  }

  void* source = m_ops->createDataSource(m_manager);
  if (source == nullptr) {
    return false;
  }

  if (m_ops->addSourceListener(source, sourceListenerFor(*m_ops), this) != 0) {
    m_ops->destroySource(source);
    return false;
  }

  for (const auto& mimeType : mimeTypes) {
    m_ops->sourceOffer(source, mimeType.c_str());
  }
  m_outgoingSources.push_back(OutgoingSource{
      .source = source,
      .mimeTypes = std::move(mimeTypes),
      .data = std::move(data),
  });
  m_ops->deviceSetSelection(m_device, source);
  return true;
}

void ClipboardService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void ClipboardService::dispatchReadEvents(short revents) {
  if (m_activeRead.fd < 0) {
    return;
  }

  if ((revents & POLLERR) != 0) {
    finishRead(true);
    return;
  }

  std::array<std::uint8_t, 16384> buffer{};
  for (;;) {
    const ssize_t bytesRead = read(m_activeRead.fd, buffer.data(), buffer.size());
    if (bytesRead > 0) {
      const auto nextSize = m_activeRead.buffer.size() + static_cast<std::size_t>(bytesRead);
      if (nextSize > kMaxEntryBytes) {
        kLog.warn("discarding oversized clipboard entry");
        finishRead(true);
        return;
      }
      m_activeRead.buffer.insert(m_activeRead.buffer.end(), buffer.begin(), buffer.begin() + bytesRead);
      continue;
    }

    if (bytesRead == 0) {
      finishRead(false);
      return;
    }

    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      break;
    }

    finishRead(true);
    return;
  }

  if ((revents & POLLHUP) != 0) {
    finishRead(false);
  }
}

void ClipboardService::handleDataOffer(void* offer) {
  if (offer == nullptr || m_ops == nullptr) {
    return;
  }

  m_offers.push_back(OfferState{
      .offer = offer,
      .mimeTypes = {},
  });
  if (m_ops->addOfferListener(offer, offerListenerFor(*m_ops), this) != 0) {
    kLog.warn("failed to attach clipboard offer listener");
  }
}

void ClipboardService::handleOfferMimeType(void* offer, const char* mimeType) {
  auto* state = findOffer(offer);
  if (state == nullptr || mimeType == nullptr) {
    return;
  }
  state->mimeTypes.emplace_back(mimeType);
}

void ClipboardService::handleSelection(void* offer) {
  cancelActiveRead();
  destroyOffer(m_selectionOffer);
  m_selectionOffer = offer;

  if (offer == nullptr) {
    return;
  }

  if (!startReceive(offer)) {
    kLog.debug("selection offer has no supported MIME types");
  }
}

void ClipboardService::handlePrimarySelection(void* offer) { destroyOffer(offer); }

void ClipboardService::handleDeviceFinished() { cleanup(); }

void ClipboardService::handleSourceSend(void* source, const char* mimeType, int fd) {
  const auto it = std::ranges::find(m_outgoingSources, source, &OutgoingSource::source);
  if (it != m_outgoingSources.end() && mimeType != nullptr) {
    const auto mimeIt = std::ranges::find(it->mimeTypes, std::string_view(mimeType));
    if (mimeIt != it->mimeTypes.end()) {
      const auto* bytes = reinterpret_cast<const char*>(it->data.data());
      std::size_t remaining = it->data.size();
      while (remaining > 0) {
        const ssize_t written = write(fd, bytes, remaining);
        if (written < 0) {
          if (errno == EINTR) {
            continue;
          }
          break;
        }
        bytes += written;
        remaining -= static_cast<std::size_t>(written);
      }
    }
  }
  close(fd);
}

void ClipboardService::handleSourceCancelled(void* source) {
  const auto it = std::ranges::find(m_outgoingSources, source, &OutgoingSource::source);
  if (it == m_outgoingSources.end()) {
    return;
  }

  if (m_ops != nullptr && it->source != nullptr) {
    m_ops->destroySource(it->source);
  }
  m_outgoingSources.erase(it);
}

const ClipboardService::OfferState* ClipboardService::findOffer(void* offer) const {
  const auto it = std::ranges::find(m_offers, offer, &OfferState::offer);
  return it != m_offers.end() ? &*it : nullptr;
}

ClipboardService::OfferState* ClipboardService::findOffer(void* offer) {
  const auto it = std::ranges::find(m_offers, offer, &OfferState::offer);
  return it != m_offers.end() ? &*it : nullptr;
}

void ClipboardService::destroyOffer(void* offer) {
  if (offer == nullptr || m_ops == nullptr) {
    return;
  }

  const auto it = std::ranges::find(m_offers, offer, &OfferState::offer);
  if (it == m_offers.end()) {
    return;
  }

  m_ops->destroyOffer(offer);
  m_offers.erase(it);
}

void ClipboardService::clearOffers() {
  if (m_ops != nullptr) {
    for (auto& offer : m_offers) {
      if (offer.offer != nullptr) {
        m_ops->destroyOffer(offer.offer);
      }
    }
  }
  m_offers.clear();
}

void ClipboardService::cancelActiveRead() {
  closeFd(m_activeRead.fd);
  m_activeRead.buffer.clear();
  m_activeRead.mimeType.clear();
  m_activeRead.offeredMimeTypes.clear();
  m_activeRead.offer = nullptr;
}

bool ClipboardService::startReceive(void* offer) {
  if (m_ops == nullptr) {
    return false;
  }

  const OfferState* state = findOffer(offer);
  if (state == nullptr) {
    return false;
  }

  const std::string mimeType = chooseMimeType(*state);
  if (mimeType.empty()) {
    return false;
  }

  int pipeFds[2] = {-1, -1};
  if (pipe2(pipeFds, O_CLOEXEC | O_NONBLOCK) != 0) {
    return false;
  }

  m_ops->offerReceive(offer, mimeType.c_str(), pipeFds[1]);
  close(pipeFds[1]);

  m_activeRead.fd = pipeFds[0];
  m_activeRead.offer = offer;
  m_activeRead.mimeType = mimeType;
  m_activeRead.buffer.clear();
  m_activeRead.offeredMimeTypes = state->mimeTypes;
  return true;
}

void ClipboardService::finishRead(bool discard) {
  const bool shouldStore = !discard && !m_activeRead.buffer.empty();
  const std::string mimeType = m_activeRead.mimeType;
  auto mimeTypes = std::move(m_activeRead.offeredMimeTypes);
  auto data = std::move(m_activeRead.buffer);
  const void* offer = m_activeRead.offer;

  cancelActiveRead();

  if (offer == m_selectionOffer) {
    destroyOffer(m_selectionOffer);
    m_selectionOffer = nullptr;
  }

  if (!shouldStore) {
    return;
  }

  ClipboardEntry entry;
  entry.storageId = generateStorageId();
  entry.mimeTypes = std::move(mimeTypes);
  if (std::ranges::find(entry.mimeTypes, mimeType) == entry.mimeTypes.end()) {
    entry.mimeTypes.push_back(mimeType);
  }
  entry.dataMimeType = mimeType;
  entry.data = std::move(data);
  entry.byteSize = entry.data.size();
  entry.payloadLoaded = true;
  entry.payloadPath = payloadPathForId(entry.storageId);
  entry.capturedAt = std::chrono::system_clock::now();
  entry.timestamp = std::chrono::steady_clock::now();
  if (isTextMimeType(mimeType)) {
    entry.textPreview = buildTextPreview(entry.data);
  }

  addToHistory(std::move(entry));
}

void ClipboardService::addToHistory(ClipboardEntry entry) {
  if (entry.byteSize == 0) {
    entry.byteSize = entry.data.size();
  }

  if (entry.byteSize == 0) {
    return;
  }

  if (!entry.data.empty() && isTextMimeType(entry.dataMimeType) && isEmptyTextPayload(entry.data)) {
    return;
  }

  if (entry.storageId.empty()) {
    entry.storageId = generateStorageId();
  }
  if (entry.payloadPath.empty()) {
    entry.payloadPath = payloadPathForId(entry.storageId);
  }

  if (entry.textPreview.empty() && !entry.data.empty() && isTextMimeType(entry.dataMimeType)) {
    entry.textPreview = buildTextPreview(entry.data);
  }

  if (!m_history.empty() && !entry.data.empty()) {
    const ClipboardEntry& current = m_history.front();
    const bool samePayload = current.data == entry.data;
    const bool sameMime = current.dataMimeType == entry.dataMimeType;
    const bool equivalentText = isTextMimeType(current.dataMimeType) && isTextMimeType(entry.dataMimeType);
    if (samePayload && (sameMime || equivalentText)) {
      return;
    }
  }

  const std::size_t entryBytes = entry.byteSize;
  if (entryBytes > kMaxEntryBytes) {
    return;
  }

  m_history.push_front(std::move(entry));
  m_historyBytes += entryBytes;
  trimHistoryToBudget();

  ++m_changeSerial;
  persistHistory();
  const std::string latestMime = m_history.front().mimeTypes.empty() ? "" : m_history.front().mimeTypes.front();
  kLog.debug("clipboard history size={} entries={} latest_mime={}", m_historyBytes, m_history.size(), latestMime);
  notifyChanged();
}

void ClipboardService::loadPersistedHistory() {
  namespace fs = std::filesystem;

  m_history.clear();
  m_historyBytes = 0;

  const fs::path path(manifestPath());
  if (!fs::exists(path)) {
    return;
  }

  std::ifstream file(path);
  if (!file.is_open()) {
    return;
  }

  try {
    nlohmann::json json;
    file >> json;
    if (!json.is_object() || !json["entries"].is_array()) {
      return;
    }

    for (const auto& item : json["entries"]) {
      ClipboardEntry entry;
      entry.storageId = item.value("id", "");
      entry.payloadPath = item.value("payload_path", payloadPathForId(entry.storageId));
      entry.mimeTypes = item.value("mime_types", std::vector<std::string>{});
      entry.dataMimeType = item.value("data_mime_type", "");
      entry.textPreview = item.value("text_preview", "");
      entry.byteSize = item.value("byte_size", static_cast<std::size_t>(0));
      entry.payloadLoaded = false;

      const auto capturedAtMs = item.value("captured_at_ms", std::int64_t{0});
      entry.capturedAt = std::chrono::system_clock::time_point(std::chrono::milliseconds(capturedAtMs));

      if (entry.storageId.empty() || entry.dataMimeType.empty() || entry.byteSize == 0) {
        continue;
      }

      m_history.push_back(std::move(entry));
      m_historyBytes += m_history.back().byteSize;
    }

    trimHistoryToBudget();
    kLog.info("loaded {} persisted clipboard entries", m_history.size());
  } catch (const std::exception& e) {
    kLog.warn("failed to load clipboard history: {}", e.what());
    m_history.clear();
    m_historyBytes = 0;
  }
}

void ClipboardService::persistHistory() {
  namespace fs = std::filesystem;

  try {
    fs::create_directories(entriesDirectory());

    nlohmann::json entries = nlohmann::json::array();
    std::unordered_set<std::string> activePayloadPaths;
    activePayloadPaths.reserve(m_history.size());

    for (auto& entry : m_history) {
      if (entry.storageId.empty()) {
        entry.storageId = generateStorageId();
      }
      if (entry.payloadPath.empty()) {
        entry.payloadPath = payloadPathForId(entry.storageId);
      }

      activePayloadPaths.insert(entry.payloadPath);
      if (entry.payloadLoaded && !entry.data.empty()) {
        std::ofstream payload(entry.payloadPath, std::ios::binary | std::ios::trunc);
        payload.write(reinterpret_cast<const char*>(entry.data.data()),
                      static_cast<std::streamsize>(entry.data.size()));
      }

      const auto capturedAtMs =
          std::chrono::duration_cast<std::chrono::milliseconds>(entry.capturedAt.time_since_epoch()).count();
      entries.push_back({
          {"id", entry.storageId},
          {"payload_path", entry.payloadPath},
          {"mime_types", entry.mimeTypes},
          {"data_mime_type", entry.dataMimeType},
          {"text_preview", entry.textPreview},
          {"byte_size", entry.byteSize},
          {"captured_at_ms", capturedAtMs},
      });
    }

    const fs::path manifest(manifestPath());
    fs::create_directories(manifest.parent_path());
    const fs::path tmp = manifest;
    const fs::path tmpPath = tmp.string() + ".tmp";
    {
      std::ofstream out(tmpPath);
      out << nlohmann::json{{"entries", entries}}.dump(2);
      out.flush();
    }
    fs::rename(tmpPath, manifest);

    const fs::path entriesDir(entriesDirectory());
    if (fs::exists(entriesDir)) {
      for (const auto& dirEntry : fs::directory_iterator(entriesDir)) {
        const auto filePath = dirEntry.path().string();
        if (!activePayloadPaths.contains(filePath)) {
          fs::remove(dirEntry.path());
        }
      }
    }
  } catch (const std::exception& e) {
    kLog.warn("failed to persist clipboard history: {}", e.what());
  }
}

void ClipboardService::trimHistoryToBudget() {
  while (m_history.size() > kMaxHistoryEntries || m_historyBytes > kMaxHistoryBytes) {
    m_historyBytes -= m_history.back().byteSize;
    m_history.pop_back();
  }
}

bool ClipboardService::loadEntryPayload(ClipboardEntry& entry) {
  if (entry.payloadLoaded) {
    return !entry.data.empty();
  }
  if (entry.payloadPath.empty()) {
    entry.payloadPath = payloadPathForId(entry.storageId);
  }

  std::ifstream file(entry.payloadPath, std::ios::binary | std::ios::ate);
  if (!file.is_open()) {
    return false;
  }

  const auto size = file.tellg();
  if (size <= 0) {
    return false;
  }

  entry.data.resize(static_cast<std::size_t>(size));
  file.seekg(0);
  file.read(reinterpret_cast<char*>(entry.data.data()), size);
  entry.payloadLoaded = true;
  if (entry.byteSize == 0) {
    entry.byteSize = entry.data.size();
  }
  if (entry.textPreview.empty() && isTextMimeType(entry.dataMimeType)) {
    entry.textPreview = buildTextPreview(entry.data);
  }
  return true;
}

std::string ClipboardService::stateDirectory() {
  const char* stateHome = std::getenv("XDG_STATE_HOME");
  if (stateHome != nullptr && stateHome[0] != '\0') {
    return std::string(stateHome) + "/noctalia/clipboard";
  }
  const char* home = std::getenv("HOME");
  if (home != nullptr && home[0] != '\0') {
    return std::string(home) + "/.local/state/noctalia/clipboard";
  }
  return "/tmp/noctalia-clipboard";
}

std::string ClipboardService::manifestPath() { return stateDirectory() + "/index.json"; }

std::string ClipboardService::entriesDirectory() { return stateDirectory() + "/entries"; }

std::string ClipboardService::payloadPathForId(std::string_view storageId) {
  return entriesDirectory() + "/" + std::string(storageId) + ".bin";
}

std::string ClipboardService::generateStorageId() {
  const auto now =
      std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch())
          .count();
  return std::to_string(now) + "-" + std::to_string(++gStorageCounter);
}

std::string ClipboardService::chooseMimeType(const OfferState& offer) const {
  const auto choose = [&offer](const auto& preferred) -> std::string {
    for (std::string_view mimeType : preferred) {
      const auto it = std::ranges::find(offer.mimeTypes, mimeType);
      if (it != offer.mimeTypes.end()) {
        return *it;
      }
    }
    return {};
  };

  if (std::string mimeType = choose(kTextMimeTypes); !mimeType.empty()) {
    return mimeType;
  }
  return choose(kImageMimeTypes);
}

bool ClipboardService::isTextMimeType(std::string_view mimeType) {
  return std::ranges::find(kTextMimeTypes, mimeType) != kTextMimeTypes.end();
}

bool ClipboardService::isEmptyTextPayload(const std::vector<std::uint8_t>& data) {
  bool sawContent = false;
  for (std::uint8_t byte : data) {
    if (byte == 0) {
      continue;
    }
    if (byte == ' ' || byte == '\n' || byte == '\r' || byte == '\t' || byte == '\f' || byte == '\v') {
      continue;
    }
    sawContent = true;
    break;
  }
  return !sawContent;
}

std::string ClipboardService::buildTextPreview(const std::vector<std::uint8_t>& data) {
  const std::size_t previewSize = std::min<std::size_t>(data.size(), kPreviewBytes);
  std::string preview(reinterpret_cast<const char*>(data.data()), previewSize);
  std::ranges::replace(preview, '\n', ' ');
  std::ranges::replace(preview, '\r', ' ');
  std::ranges::replace(preview, '\t', ' ');
  return preview;
}

void ClipboardService::notifyChanged() const {
  if (m_changeCallback) {
    m_changeCallback();
  }
}
