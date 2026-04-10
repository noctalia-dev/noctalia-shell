#include "compositors/mango/mango_workspace_backend.h"

#include "core/log.h"

#include <algorithm>
#include <charconv>
#include <string>

#include "dwl-ipc-unstable-v2-client-protocol.h"

namespace {

  constexpr Logger kLog("workspace_mango");

  void managerTags(void* data, zdwl_ipc_manager_v2* /*manager*/, uint32_t amount) {
    static_cast<MangoWorkspaceBackend*>(data)->onTagCount(amount);
  }

  void managerLayout(void* data, zdwl_ipc_manager_v2* /*manager*/, const char* name) {
    static_cast<MangoWorkspaceBackend*>(data)->onLayoutAnnounced(name);
  }

  const zdwl_ipc_manager_v2_listener kManagerListener = {
      .tags = managerTags,
      .layout = managerLayout,
  };

  void outputToggleVisibility(void* /*data*/, zdwl_ipc_output_v2* /*output*/) {}

  void outputActive(void* data, zdwl_ipc_output_v2* output, uint32_t active) {
    static_cast<MangoWorkspaceBackend*>(data)->onOutputActive(output, active);
  }

  void outputTag(void* data, zdwl_ipc_output_v2* output, uint32_t tag, uint32_t state, uint32_t /*clients*/,
                 uint32_t /*focused*/) {
    static_cast<MangoWorkspaceBackend*>(data)->onOutputTag(output, tag, state);
  }

  void outputLayout(void* /*data*/, zdwl_ipc_output_v2* /*output*/, uint32_t /*layout*/) {}
  void outputTitle(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*title*/) {}
  void outputAppId(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*appid*/) {}
  void outputLayoutSymbol(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*layout*/) {}

  void outputFrame(void* data, zdwl_ipc_output_v2* output) {
    static_cast<MangoWorkspaceBackend*>(data)->onOutputFrame(output);
  }

  void outputFullscreen(void* /*data*/, zdwl_ipc_output_v2* /*output*/, uint32_t /*state*/) {}
  void outputFloating(void* /*data*/, zdwl_ipc_output_v2* /*output*/, uint32_t /*state*/) {}
  void outputX(void* /*data*/, zdwl_ipc_output_v2* /*output*/, int32_t /*x*/) {}
  void outputY(void* /*data*/, zdwl_ipc_output_v2* /*output*/, int32_t /*y*/) {}
  void outputWidth(void* /*data*/, zdwl_ipc_output_v2* /*output*/, int32_t /*width*/) {}
  void outputHeight(void* /*data*/, zdwl_ipc_output_v2* /*output*/, int32_t /*height*/) {}
  void outputLastLayer(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*layer*/) {}
  void outputKbLayout(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*layout*/) {}
  void outputKeymode(void* /*data*/, zdwl_ipc_output_v2* /*output*/, const char* /*keymode*/) {}
  void outputScaleFactor(void* /*data*/, zdwl_ipc_output_v2* /*output*/, uint32_t /*scale*/) {}

  const zdwl_ipc_output_v2_listener kOutputListener = {
      .toggle_visibility = outputToggleVisibility,
      .active = outputActive,
      .tag = outputTag,
      .layout = outputLayout,
      .title = outputTitle,
      .appid = outputAppId,
      .layout_symbol = outputLayoutSymbol,
      .frame = outputFrame,
      .fullscreen = outputFullscreen,
      .floating = outputFloating,
      .x = outputX,
      .y = outputY,
      .width = outputWidth,
      .height = outputHeight,
      .last_layer = outputLastLayer,
      .kb_layout = outputKbLayout,
      .keymode = outputKeymode,
      .scalefactor = outputScaleFactor,
  };

} // namespace

void MangoWorkspaceBackend::bind(zdwl_ipc_manager_v2* manager) {
  m_manager = manager;
  zdwl_ipc_manager_v2_add_listener(m_manager, &kManagerListener, this);
  for (const auto& [output, _] : m_outputs) {
    ensureOutputBound(output);
  }
}

void MangoWorkspaceBackend::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void MangoWorkspaceBackend::activate(const std::string& id) {
  auto* state = activeOutputState();
  if (state == nullptr) {
    state = const_cast<OutputState*>(preferredOutputState());
  }
  if (state != nullptr) {
    activateForOutput(state->output, id);
  }
}

void MangoWorkspaceBackend::activateForOutput(wl_output* output, const std::string& id) {
  auto it = m_outputs.find(output);
  if (it == m_outputs.end()) {
    return;
  }

  const auto displayIndex = parseTagIndex(id);
  if (!displayIndex.has_value() || *displayIndex >= it->second.tags.size() || it->second.handle == nullptr) {
    return;
  }

  const std::size_t protocolIndex = protocolIndexForDisplay(*displayIndex);
  zdwl_ipc_output_v2_set_tags(it->second.handle, 1u << protocolIndex, 0);
  kLog.debug("activate request display_tag={} protocol_tag={} output={} snapshot={}", *displayIndex + 1,
             protocolIndex + 1, static_cast<const void*>(output), summarizeTags(it->second));
}

void MangoWorkspaceBackend::activateForOutput(wl_output* output, const Workspace& workspace) {
  const auto index = parseTagIndex(workspace);
  if (!index.has_value()) {
    return;
  }
  activateForOutput(output, std::to_string(*index + 1));
}

std::vector<Workspace> MangoWorkspaceBackend::all() const {
  const auto* state = preferredOutputState();
  return state != nullptr ? forOutput(state->output) : std::vector<Workspace>{};
}

std::vector<Workspace> MangoWorkspaceBackend::forOutput(wl_output* output) const {
  const auto it = m_outputs.find(output);
  if (it == m_outputs.end()) {
    return {};
  }

  std::vector<Workspace> result;
  result.reserve(it->second.tags.size());
  for (std::size_t displayIndex = 0; displayIndex < it->second.tags.size(); ++displayIndex) {
    const std::size_t protocolIndex = protocolIndexForDisplay(displayIndex);
    result.push_back(makeWorkspace(displayIndex, it->second.tags[protocolIndex]));
  }
  return result;
}

void MangoWorkspaceBackend::cleanup() {
  for (auto& [handle, _] : m_outputByHandle) {
    if (handle != nullptr) {
      zdwl_ipc_output_v2_release(handle);
    }
  }
  m_outputByHandle.clear();
  for (auto& [_, state] : m_outputs) {
    state.handle = nullptr;
  }
  if (m_manager != nullptr) {
    zdwl_ipc_manager_v2_release(m_manager);
    m_manager = nullptr;
  }
}

void MangoWorkspaceBackend::onOutputAdded(wl_output* output) {
  m_outputs.try_emplace(output, OutputState{.output = output, .handle = nullptr, .active = false, .tags = {}});
  ensureOutputBound(output);
}

void MangoWorkspaceBackend::onOutputRemoved(wl_output* output) {
  const auto it = m_outputs.find(output);
  if (it == m_outputs.end()) {
    return;
  }

  if (it->second.handle != nullptr) {
    m_outputByHandle.erase(it->second.handle);
    zdwl_ipc_output_v2_release(it->second.handle);
  }
  m_outputs.erase(it);
}

void MangoWorkspaceBackend::onTagCount(std::uint32_t amount) {
  m_tagCount = std::max(m_tagCount, amount);
  for (auto& [_, state] : m_outputs) {
    state.tags.resize(m_tagCount);
  }
}

void MangoWorkspaceBackend::onLayoutAnnounced(const char* name) { m_layouts.push_back(name != nullptr ? name : ""); }

void MangoWorkspaceBackend::onOutputActive(zdwl_ipc_output_v2* handle, std::uint32_t active) {
  const auto it = m_outputByHandle.find(handle);
  if (it == m_outputByHandle.end()) {
    return;
  }
  auto state = m_outputs.find(it->second);
  if (state != m_outputs.end()) {
    state->second.active = active != 0;
  }
}

void MangoWorkspaceBackend::onOutputTag(zdwl_ipc_output_v2* handle, std::uint32_t tag, std::uint32_t stateValue) {
  const auto it = m_outputByHandle.find(handle);
  if (it == m_outputByHandle.end()) {
    return;
  }

  auto output = m_outputs.find(it->second);
  if (output == m_outputs.end()) {
    return;
  }

  // Some compositors may not reliably emit manager.tags before output.tag frames.
  // Learn tag count from output events so display/protocol index mapping stays valid.
  const std::uint32_t inferredCount = tag + 1;
  if (inferredCount > m_tagCount) {
    m_tagCount = inferredCount;
    for (auto& [_, otherState] : m_outputs) {
      otherState.tags.resize(m_tagCount);
    }
  }

  if (tag >= output->second.tags.size()) {
    output->second.tags.resize(tag + 1);
  }

  auto& tagInfo = output->second.tags[tag];
  tagInfo.active = (stateValue & ZDWL_IPC_OUTPUT_V2_TAG_STATE_ACTIVE) != 0;
  tagInfo.urgent = (stateValue & ZDWL_IPC_OUTPUT_V2_TAG_STATE_URGENT) != 0;
  kLog.debug("tag event output={} protocol_tag={} active={} urgent={} total_tags={} snapshot={}",
             static_cast<const void*>(output->second.output), tag + 1, tagInfo.active ? "yes" : "no",
             tagInfo.urgent ? "yes" : "no", m_tagCount, summarizeTags(output->second));
}

void MangoWorkspaceBackend::onOutputFrame(zdwl_ipc_output_v2* handle) {
  const auto it = m_outputByHandle.find(handle);
  if (it != m_outputByHandle.end()) {
    const auto stateIt = m_outputs.find(it->second);
    if (stateIt != m_outputs.end()) {
      kLog.debug("frame output={} total_tags={} snapshot={}", static_cast<const void*>(stateIt->second.output),
                 m_tagCount, summarizeTags(stateIt->second));
    }
  }
  notifyChanged();
}

void MangoWorkspaceBackend::ensureOutputBound(wl_output* output) {
  auto it = m_outputs.find(output);
  if (m_manager == nullptr || it == m_outputs.end() || it->second.handle != nullptr) {
    return;
  }

  auto* handle = zdwl_ipc_manager_v2_get_output(m_manager, output);
  if (handle == nullptr) {
    return;
  }

  it->second.handle = handle;
  it->second.tags.resize(m_tagCount);
  m_outputByHandle.emplace(handle, output);
  zdwl_ipc_output_v2_add_listener(handle, &kOutputListener, this);
}

MangoWorkspaceBackend::OutputState* MangoWorkspaceBackend::activeOutputState() {
  for (auto& [_, state] : m_outputs) {
    if (state.active) {
      return &state;
    }
  }
  return nullptr;
}

const MangoWorkspaceBackend::OutputState* MangoWorkspaceBackend::preferredOutputState() const {
  for (const auto& [_, state] : m_outputs) {
    if (state.active) {
      return &state;
    }
  }
  if (!m_outputs.empty()) {
    return &m_outputs.begin()->second;
  }
  return nullptr;
}

std::optional<std::size_t> MangoWorkspaceBackend::parseTagIndex(const Workspace& workspace) {
  if (!workspace.coordinates.empty()) {
    return static_cast<std::size_t>(workspace.coordinates[0]);
  }
  return parseTagIndex(workspace.id.empty() ? workspace.name : workspace.id);
}

std::optional<std::size_t> MangoWorkspaceBackend::parseTagIndex(const std::string& id) {
  if (id.empty()) {
    return std::nullopt;
  }

  std::size_t value = 0;
  const char* start = id.data();
  const char* end = id.data() + id.size();
  const auto [ptr, ec] = std::from_chars(start, end, value);
  if (ec != std::errc{} || ptr != end || value == 0) {
    return std::nullopt;
  }
  return value - 1;
}

std::size_t MangoWorkspaceBackend::protocolIndexForDisplay(std::size_t displayIndex) const { return displayIndex; }

Workspace MangoWorkspaceBackend::makeWorkspace(std::size_t index, const TagInfo& tag) {
  return Workspace{
      .id = std::to_string(index + 1),
      .name = std::to_string(index + 1),
      .coordinates = {static_cast<std::uint32_t>(index)},
      .active = tag.active,
  };
}

std::string MangoWorkspaceBackend::summarizeTags(const OutputState& state) const {
  if (state.tags.empty()) {
    return "[]";
  }

  std::string out;
  out.reserve(state.tags.size() * 10);
  out += "[";
  for (std::size_t displayIndex = 0; displayIndex < state.tags.size(); ++displayIndex) {
    const std::size_t protocolIndex = protocolIndexForDisplay(displayIndex);
    const auto& tag = state.tags[protocolIndex];
    if (displayIndex > 0) {
      out += ' ';
    }
    out += std::to_string(displayIndex + 1);
    out += "->";
    out += std::to_string(protocolIndex + 1);
    out += tag.active ? "*" : ".";
  }
  out += "]";
  return out;
}

void MangoWorkspaceBackend::notifyChanged() {
  if (m_changeCallback) {
    m_changeCallback();
  }
}
