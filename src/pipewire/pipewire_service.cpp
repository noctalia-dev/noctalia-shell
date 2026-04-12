#include "pipewire/pipewire_service.h"

#include "core/log.h"
#include "core/process.h"

#include <pipewire/extensions/metadata.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/props.h>
#include <spa/pod/builder.h>
#include <spa/pod/parser.h>
#include <spa/utils/result.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <string_view>

namespace {

  // Registry event callbacks (C-style, forwarded to service)
  void onRegistryGlobal(void* data, std::uint32_t id, std::uint32_t /*permissions*/, const char* type,
                        std::uint32_t version, const spa_dict* props) {
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

  // Node event callbacks
  void onNodeInfo(void* data, const pw_node_info* info) {
    auto* nd = static_cast<PipeWireService::NodeData*>(data);
    nd->service->onNodeInfo(nd->id, info);
  }

  void onNodeParam(void* data, int /*seq*/, std::uint32_t id, std::uint32_t index, std::uint32_t next,
                   const spa_pod* param) {
    auto* nd = static_cast<PipeWireService::NodeData*>(data);
    nd->service->onNodeParam(nd->id, id, index, next, param);
  }

  const pw_node_events kNodeEvents = {
      .version = PW_VERSION_NODE_EVENTS,
      .info = onNodeInfo,
      .param = onNodeParam,
  };

  // Metadata events for tracking default sink/source
  struct MetadataData {
    PipeWireService* service = nullptr;
    struct pw_metadata* proxy = nullptr;
    spa_hook* listener = nullptr;
  };

  int onMetadataProperty(void* data, std::uint32_t /*subject*/, const char* key, const char* /*type*/,
                         const char* value) {
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

  constexpr Logger kLog("pipewire");

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

void PipeWireService::onRegistryGlobal(std::uint32_t id, const char* type, std::uint32_t /*version*/,
                                       const spa_dict* props) {
  // Track audio sink/source nodes
  if (std::strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
    std::string mediaClass = dictGet(props, PW_KEY_MEDIA_CLASS);
    if (mediaClass != "Audio/Sink" && mediaClass != "Audio/Source") {
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
    nd->mediaClass = mediaClass;

    // Bind to the node to receive param updates
    auto* proxy = static_cast<pw_node*>(pw_registry_bind(m_registry, id, type, PW_VERSION_NODE, sizeof(void*)));
    if (proxy != nullptr) {
      nd->proxy = proxy;
      nd->listener = new spa_hook{};
      spa_zero(*nd->listener);
      pw_node_add_listener(proxy, nd->listener, &kNodeEvents, nd.get());

      // Subscribe to Props param changes
      std::uint32_t params[] = {SPA_PARAM_Props};
      pw_node_subscribe_params(proxy, params, 1);
      // Request the current props immediately so initial UI state does not sit
      // on the default 100% placeholder until a later change arrives.
      pw_node_enum_params(proxy, 0, SPA_PARAM_Props, 0, 1, nullptr);
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
  }

  // Request Props param enumeration if changes flagged
  if ((info->change_mask & PW_NODE_CHANGE_MASK_PARAMS) != 0) {
    for (std::uint32_t i = 0; i < info->n_params; ++i) {
      if (info->params[i].id == SPA_PARAM_Props) {
        pw_node_enum_params(it->second->proxy, 0, SPA_PARAM_Props, 0, 1, nullptr);
        break;
      }
    }
  }
}

void PipeWireService::onNodeParam(std::uint32_t id, std::uint32_t paramId, std::uint32_t /*index*/,
                                  std::uint32_t /*next*/, const spa_pod* param) {
  if (paramId != SPA_PARAM_Props || param == nullptr) {
    return;
  }

  auto it = m_nodes.find(id);
  if (it == m_nodes.end()) {
    return;
  }

  auto& nd = *it->second;

  // Parse volume and mute from the Props param
  spa_pod_prop* prop = nullptr;
  auto* obj = reinterpret_cast<spa_pod_object*>(const_cast<spa_pod*>(param));

  SPA_POD_OBJECT_FOREACH(obj, prop) {
    if (prop->key == SPA_PROP_channelVolumes) {
      // Channel volumes - take the max across channels
      std::uint32_t nValues = 0;
      auto* arrayData = spa_pod_get_array(&prop->value, &nValues);
      if (arrayData != nullptr && nValues > 0) {
        auto* values = static_cast<float*>(arrayData);
        float maxVol = 0.0f;
        for (std::uint32_t i = 0; i < nValues; ++i) {
          // Convert cubic volume to linear (PipeWire uses cubic internally)
          float linear = std::cbrt(values[i]);
          if (linear > maxVol) {
            maxVol = linear;
          }
        }
        nd.volume = maxVol;
        nd.channelCount = nValues;
      }
    } else if (prop->key == SPA_PROP_mute) {
      bool muted = false;
      if (spa_pod_get_bool(&prop->value, &muted) == 0) {
        nd.muted = muted;
      }
    }
  }

  rebuildState();
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

void PipeWireService::rebuildState() {
  AudioState next;

  for (const auto& [id, nd] : m_nodes) {
    AudioNode node;
    node.id = id;
    node.name = nd->name;
    node.description = nd->description;
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
    }
  }

  // Sort by id for stable ordering
  std::ranges::sort(next.sinks, [](const auto& a, const auto& b) { return a.id < b.id; });
  std::ranges::sort(next.sources, [](const auto& a, const auto& b) { return a.id < b.id; });

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

  const bool updatedViaWpctl =
      process::runSync({"wpctl", "set-volume", std::to_string(id), std::format("{:.4f}", volume)});
  if (updatedViaWpctl) {
    if (std::abs(nd.volume - volume) >= 0.0001f) {
      nd.volume = volume;
      rebuildState();
    }
    return;
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

  // Apply optimistic local state so UI/OSD reacts immediately while waiting for
  // PipeWire to publish the updated node props.
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

  std::uint8_t buffer[256];
  spa_pod_builder builder;
  spa_pod_builder_init(&builder, buffer, sizeof(buffer));

  spa_pod_frame frame;
  spa_pod_builder_push_object(&builder, &frame, SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
  spa_pod_builder_prop(&builder, SPA_PROP_mute, 0);
  spa_pod_builder_bool(&builder, muted);
  auto* pod = static_cast<spa_pod*>(spa_pod_builder_pop(&builder, &frame));

  pw_node_set_param(nd.proxy, SPA_PARAM_Props, 0, pod);

  // Apply optimistic local state so UI/OSD reacts immediately while waiting for
  // PipeWire to publish the updated node props.
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
