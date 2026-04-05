#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

struct pw_context;
struct pw_core;
struct pw_loop;
struct pw_registry;
struct spa_hook;

struct AudioNode {
  std::uint32_t id = 0;
  std::string name;
  std::string description;
  std::string mediaClass; // "Audio/Sink", "Audio/Source"
  float volume = 1.0f;
  bool muted = false;
  std::uint32_t channelCount = 0;
  bool isDefault = false;
};

struct AudioState {
  std::vector<AudioNode> sinks;
  std::vector<AudioNode> sources;
  std::uint32_t defaultSinkId = 0;
  std::uint32_t defaultSourceId = 0;
};

class PipeWireService {
public:
  using ChangeCallback = std::function<void()>;

  PipeWireService();
  ~PipeWireService();

  PipeWireService(const PipeWireService&) = delete;
  PipeWireService& operator=(const PipeWireService&) = delete;

  void setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  // Poll integration
  [[nodiscard]] int fd() const noexcept;
  void dispatch();

  // State
  [[nodiscard]] const AudioState& state() const noexcept { return m_state; }
  [[nodiscard]] const AudioNode* defaultSink() const noexcept;
  [[nodiscard]] const AudioNode* defaultSource() const noexcept;

  // Control
  void setSinkVolume(std::uint32_t id, float volume);
  void setSinkMuted(std::uint32_t id, bool muted);
  void setSourceVolume(std::uint32_t id, float volume);
  void setSourceMuted(std::uint32_t id, bool muted);

  // Convenience (operates on default sink/source)
  void setVolume(float volume);
  void setMuted(bool muted);
  void setMicVolume(float volume);
  void setMicMuted(bool muted);

  // Called from C callbacks in the .cpp — must be public
  struct NodeData {
    PipeWireService* service = nullptr;
    std::uint32_t id = 0;
    std::string name;
    std::string description;
    std::string mediaClass;
    float volume = 1.0f;
    bool muted = false;
    std::uint32_t channelCount = 0;
    struct pw_node* proxy = nullptr;
    spa_hook* listener = nullptr;
  };
  void onRegistryGlobal(std::uint32_t id, const char* type, std::uint32_t version, const struct spa_dict* props);
  void onRegistryGlobalRemove(std::uint32_t id);
  void onNodeInfo(std::uint32_t id, const struct pw_node_info* info);
  void onNodeParam(std::uint32_t id, std::uint32_t paramId, std::uint32_t index, std::uint32_t next,
                   const struct spa_pod* param);
  void parseDefaultNodes(const struct spa_dict* props);

private:
  void rebuildState();
  void setNodeVolume(std::uint32_t id, float volume);
  void setNodeMuted(std::uint32_t id, bool muted);

  pw_loop* m_loop = nullptr;
  pw_context* m_context = nullptr;
  pw_core* m_core = nullptr;
  pw_registry* m_registry = nullptr;

  // Listener hooks (must outlive the objects they listen to)
  spa_hook* m_coreListener = nullptr;
  spa_hook* m_registryListener = nullptr;

  std::unordered_map<std::uint32_t, std::unique_ptr<NodeData>> m_nodes;
  std::vector<std::function<void()>> m_metadataCleanups;
  std::string m_defaultSinkName;
  std::string m_defaultSourceName;
  AudioState m_state;
  ChangeCallback m_changeCallback;

  void emitChanged();
};
