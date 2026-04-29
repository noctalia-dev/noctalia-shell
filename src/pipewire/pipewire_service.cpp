#include "pipewire/pipewire_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/process.h"
#include "ipc/ipc_arg_parse.h"
#include "ipc/ipc_service.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstring>
#include <memory>
#include <optional>
#include <pipewire/device.h>
#include <pipewire/extensions/metadata.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/props.h>
#include <spa/param/route.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/pod/parser.h>
#include <spa/utils/result.h>
#include <string>
#include <string_view>

namespace {

  constexpr float kDefaultVolumeStep = 0.05f;

  // Registry events.
  void onRegistryGlobal(void* data, std::uint32_t id, std::uint32_t, const char* type, std::uint32_t version,
                        const spa_dict* props) {
    auto* svc = static_cast<PipeWireService*>(data);
    svc->onRegistryGlobal(id, type, version, props);
  }

  void onRegistryGlobalRemove(void* data, std::uint32_t id) {
    auto* svc = static_cast<PipeWireService*>(data);
    svc->onRegistryGlobalRemove(id);
  }

  const pw_registry_events kRegistryEvents = {
      .version = PW_VERSION_REGISTRY_EVENTS,
      .global = onRegistryGlobal,
      .global_remove = onRegistryGlobalRemove,
  };

  void onClientInfo(void* data, const pw_client_info* info) {
    auto* client = static_cast<PipeWireService::ClientData*>(data);
    client->service->onClientInfo(client->id, info);
  }

  const pw_client_events kClientEvents = {
      .version = PW_VERSION_CLIENT_EVENTS,
      .info = onClientInfo,
      .permissions = nullptr,
  };

  // Device events
  void onDeviceInfo(void* data, const pw_device_info* info) {
    auto* dev = static_cast<PipeWireService::DeviceData*>(data);
    dev->service->onDeviceInfo(dev->id, info);
  }

  void onDeviceParam(void* data, int, std::uint32_t id, std::uint32_t index, std::uint32_t next, const spa_pod* param) {
    auto* dev = static_cast<PipeWireService::DeviceData*>(data);
    dev->service->onDeviceParam(dev->id, id, index, next, param);
  }

  const pw_device_events kDeviceEvents = {
      .version = PW_VERSION_DEVICE_EVENTS,
      .info = onDeviceInfo,
      .param = onDeviceParam,
  };

  // Node events.
  void onNodeInfo(void* data, const pw_node_info* info) {
    auto* nd = static_cast<PipeWireService::NodeData*>(data);
    nd->service->onNodeInfo(nd->id, info);
  }

  void onNodeParam(void* data, int, std::uint32_t id, std::uint32_t index, std::uint32_t next, const spa_pod* param) {
    auto* nd = static_cast<PipeWireService::NodeData*>(data);
    nd->service->onNodeParam(nd->id, id, index, next, param);
  }

  const pw_node_events kNodeEvents = {
      .version = PW_VERSION_NODE_EVENTS,
      .info = onNodeInfo,
      .param = onNodeParam,
  };

  // Default sink/source metadata.
  struct MetadataData {
    PipeWireService* service = nullptr;
    struct pw_metadata* proxy = nullptr;
    spa_hook* listener = nullptr;
  };

  int onMetadataProperty(void* data, std::uint32_t, const char* key, const char*, const char* value) {
    if (key == nullptr || value == nullptr) {
      return 0;
    }
    auto* md = static_cast<MetadataData*>(data);
    // Parse the JSON value to extract the name - format is {"name":"sink_name"}
    std::string val(value);
    if (std::strcmp(key, "default.audio.sink") == 0 || std::strcmp(key, "default.audio.source") == 0) {
      auto namePos = val.find("\"name\"");
      if (namePos != std::string::npos) {
        auto colonPos = val.find(':', namePos);
        if (colonPos != std::string::npos) {
          auto firstQuote = val.find('"', colonPos + 1);
          auto secondQuote = val.find('"', firstQuote + 1);
          if (firstQuote != std::string::npos && secondQuote != std::string::npos) {
            std::string name = val.substr(firstQuote + 1, secondQuote - firstQuote - 1);
            spa_dict_item items[1];
            items[0] = SPA_DICT_ITEM_INIT(key, name.c_str());
            spa_dict dict = SPA_DICT_INIT(items, 1);
            md->service->parseDefaultNodes(&dict);
          }
        }
      }
    }
    return 0;
  }

  const pw_metadata_events kMetadataEvents = {
      .version = PW_VERSION_METADATA_EVENTS,
      .property = onMetadataProperty,
  };

  std::string dictGet(const spa_dict* dict, const char* key) {
    if (dict == nullptr) {
      return {};
    }
    const char* val = spa_dict_lookup(dict, key);
    return val != nullptr ? std::string(val) : std::string{};
  }

  std::string escapeJsonString(std::string_view text) {
    std::string escaped;
    escaped.reserve(text.size());

    for (const char ch : text) {
      if (ch == '\\' || ch == '"') {
        escaped.push_back('\\');
      }
      escaped.push_back(ch);
    }

    return escaped;
  }

  std::uint32_t parseUint32Or(const std::string& value, std::uint32_t fallback = 0) {
    if (value.empty()) {
      return fallback;
    }
    std::uint32_t out = fallback;
    const auto* begin = value.data();
    const auto* end = value.data() + value.size();
    const auto [ptr, ec] = std::from_chars(begin, end, out);
    if (ec != std::errc{} || ptr != end) {
      return fallback;
    }
    return out;
  }

  std::optional<float> parseFloat(const std::string& value) {
    if (value.empty()) {
      return std::nullopt;
    }
    try {
      return std::stof(value);
    } catch (...) {
      return std::nullopt;
    }
  }

  std::optional<bool> parseBool(const std::string& value) {
    if (value.empty()) {
      return std::nullopt;
    }
    if (value == "1" || value == "true" || value == "yes" || value == "on") {
      return true;
    }
    if (value == "0" || value == "false" || value == "no" || value == "off") {
      return false;
    }
    return std::nullopt;
  }

  void applyVolumePropsFromDict(PipeWireService::NodeData& nd, const spa_dict* props) {
    if (props == nullptr) {
      return;
    }

    if (const auto maybeChannelmixVolume = parseFloat(dictGet(props, "channelmix.volume"));
        maybeChannelmixVolume.has_value()) {
      nd.volume = std::clamp(*maybeChannelmixVolume, 0.0f, 1.5f);
    } else if (const auto maybeVolume = parseFloat(dictGet(props, "volume")); maybeVolume.has_value()) {
      nd.volume = std::clamp(*maybeVolume, 0.0f, 1.5f);
    }

    if (const auto maybeChannelmixMuted = parseBool(dictGet(props, "channelmix.mute"));
        maybeChannelmixMuted.has_value()) {
      nd.muted = *maybeChannelmixMuted;
    } else if (const auto maybeMuted = parseBool(dictGet(props, "mute")); maybeMuted.has_value()) {
      nd.muted = *maybeMuted;
    }
  }

  bool applyClientPropsFromDict(PipeWireService::ClientData& client, const spa_dict* props) {
    if (props == nullptr) {
      return false;
    }

    bool changed = false;
    auto assignIfBetter = [&changed](std::string& field, std::string value) {
      if (!value.empty() && field != value) {
        field = std::move(value);
        changed = true;
      }
    };

    std::string name = dictGet(props, "application.name");
    if (name.empty()) {
      name = dictGet(props, "client.name");
    }
    assignIfBetter(client.name, std::move(name));

    std::string appId = dictGet(props, "application.id");
    if (appId.ends_with(".desktop")) {
      appId.erase(appId.size() - std::string_view(".desktop").size());
    }
    assignIfBetter(client.appId, std::move(appId));

    assignIfBetter(client.binary, dictGet(props, "application.process.binary"));

    std::string iconName = dictGet(props, "application.icon-name");
    if (iconName.empty()) {
      iconName = dictGet(props, "node.icon-name");
    }
    assignIfBetter(client.iconName, std::move(iconName));

    return changed;
  }

  void parseVolumeArrayProp(const spa_pod_prop* prop, float& outVolume, std::uint32_t* outChannelCount = nullptr) {
    if (prop == nullptr) {
      return;
    }
    const auto* array = reinterpret_cast<const spa_pod_array*>(&prop->value);
    spa_pod* iter = nullptr;
    float maxVol = 0.0f;
    std::uint32_t count = 0;
    SPA_POD_ARRAY_FOREACH(array, iter) {
      const float cubic = *reinterpret_cast<const float*>(iter);
      const float linear = std::cbrt(std::max(0.0f, cubic));
      if (linear > maxVol) {
        maxVol = linear;
      }
      ++count;
    }
    if (count > 0) {
      outVolume = maxVol;
      if (outChannelCount != nullptr) {
        *outChannelCount = count;
      }
    }
  }

  constexpr Logger kLog("pipewire");

  bool isProgramStreamClass(std::string_view mediaClass) { return mediaClass == "Stream/Output/Audio"; }

  void logProgramStreamMetadata(std::string_view phase, std::uint32_t id, const PipeWireService::NodeData& nd) {
    if (!isProgramStreamClass(nd.mediaClass)) {
      return;
    }
    kLog.debug(
        "[program-stream] {} id={} clientId={} class='{}' appName='{}' appId='{}' appBinary='{}' streamTitle='{}' "
        "icon='{}' nodeName='{}' nodeDesc='{}'",
        phase, id, nd.clientId, nd.mediaClass, nd.applicationName, nd.applicationId, nd.applicationBinary,
        nd.streamTitle, nd.iconName, nd.name, nd.description);
  }

} // namespace

PipeWireService::PipeWireService() {
  pw_init(nullptr, nullptr);

  m_loop = pw_loop_new(nullptr);
  if (m_loop == nullptr) {
    throw std::runtime_error("pipewire: failed to create loop");
  }

  m_context = pw_context_new(m_loop, nullptr, 0);
  if (m_context == nullptr) {
    pw_loop_destroy(m_loop);
    throw std::runtime_error("pipewire: failed to create context");
  }

  m_core = pw_context_connect(m_context, nullptr, 0);
  if (m_core == nullptr) {
    pw_context_destroy(m_context);
    pw_loop_destroy(m_loop);
    throw std::runtime_error("pipewire: failed to connect to daemon");
  }

  m_registry = pw_core_get_registry(m_core, PW_VERSION_REGISTRY, 0);
  if (m_registry == nullptr) {
    pw_core_disconnect(m_core);
    pw_context_destroy(m_context);
    pw_loop_destroy(m_loop);
    throw std::runtime_error("pipewire: failed to get registry");
  }

  m_registryListener = new spa_hook{};
  spa_zero(*m_registryListener);
  pw_registry_add_listener(m_registry, m_registryListener, &kRegistryEvents, this);

  // Do initial roundtrip to discover existing objects
  auto* loop = m_loop;
  pw_core_sync(m_core, PW_ID_CORE, 0);
  while (pw_loop_iterate(loop, 0) > 0) {
  }

  kLog.info("connected (version {})", pw_get_library_version());
  const auto* sink = defaultSink();
  if (sink != nullptr) {
    kLog.info("default sink \"{}\" vol={:.0f}%", sink->description, sink->volume * 100.0f);
  }
}

PipeWireService::~PipeWireService() {
  // Destroy node proxies and their listeners
  for (auto& [id, nd] : m_nodes) {
    if (nd->listener != nullptr) {
      spa_hook_remove(nd->listener);
      delete nd->listener;
    }
    if (nd->proxy != nullptr) {
      pw_proxy_destroy(reinterpret_cast<pw_proxy*>(nd->proxy));
    }
  }
  m_nodes.clear();

  for (auto& [id, client] : m_clients) {
    if (client.listener != nullptr) {
      spa_hook_remove(client.listener);
      delete client.listener;
    }
    if (client.proxy != nullptr) {
      pw_proxy_destroy(reinterpret_cast<pw_proxy*>(client.proxy));
    }
  }
  m_clients.clear();

  for (auto& [id, device] : m_devices) {
    if (device.listener != nullptr) {
      spa_hook_remove(device.listener);
      delete device.listener;
    }
    if (device.proxy != nullptr) {
      pw_proxy_destroy(reinterpret_cast<pw_proxy*>(device.proxy));
    }
  }
  m_devices.clear();

  for (auto& cleanup : m_metadataCleanups) {
    cleanup();
  }
  m_metadataCleanups.clear();

  if (m_registryListener != nullptr) {
    spa_hook_remove(m_registryListener);
    delete m_registryListener;
  }

  if (m_registry != nullptr) {
    pw_proxy_destroy(reinterpret_cast<pw_proxy*>(m_registry));
  }
  if (m_core != nullptr) {
    pw_core_disconnect(m_core);
  }
  if (m_context != nullptr) {
    pw_context_destroy(m_context);
  }
  if (m_loop != nullptr) {
    pw_loop_destroy(m_loop);
  }

  pw_deinit();
}

int PipeWireService::fd() const noexcept {
  if (m_loop == nullptr) {
    return -1;
  }
  auto* loop = m_loop;
  return pw_loop_get_fd(loop);
}

void PipeWireService::dispatch() {
  if (m_loop == nullptr) {
    return;
  }
  auto* loop = m_loop;
  // Process all pending events without blocking
  while (pw_loop_iterate(loop, 0) > 0) {
  }
}

const AudioNode* PipeWireService::defaultSink() const noexcept {
  for (const auto& sink : m_state.sinks) {
    if (sink.isDefault) {
      return &sink;
    }
  }
  return m_state.sinks.empty() ? nullptr : &m_state.sinks.front();
}

const AudioNode* PipeWireService::defaultSource() const noexcept {
  for (const auto& source : m_state.sources) {
    if (source.isDefault) {
      return &source;
    }
  }
  return m_state.sources.empty() ? nullptr : &m_state.sources.front();
}

void PipeWireService::onRegistryGlobal(std::uint32_t id, const char* type, std::uint32_t, const spa_dict* props) {
  if (std::strcmp(type, PW_TYPE_INTERFACE_Client) == 0) {
    ClientData client;
    client.service = this;
    client.id = id;
    applyClientPropsFromDict(client, props);
    auto [it, inserted] = m_clients.insert_or_assign(id, std::move(client));

    auto& stored = it->second;
    if (inserted) {
      auto* proxy = static_cast<pw_client*>(pw_registry_bind(m_registry, id, type, PW_VERSION_CLIENT, sizeof(void*)));
      if (proxy != nullptr) {
        stored.proxy = proxy;
        stored.listener = new spa_hook{};
        spa_zero(*stored.listener);
        pw_client_add_listener(proxy, stored.listener, &kClientEvents, &stored);
      }
    }

    for (auto& [_, node] : m_nodes) {
      if (node != nullptr) {
        refreshNodeIdentity(*node);
      }
    }
    // New client metadata can improve already-known stream node identity.
    rebuildState();
    return;
  }

  if (std::strcmp(type, PW_TYPE_INTERFACE_Device) == 0) {
    DeviceData device;
    device.service = this;
    device.id = id;
    auto [it, inserted] = m_devices.insert_or_assign(id, std::move(device));

    auto& stored = it->second;
    if (inserted) {
      auto* proxy = static_cast<pw_device*>(pw_registry_bind(m_registry, id, type, PW_VERSION_DEVICE, sizeof(void*)));
      if (proxy != nullptr) {
        stored.proxy = proxy;
        stored.listener = new spa_hook{};
        spa_zero(*stored.listener);
        pw_device_add_listener(proxy, stored.listener, &kDeviceEvents, &stored);
        std::uint32_t params[] = {SPA_PARAM_Route};
        pw_device_subscribe_params(proxy, params, 1);
        pw_device_enum_params(proxy, 0, SPA_PARAM_Route, 0, UINT32_MAX, nullptr);
      }
    }
    return;
  }

  // Track audio sink/source nodes
  if (std::strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
    std::string mediaClass = dictGet(props, PW_KEY_MEDIA_CLASS);
    if (mediaClass != "Audio/Sink" && mediaClass != "Audio/Source" && mediaClass != "Stream/Output/Audio") {
      return;
    }

    auto nd = std::make_unique<NodeData>();
    nd->service = this;
    nd->id = id;
    nd->name = dictGet(props, PW_KEY_NODE_NAME);
    nd->description = dictGet(props, PW_KEY_NODE_DESCRIPTION);
    if (nd->description.empty()) {
      nd->description = dictGet(props, PW_KEY_NODE_NICK);
    }
    if (nd->description.empty()) {
      nd->description = nd->name;
    }
    nd->clientId = parseUint32Or(dictGet(props, "client.id"));
    nd->deviceId = parseUint32Or(dictGet(props, "device.id"));
    nd->applicationName = dictGet(props, "application.name");
    if (nd->applicationName.empty()) {
      nd->applicationName = dictGet(props, "client.name");
    }
    nd->applicationId = dictGet(props, "application.id");
    if (nd->applicationId.ends_with(".desktop")) {
      nd->applicationId.erase(nd->applicationId.size() - std::string_view(".desktop").size());
    }
    nd->applicationBinary = dictGet(props, "application.process.binary");
    if (nd->applicationName.empty()) {
      nd->applicationName = nd->applicationBinary;
    }
    if (nd->applicationName.empty()) {
      nd->applicationName = nd->description;
    }

    nd->streamTitle = dictGet(props, "media.title");
    if (nd->streamTitle.empty()) {
      nd->streamTitle = dictGet(props, "media.name");
    }
    if (nd->streamTitle.empty()) {
      nd->streamTitle = dictGet(props, "node.nick");
    }
    if (nd->streamTitle.empty()) {
      nd->streamTitle = dictGet(props, PW_KEY_NODE_DESCRIPTION);
    }

    nd->iconName = dictGet(props, "application.icon-name");
    if (nd->iconName.empty()) {
      nd->iconName = dictGet(props, "node.icon-name");
    }
    if (nd->iconName.empty()) {
      nd->iconName = nd->applicationBinary;
    }
    nd->mediaClass = mediaClass;
    applyVolumePropsFromDict(*nd, props);
    refreshNodeIdentity(*nd);
    logProgramStreamMetadata("registry-global", id, *nd);

    // Bind to the node to receive param updates
    auto* proxy = static_cast<pw_node*>(pw_registry_bind(m_registry, id, type, PW_VERSION_NODE, sizeof(void*)));
    if (proxy != nullptr) {
      nd->proxy = proxy;
      nd->listener = new spa_hook{};
      spa_zero(*nd->listener);
      pw_node_add_listener(proxy, nd->listener, &kNodeEvents, nd.get());

      // Subscribe to Props param changes
      std::uint32_t params[] = {SPA_PARAM_Props, SPA_PARAM_Route};
      pw_node_subscribe_params(proxy, params, 2);
      // Fetch current props so initial UI state does not sit at 100%.
      pw_node_enum_params(proxy, 0, SPA_PARAM_Props, 0, UINT32_MAX, nullptr);
      pw_node_enum_params(proxy, 0, SPA_PARAM_Route, 0, UINT32_MAX, nullptr);
    }

    m_nodes[id] = std::move(nd);
    rebuildState();
  }

  // Track metadata for default sink/source names
  if (std::strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0) {
    std::string name = dictGet(props, PW_KEY_METADATA_NAME);
    if (name == "default") {
      auto* proxy =
          static_cast<pw_metadata*>(pw_registry_bind(m_registry, id, type, PW_VERSION_METADATA, sizeof(void*)));
      if (proxy != nullptr) {
        m_defaultMetadata = proxy;
        auto* md = new MetadataData{this, proxy, new spa_hook{}};
        spa_zero(*md->listener);
        pw_metadata_add_listener(proxy, md->listener, &kMetadataEvents, md);
        m_metadataCleanups.push_back([md]() {
          if (md->listener != nullptr) {
            spa_hook_remove(md->listener);
            delete md->listener;
          }
          if (md->proxy != nullptr) {
            pw_proxy_destroy(reinterpret_cast<pw_proxy*>(md->proxy));
          }
          if (md->service != nullptr && md->service->m_defaultMetadata == md->proxy) {
            md->service->m_defaultMetadata = nullptr;
          }
          delete md;
        });
      }
    }
  }
}

void PipeWireService::onRegistryGlobalRemove(std::uint32_t id) {
  if (auto it = m_clients.find(id); it != m_clients.end()) {
    if (it->second.listener != nullptr) {
      spa_hook_remove(it->second.listener);
      delete it->second.listener;
    }
    if (it->second.proxy != nullptr) {
      pw_proxy_destroy(reinterpret_cast<pw_proxy*>(it->second.proxy));
    }
    m_clients.erase(it);
    for (auto& [_, node] : m_nodes) {
      if (node != nullptr) {
        refreshNodeIdentity(*node);
      }
    }
    rebuildState();
    return;
  }

  if (auto it = m_devices.find(id); it != m_devices.end()) {
    if (it->second.listener != nullptr) {
      spa_hook_remove(it->second.listener);
      delete it->second.listener;
    }
    if (it->second.proxy != nullptr) {
      pw_proxy_destroy(reinterpret_cast<pw_proxy*>(it->second.proxy));
    }
    m_devices.erase(it);
    return;
  }

  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  auto& nd = it->second;
  if (nd->listener != nullptr) {
    spa_hook_remove(nd->listener);
    delete nd->listener;
  }
  if (nd->proxy != nullptr) {
    pw_proxy_destroy(reinterpret_cast<pw_proxy*>(nd->proxy));
  }
  m_nodes.erase(it);
  rebuildState();
}

void PipeWireService::onNodeInfo(std::uint32_t id, const pw_node_info* info) {
  if (info == nullptr) {
    return;
  }

  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  // Update name/description from props if available
  if (info->props != nullptr) {
    std::string desc = dictGet(info->props, PW_KEY_NODE_DESCRIPTION);
    if (!desc.empty()) {
      it->second->description = desc;
    }
    std::string name = dictGet(info->props, PW_KEY_NODE_NAME);
    if (!name.empty()) {
      it->second->name = name;
    }
    std::string appName = dictGet(info->props, "application.name");
    if (appName.empty()) {
      appName = dictGet(info->props, "client.name");
    }
    if (!appName.empty()) {
      it->second->applicationName = appName;
    }
    std::string appId = dictGet(info->props, "application.id");
    if (appId.ends_with(".desktop")) {
      appId.erase(appId.size() - std::string_view(".desktop").size());
    }
    if (!appId.empty()) {
      it->second->applicationId = appId;
    }
    const std::uint32_t clientId = parseUint32Or(dictGet(info->props, "client.id"), it->second->clientId);
    if (clientId != 0) {
      it->second->clientId = clientId;
    }
    const std::uint32_t deviceId = parseUint32Or(dictGet(info->props, "device.id"), it->second->deviceId);
    if (deviceId != 0) {
      it->second->deviceId = deviceId;
    }
    std::string appBinary = dictGet(info->props, "application.process.binary");
    if (!appBinary.empty()) {
      it->second->applicationBinary = appBinary;
      if (it->second->applicationName.empty()) {
        it->second->applicationName = appBinary;
      }
    }
    std::string mediaName = dictGet(info->props, "media.title");
    if (mediaName.empty()) {
      mediaName = dictGet(info->props, "media.name");
    }
    if (!mediaName.empty()) {
      it->second->streamTitle = mediaName;
    }
    std::string iconName = dictGet(info->props, "application.icon-name");
    if (iconName.empty()) {
      iconName = dictGet(info->props, "node.icon-name");
    }
    if (!iconName.empty()) {
      it->second->iconName = iconName;
    }
    applyVolumePropsFromDict(*it->second, info->props);
    refreshNodeIdentity(*it->second);
    logProgramStreamMetadata("node-info", id, *it->second);
  }

  // Request Props param enumeration if changes flagged
  if ((info->change_mask & PW_NODE_CHANGE_MASK_PARAMS) != 0) {
    for (std::uint32_t i = 0; i < info->n_params; ++i) {
      if (info->params[i].id == SPA_PARAM_Props) {
        pw_node_enum_params(it->second->proxy, 0, SPA_PARAM_Props, 0, UINT32_MAX, nullptr);
      } else if (info->params[i].id == SPA_PARAM_Route) {
        pw_node_enum_params(it->second->proxy, 0, SPA_PARAM_Route, 0, UINT32_MAX, nullptr);
      }
    }
  }
}

void PipeWireService::onNodeParam(std::uint32_t id, std::uint32_t paramId, std::uint32_t, std::uint32_t,
                                  const spa_pod* param) {
  if ((paramId != SPA_PARAM_Props && paramId != SPA_PARAM_Route) || param == nullptr) {
    return;
  }

  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  auto& nd = *it->second;
  if (paramId == SPA_PARAM_Route) {
    std::int32_t routeIndex = -1;
    std::int32_t routeDevice = -1;
    std::uint32_t routeDirection = nd.routeDirection;
    const spa_pod* routeProps = nullptr;
    if (spa_pod_parse_object(param, SPA_TYPE_OBJECT_ParamRoute, nullptr, SPA_PARAM_ROUTE_index,
                             SPA_POD_Int(&routeIndex), SPA_PARAM_ROUTE_direction, SPA_POD_Id(&routeDirection),
                             SPA_PARAM_ROUTE_device, SPA_POD_Int(&routeDevice), SPA_PARAM_ROUTE_props,
                             SPA_POD_Pod(&routeProps)) >= 0) {
      if (routeIndex >= 0) {
        nd.routeIndex = routeIndex;
        nd.routeDevice = routeDevice;
        nd.routeDirection = routeDirection;
        nd.hasRoute = true;
      }
      if (routeProps != nullptr) {
        spa_pod_prop* prop = nullptr;
        auto* propsObj = reinterpret_cast<spa_pod_object*>(const_cast<spa_pod*>(routeProps));
        SPA_POD_OBJECT_FOREACH(propsObj, prop) {
          if (prop->key == SPA_PROP_mute) {
            bool muted = false;
            if (spa_pod_get_bool(&prop->value, &muted) == 0) {
              nd.muted = muted;
            }
          }
        }
      }
      rebuildState();
    }
    return;
  }

  float parsedChannelVolumes = nd.volume;
  float parsedVolume = nd.volume;
  float parsedSoftVolumes = nd.volume;
  std::uint32_t parsedChannelCount = nd.channelCount;
  bool hasChannelVolumes = false;
  bool hasVolume = false;
  bool hasSoftVolumes = false;

  // Parse volume and mute from the Props param
  spa_pod_prop* prop = nullptr;
  auto* obj = reinterpret_cast<spa_pod_object*>(const_cast<spa_pod*>(param));

  SPA_POD_OBJECT_FOREACH(obj, prop) {
    if (prop->key == SPA_PROP_channelVolumes) {
      // Channel volumes - take the max across channels.
      parseVolumeArrayProp(prop, parsedChannelVolumes, &parsedChannelCount);
      hasChannelVolumes = true;
    } else if (prop->key == SPA_PROP_volume) {
      float cubic = 0.0f;
      if (spa_pod_get_float(&prop->value, &cubic) == 0) {
        parsedVolume = std::cbrt(std::max(0.0f, cubic));
        hasVolume = true;
      }
    } else if (prop->key == SPA_PROP_softVolumes) {
      parseVolumeArrayProp(prop, parsedSoftVolumes);
      hasSoftVolumes = true;
    } else if (prop->key == SPA_PROP_mute) {
      bool muted = false;
      if (spa_pod_get_bool(&prop->value, &muted) == 0) {
        nd.muted = muted;
      }
    }
  }

  if (hasChannelVolumes) {
    nd.volume = parsedChannelVolumes;
    nd.channelCount = parsedChannelCount;
  } else if (hasVolume) {
    nd.volume = parsedVolume;
  } else if (hasSoftVolumes) {
    nd.volume = parsedSoftVolumes;
  }

  if (isProgramStreamClass(nd.mediaClass)) {
    kLog.debug("[program-stream] node-param id={} class='{}' volume={:.3f} muted={} channels={}", id, nd.mediaClass,
               nd.volume, nd.muted, nd.channelCount);
  }

  rebuildState();
}

void PipeWireService::onClientInfo(std::uint32_t id, const pw_client_info* info) {
  if (info == nullptr || info->props == nullptr) {
    return;
  }

  auto it = m_clients.find(id);
  if (it == m_clients.end()) {
    return;
  }

  if (!applyClientPropsFromDict(it->second, info->props)) {
    return;
  }

  for (auto& [_, node] : m_nodes) {
    if (node != nullptr) {
      refreshNodeIdentity(*node);
    }
  }
  rebuildState();
}

void PipeWireService::onDeviceInfo(std::uint32_t id, const pw_device_info* info) {
  if (info == nullptr) {
    return;
  }
  auto it = m_devices.find(id);
  if (it == m_devices.end() || it->second.proxy == nullptr) {
    return;
  }

  if ((info->change_mask & PW_DEVICE_CHANGE_MASK_PARAMS) != 0) {
    for (std::uint32_t i = 0; i < info->n_params; ++i) {
      if (info->params[i].id == SPA_PARAM_Route) {
        pw_device_enum_params(it->second.proxy, 0, SPA_PARAM_Route, 0, UINT32_MAX, nullptr);
      }
    }
  }
}

void PipeWireService::onDeviceParam(std::uint32_t id, std::uint32_t paramId, std::uint32_t index, std::uint32_t,
                                    const spa_pod* param) {
  if (paramId != SPA_PARAM_Route || param == nullptr) {
    return;
  }

  auto it = m_devices.find(id);
  if (it == m_devices.end()) {
    return;
  }

  std::int32_t routeIndex = -1;
  std::int32_t routeDevice = -1;
  std::uint32_t routeDirection = 0;
  const spa_pod* routeProps = nullptr;
  if (spa_pod_parse_object(param, SPA_TYPE_OBJECT_ParamRoute, nullptr, SPA_PARAM_ROUTE_index, SPA_POD_Int(&routeIndex),
                           SPA_PARAM_ROUTE_direction, SPA_POD_Id(&routeDirection), SPA_PARAM_ROUTE_device,
                           SPA_POD_Int(&routeDevice), SPA_PARAM_ROUTE_props, SPA_POD_Pod(&routeProps)) < 0) {
    return;
  }

  bool muted = false;
  if (routeProps != nullptr) {
    spa_pod_prop* prop = nullptr;
    auto* propsObj = reinterpret_cast<spa_pod_object*>(const_cast<spa_pod*>(routeProps));
    SPA_POD_OBJECT_FOREACH(propsObj, prop) {
      if (prop->key == SPA_PROP_mute) {
        bool routeMuted = false;
        if (spa_pod_get_bool(&prop->value, &routeMuted) == 0) {
          muted = routeMuted;
        }
      }
    }
  }

  auto& routes = it->second.routes;
  auto existing =
      std::find_if(routes.begin(), routes.end(), [routeIndex](const auto& route) { return route.index == routeIndex; });
  if (existing == routes.end()) {
    DeviceRouteData route;
    route.index = routeIndex >= 0 ? routeIndex : static_cast<std::int32_t>(index);
    route.device = routeDevice;
    route.direction = routeDirection;
    route.muted = muted;
    routes.push_back(route);
  } else {
    existing->device = routeDevice;
    existing->direction = routeDirection;
    existing->muted = muted;
  }
}

void PipeWireService::parseDefaultNodes(const spa_dict* props) {
  std::string sinkName = dictGet(props, "default.audio.sink");
  std::string sourceName = dictGet(props, "default.audio.source");

  bool changed = false;
  if (!sinkName.empty() && sinkName != m_defaultSinkName) {
    m_defaultSinkName = sinkName;
    changed = true;
  }
  if (!sourceName.empty() && sourceName != m_defaultSourceName) {
    m_defaultSourceName = sourceName;
    changed = true;
  }

  if (changed) {
    rebuildState();
  }
}

void PipeWireService::refreshNodeIdentity(NodeData& nd) {
  const auto it = m_clients.find(nd.clientId);
  if (it == m_clients.end()) {
    return;
  }
  const ClientData& client = it->second;
  if ((nd.applicationName.empty() || nd.applicationName == "audio-src" || nd.applicationName == "audio-sink" ||
       nd.applicationName == "audio-source") &&
      !client.name.empty()) {
    nd.applicationName = client.name;
  }
  if ((nd.applicationId.empty() || nd.applicationId == "audio-src") && !client.appId.empty()) {
    nd.applicationId = client.appId;
  }
  if ((nd.applicationBinary.empty() || nd.applicationBinary == "audio-src") && !client.binary.empty()) {
    nd.applicationBinary = client.binary;
  }
  if (nd.iconName.empty() && !client.iconName.empty()) {
    nd.iconName = client.iconName;
  }
}

void PipeWireService::rebuildState() {
  AudioState next;

  for (const auto& [id, nd] : m_nodes) {
    AudioNode node;
    node.id = id;
    node.name = nd->name;
    node.description = nd->description;
    node.applicationName = nd->applicationName;
    node.applicationId = nd->applicationId;
    node.applicationBinary = nd->applicationBinary;
    node.streamTitle = nd->streamTitle;
    node.iconName = nd->iconName;
    node.mediaClass = nd->mediaClass;
    node.volume = nd->volume;
    node.muted = nd->muted;
    node.channelCount = nd->channelCount;

    if (nd->mediaClass == "Audio/Sink") {
      node.isDefault = (nd->name == m_defaultSinkName);
      if (node.isDefault) {
        next.defaultSinkId = id;
      }
      next.sinks.push_back(std::move(node));
    } else if (nd->mediaClass == "Audio/Source") {
      node.isDefault = (nd->name == m_defaultSourceName);
      if (node.isDefault) {
        next.defaultSourceId = id;
      }
      next.sources.push_back(std::move(node));
    } else if (nd->mediaClass == "Stream/Output/Audio") {
      next.programOutputs.push_back(std::move(node));
    }
  }

  // Sort by id for stable ordering
  std::ranges::sort(next.sinks, [](const auto& a, const auto& b) { return a.id < b.id; });
  std::ranges::sort(next.sources, [](const auto& a, const auto& b) { return a.id < b.id; });
  std::ranges::sort(next.programOutputs, [](const auto& a, const auto& b) { return a.id < b.id; });

  if (next == m_state) {
    return;
  }

  m_state = std::move(next);
  ++m_changeSerial;
  emitChanged();
}

void PipeWireService::setNodeVolume(std::uint32_t id, float volume) {
  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  auto& nd = *it->second;
  if (nd.proxy == nullptr) {
    return;
  }

  volume = std::clamp(volume, 0.0f, 1.5f);

  // Use wpctl only for real device nodes.
  const bool isDeviceNode = nd.mediaClass == "Audio/Sink" || nd.mediaClass == "Audio/Source";
  if (isDeviceNode) {
    const bool updatedViaWpctl =
        process::runSync({"wpctl", "set-volume", std::to_string(id), std::format("{:.4f}", volume)});
    if (updatedViaWpctl) {
      if (std::abs(nd.volume - volume) >= 0.0001f) {
        nd.volume = volume;
        rebuildState();
      }
      return;
    }
  }

  // Convert linear volume to cubic (PipeWire native)
  float cubic = volume * volume * volume;

  std::uint32_t nChannels = nd.channelCount > 0 ? nd.channelCount : 2;
  std::vector<float> volumes(nChannels, cubic);

  std::uint8_t buffer[1024];
  spa_pod_builder builder;
  spa_pod_builder_init(&builder, buffer, sizeof(buffer));

  spa_pod_frame frame;
  spa_pod_builder_push_object(&builder, &frame, SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
  spa_pod_builder_prop(&builder, SPA_PROP_channelVolumes, 0);
  spa_pod_builder_array(&builder, sizeof(float), SPA_TYPE_Float, nChannels, volumes.data());
  auto* pod = static_cast<spa_pod*>(spa_pod_builder_pop(&builder, &frame));

  pw_node_set_param(nd.proxy, SPA_PARAM_Props, 0, pod);

  // Apply optimistic local state while PipeWire publishes props.
  if (std::abs(nd.volume - volume) >= 0.0001f) {
    nd.volume = volume;
    rebuildState();
  }
}

void PipeWireService::setNodeMuted(std::uint32_t id, bool muted) {
  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  auto& nd = *it->second;
  if (nd.proxy == nullptr) {
    return;
  }

  const bool isDeviceNode = nd.mediaClass == "Audio/Sink" || nd.mediaClass == "Audio/Source";
  if (isDeviceNode && nd.deviceId != 0) {
    auto devIt = m_devices.find(nd.deviceId);
    if (devIt != m_devices.end() && devIt->second.proxy != nullptr) {
      const std::uint32_t targetDirection =
          (nd.mediaClass == "Audio/Source") ? SPA_DIRECTION_INPUT : SPA_DIRECTION_OUTPUT;
      bool wroteDeviceRoute = false;
      for (const auto& route : devIt->second.routes) {
        if (route.index < 0 || route.direction != targetDirection) {
          continue;
        }

        std::uint8_t routeBuffer[512];
        spa_pod_builder routeBuilder;
        spa_pod_builder_init(&routeBuilder, routeBuffer, sizeof(routeBuffer));

        spa_pod_frame routeFrame;
        spa_pod_builder_push_object(&routeBuilder, &routeFrame, SPA_TYPE_OBJECT_ParamRoute, SPA_PARAM_Route);
        spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_index, 0);
        spa_pod_builder_int(&routeBuilder, route.index);
        spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_direction, 0);
        spa_pod_builder_id(&routeBuilder, route.direction);
        spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_device, 0);
        spa_pod_builder_int(&routeBuilder, route.device);
        spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_props, 0);
        spa_pod_frame routePropsFrame;
        spa_pod_builder_push_object(&routeBuilder, &routePropsFrame, SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
        spa_pod_builder_prop(&routeBuilder, SPA_PROP_mute, 0);
        spa_pod_builder_bool(&routeBuilder, muted);
        spa_pod_builder_pop(&routeBuilder, &routePropsFrame);
        spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_save, 0);
        spa_pod_builder_bool(&routeBuilder, true);
        auto* routePod = static_cast<spa_pod*>(spa_pod_builder_pop(&routeBuilder, &routeFrame));
        pw_device_set_param(devIt->second.proxy, SPA_PARAM_Route, 0, routePod);
        wroteDeviceRoute = true;
      }

      if (wroteDeviceRoute) {
        if (nd.muted != muted) {
          nd.muted = muted;
          rebuildState();
        }
        return;
      }
    }
  }

  if (nd.hasRoute && nd.routeIndex >= 0) {
    std::uint8_t routeBuffer[512];
    spa_pod_builder routeBuilder;
    spa_pod_builder_init(&routeBuilder, routeBuffer, sizeof(routeBuffer));

    spa_pod_frame routeFrame;
    spa_pod_builder_push_object(&routeBuilder, &routeFrame, SPA_TYPE_OBJECT_ParamRoute, SPA_PARAM_Route);
    spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_index, 0);
    spa_pod_builder_int(&routeBuilder, nd.routeIndex);
    spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_direction, 0);
    spa_pod_builder_id(&routeBuilder, nd.routeDirection);
    spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_device, 0);
    spa_pod_builder_int(&routeBuilder, nd.routeDevice);
    spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_props, 0);
    spa_pod_frame routePropsFrame;
    spa_pod_builder_push_object(&routeBuilder, &routePropsFrame, SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
    spa_pod_builder_prop(&routeBuilder, SPA_PROP_mute, 0);
    spa_pod_builder_bool(&routeBuilder, muted);
    spa_pod_builder_pop(&routeBuilder, &routePropsFrame);
    spa_pod_builder_prop(&routeBuilder, SPA_PARAM_ROUTE_save, 0);
    spa_pod_builder_bool(&routeBuilder, true);
    auto* routePod = static_cast<spa_pod*>(spa_pod_builder_pop(&routeBuilder, &routeFrame));
    pw_node_set_param(nd.proxy, SPA_PARAM_Route, 0, routePod);
  }

  std::uint8_t buffer[256];
  spa_pod_builder builder;
  spa_pod_builder_init(&builder, buffer, sizeof(buffer));

  spa_pod_frame frame;
  spa_pod_builder_push_object(&builder, &frame, SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
  spa_pod_builder_prop(&builder, SPA_PROP_mute, 0);
  spa_pod_builder_bool(&builder, muted);
  auto* pod = static_cast<spa_pod*>(spa_pod_builder_pop(&builder, &frame));

  pw_node_set_param(nd.proxy, SPA_PARAM_Props, 0, pod);

  // Apply optimistic local state while PipeWire publishes props.
  if (nd.muted != muted) {
    nd.muted = muted;
    rebuildState();
  }
}

void PipeWireService::setSinkVolume(std::uint32_t id, float volume) { setNodeVolume(id, volume); }
void PipeWireService::setSinkMuted(std::uint32_t id, bool muted) { setNodeMuted(id, muted); }
void PipeWireService::setDefaultSink(std::uint32_t id) { setDefaultNode(id, "default.audio.sink"); }
void PipeWireService::setSourceVolume(std::uint32_t id, float volume) { setNodeVolume(id, volume); }
void PipeWireService::setSourceMuted(std::uint32_t id, bool muted) { setNodeMuted(id, muted); }
void PipeWireService::setDefaultSource(std::uint32_t id) { setDefaultNode(id, "default.audio.source"); }

void PipeWireService::setProgramOutputVolume(std::uint32_t id, float volume) { setNodeVolume(id, volume); }
void PipeWireService::setProgramOutputMuted(std::uint32_t id, bool muted) { setNodeMuted(id, muted); }

void PipeWireService::setDefaultNode(std::uint32_t id, const char* key) {
  const auto it = m_nodes.find(id);
  if (it == m_nodes.end() || key == nullptr) {
    return;
  }

  // Prefer wpctl so WirePlumber persists the default. Metadata API alone often does not survive reboot.
  if (process::runSync({"wpctl", "set-default", std::to_string(id)})) {
    if (std::strcmp(key, "default.audio.sink") == 0) {
      m_defaultSinkName = it->second->name;
    } else if (std::strcmp(key, "default.audio.source") == 0) {
      m_defaultSourceName = it->second->name;
    }
    rebuildState();
    return;
  }

  if (m_defaultMetadata == nullptr) {
    kLog.warn("unable to set {} - default metadata unavailable", key);
    return;
  }

  const std::string payload = "{\"name\":\"" + escapeJsonString(it->second->name) + "\"}";
  const int rc = pw_metadata_set_property(m_defaultMetadata, PW_ID_CORE, key, "Spa:String:JSON", payload.c_str());
  if (rc < 0) {
    kLog.warn("failed to set {} to \"{}\" ({})", key, it->second->name, spa_strerror(rc));
    return;
  }

  if (std::strcmp(key, "default.audio.sink") == 0) {
    m_defaultSinkName = it->second->name;
  } else if (std::strcmp(key, "default.audio.source") == 0) {
    m_defaultSourceName = it->second->name;
  }
  rebuildState();
}

void PipeWireService::setVolume(float volume) {
  const auto* sink = defaultSink();
  if (sink != nullptr) {
    setNodeVolume(sink->id, volume);
  }
}

void PipeWireService::setMuted(bool muted) {
  const auto* sink = defaultSink();
  if (sink != nullptr) {
    setNodeMuted(sink->id, muted);
  }
}

void PipeWireService::setMicVolume(float volume) {
  const auto* source = defaultSource();
  if (source != nullptr) {
    setNodeVolume(source->id, volume);
  }
}

void PipeWireService::setMicMuted(bool muted) {
  const auto* source = defaultSource();
  if (source != nullptr) {
    setNodeMuted(source->id, muted);
  }
}

void PipeWireService::emitVolumePreview(bool isInput, std::uint32_t id, float volume) const {
  if (!m_volumePreviewCallback) {
    return;
  }
  const auto it = m_nodes.find(id);
  const bool muted = (it != m_nodes.end()) ? it->second->muted : false;
  m_volumePreviewCallback(isInput, id, std::clamp(volume, 0.0f, 1.5f), muted);
}

void PipeWireService::emitChanged() {
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void PipeWireService::registerIpc(IpcService& ipc, const ConfigService& config) {
  const auto maxVolume = [&config] { return config.config().audio.enableOverdrive ? 1.5f : 1.0f; };
  const auto parseVolumeValueError =
      "error: invalid volume value (use percent like 65 or 65%, or normalized like 0.65)\n";
  const auto parseVolumeStepError = "error: invalid volume step (use percent like 5 or 5%, or normalized like 0.05)\n";

  ipc.registerHandler(
      "volume-set",
      [this, maxVolume, parseVolumeValueError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() != 1) {
          return "error: volume-set requires <value>\n";
        }
        const auto* sink = defaultSink();
        if (!sink)
          return "error: no default output\n";

        const auto amount = noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!amount.has_value()) {
          return parseVolumeValueError;
        }

        setVolume(std::clamp(*amount, 0.0f, maxVolume()));
        return "ok\n";
      },
      "volume-set <value>", "Set speaker volume");

  ipc.registerHandler(
      "volume-up",
      [this, maxVolume, parseVolumeStepError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() > 1) {
          return "error: volume-up accepts at most one optional [step]\n";
        }
        const auto* sink = defaultSink();
        if (!sink)
          return "error: no default output\n";

        const auto step = parts.empty() ? std::optional<float>(kDefaultVolumeStep)
                                        : noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!step.has_value()) {
          return parseVolumeStepError;
        }

        setVolume(std::clamp(sink->volume + *step, 0.0f, maxVolume()));
        return "ok\n";
      },
      "volume-up [step]", "Increase speaker volume");

  ipc.registerHandler(
      "volume-down",
      [this, maxVolume, parseVolumeStepError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() > 1) {
          return "error: volume-down accepts at most one optional [step]\n";
        }
        const auto* sink = defaultSink();
        if (!sink)
          return "error: no default output\n";

        const auto step = parts.empty() ? std::optional<float>(kDefaultVolumeStep)
                                        : noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!step.has_value()) {
          return parseVolumeStepError;
        }

        setVolume(std::clamp(sink->volume - *step, 0.0f, maxVolume()));
        return "ok\n";
      },
      "volume-down [step]", "Decrease speaker volume");

  ipc.registerHandler(
      "volume-mute",
      [this](const std::string&) -> std::string {
        const auto* sink = defaultSink();
        if (!sink)
          return "error: no default output\n";
        setMuted(!sink->muted);
        return "ok\n";
      },
      "volume-mute", "Toggle speaker mute");

  ipc.registerHandler(
      "mic-volume-set",
      [this, maxVolume, parseVolumeValueError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() != 1) {
          return "error: mic-volume-set requires <value>\n";
        }
        const auto* source = defaultSource();
        if (!source)
          return "error: no default input\n";

        const auto amount = noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!amount.has_value()) {
          return parseVolumeValueError;
        }

        setMicVolume(std::clamp(*amount, 0.0f, maxVolume()));
        return "ok\n";
      },
      "mic-volume-set <value>", "Set microphone volume");

  ipc.registerHandler(
      "mic-volume-up",
      [this, maxVolume, parseVolumeStepError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() > 1) {
          return "error: mic-volume-up accepts at most one optional [step]\n";
        }
        const auto* source = defaultSource();
        if (!source)
          return "error: no default input\n";

        const auto step = parts.empty() ? std::optional<float>(kDefaultVolumeStep)
                                        : noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!step.has_value()) {
          return parseVolumeStepError;
        }

        setMicVolume(std::clamp(source->volume + *step, 0.0f, maxVolume()));
        return "ok\n";
      },
      "mic-volume-up [step]", "Increase microphone volume");

  ipc.registerHandler(
      "mic-volume-down",
      [this, maxVolume, parseVolumeStepError](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() > 1) {
          return "error: mic-volume-down accepts at most one optional [step]\n";
        }
        const auto* source = defaultSource();
        if (!source)
          return "error: no default input\n";

        const auto step = parts.empty() ? std::optional<float>(kDefaultVolumeStep)
                                        : noctalia::ipc::parseNormalizedOrPercent(parts[0], maxVolume() * 100.0f);
        if (!step.has_value()) {
          return parseVolumeStepError;
        }

        setMicVolume(std::clamp(source->volume - *step, 0.0f, maxVolume()));
        return "ok\n";
      },
      "mic-volume-down [step]", "Decrease microphone volume");

  ipc.registerHandler(
      "mic-mute",
      [this](const std::string&) -> std::string {
        const auto* source = defaultSource();
        if (!source)
          return "error: no default input\n";
        setMicMuted(!source->muted);
        return "ok\n";
      },
      "mic-mute", "Toggle microphone mute");
}
