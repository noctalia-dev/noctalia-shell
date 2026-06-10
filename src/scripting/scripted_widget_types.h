#pragma once

#include "config/config_types.h"
#include "core/process.h"

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace scripting {

  struct ScriptWidgetColorPatch {
    std::string role;
    std::string mode;

    bool operator==(const ScriptWidgetColorPatch&) const = default;
  };

  struct ScriptWidgetImagePatch {
    std::string path;
    bool watch = false;
    float width = 0.0f;
    float height = 0.0f;

    bool operator==(const ScriptWidgetImagePatch&) const = default;
  };

  struct ScriptWidgetTooltipRowPatch {
    std::string key;
    std::string value;

    bool operator==(const ScriptWidgetTooltipRowPatch&) const = default;
  };

  struct ScriptWidgetTooltipPatch {
    bool clear = false;
    std::string text;
    std::vector<ScriptWidgetTooltipRowPatch> rows;

    [[nodiscard]] bool hasRows() const noexcept { return !rows.empty(); }

    bool operator==(const ScriptWidgetTooltipPatch&) const = default;
  };

  struct ScriptWidgetPatch {
    std::optional<std::string> text;
    std::optional<std::string> glyph;
    std::optional<ScriptWidgetImagePatch> image;
    std::optional<ScriptWidgetTooltipPatch> tooltip;
    std::optional<std::string> fontFamily;
    std::optional<ScriptWidgetColorPatch> textColor;
    std::optional<ScriptWidgetColorPatch> glyphColor;
    std::optional<bool> visible;
    std::optional<int> updateIntervalMs;

    // Control-center shortcut fields (the `shortcut.*` namespace).
    std::optional<std::string> label;
    std::optional<std::string> iconOn;
    std::optional<std::string> iconOff;
    std::optional<bool> active;
    std::optional<bool> enabled;

    [[nodiscard]] bool empty() const {
      return !text.has_value()
          && !glyph.has_value()
          && !image.has_value()
          && !tooltip.has_value()
          && !fontFamily.has_value()
          && !textColor.has_value()
          && !glyphColor.has_value()
          && !visible.has_value()
          && !updateIntervalMs.has_value()
          && !label.has_value()
          && !iconOn.has_value()
          && !iconOff.has_value()
          && !active.has_value()
          && !enabled.has_value();
    }
  };

  enum class ScriptWidgetSideEffectKind : std::uint8_t {
    Log,
    NotifyInfo,
    NotifyError,
    CopyToClipboard,
  };

  struct ScriptWidgetSideEffect {
    ScriptWidgetSideEffectKind kind = ScriptWidgetSideEffectKind::Log;
    std::string title;
    std::string body;
  };

  struct ScriptWidgetSnapshot {
    bool isVertical = false;
    std::string outputName;
    std::string barName;
    std::string focusedOutputName;
  };

  enum class ScriptWidgetEventKind : std::uint8_t {
    Load,
    Reload,
    Update,
    Call,
    CallBool,
    CallStrings,
    AsyncCommandResult,
    AsyncProcessMatchResult,
    AsyncHttpResult,
    StateWatchResult,
    StreamLine,
    Stop,
  };

  struct ScriptWidgetEvent {
    ScriptWidgetEventKind kind = ScriptWidgetEventKind::Update;
    std::uint64_t generation = 0;
    std::uint64_t hostId = 0;
    std::string functionName;
    std::string chunkName;
    std::string source;
    std::string first;
    std::string second;
    bool boolValue = false;
    bool processMatchResult = false;
    // When true, a newer CallStrings event with the same functionName supersedes
    // this one while it is still queued (only the latest payload matters, e.g.
    // onAudioSpectrum frames). IPC and other callbacks leave this false so every
    // event is delivered.
    bool coalesce = false;
    int callbackRef = 0;
    process::RunResult commandResult;
    // AsyncHttpResult payload.
    bool httpOk = false;
    bool httpIsDownload = false;
    int httpStatus = 0;
    std::string httpBody;
    // StateWatchResult payload (the changed value as JSON).
    std::string stateJson;
    ScriptWidgetSnapshot snapshot;
    std::chrono::milliseconds budget{12};
  };

  struct ScriptWidgetResult {
    std::uint64_t generation = 0;
    ScriptWidgetPatch patch;
    std::vector<ScriptWidgetSideEffect> sideEffects;
    bool ok = true;
    bool timedOut = false;
    bool hasOnIpc = false;
    bool hasOnIpcKnown = false;
    bool unhealthy = false;
    std::string callbackName;
    std::string error;
  };

  using ScriptWidgetSettings = std::unordered_map<std::string, WidgetSettingValue>;
  using ScriptWidgetResultCallback = std::function<void(ScriptWidgetResult)>;

} // namespace scripting
