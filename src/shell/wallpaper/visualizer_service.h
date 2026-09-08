#pragma once

#include "config/config_types.h"
#include "core/timer_manager.h"

#include <functional>
#include <string>
#include <vector>

class ConfigService;
class MprisService;
class ProjectMRenderer;

// Owns preset selection + rotation for the live-paper visualizer. Wallpaper
// and lock surface both consume the *same* ProjectMRenderer instance — this
// service is the only thing that decides which preset is currently mounted on
// it.
//
// Rotation has two triggers:
//   1. A timer firing every `live_paper.interval_seconds` (skipped when the
//      interval is 0).
//   2. The MPRIS active track changing — gives the visualizer a "beat drop"
//      cue without waiting on the timer.
//
// Both triggers honour a short minimum gap so a flurry of MPRIS events
// (metadata refreshes during track start) does not thrash through preset
// transitions faster than libprojectM can cross-fade.
class VisualizerService {
public:
  VisualizerService();
  ~VisualizerService();

  VisualizerService(const VisualizerService&) = delete;
  VisualizerService& operator=(const VisualizerService&) = delete;

  // Wire up dependencies. The renderer is non-owning and must outlive the
  // service. mpris is the active player source — used to detect track changes
  // for "beat drop" preset advances. May be null if MPRIS is unavailable.
  void initialize(ProjectMRenderer* renderer, ConfigService* config, MprisService* mpris);
  void shutdown();

  // Called when [wallpaper.live_paper] changes in TOML. Rescans the presets
  // directory if it changed; reschedules the rotation timer; loads the first
  // preset if none is mounted yet.
  void onConfigChanged();

  // Application wires its own (single-slot) MprisService::setChangeCallback to
  // ours via this entry point; we de-dup transient metadata refreshes by
  // comparing track ids.
  void onMprisChanged();

  // IPC entry points.
  void advancePreset();
  void setEnabled(bool enabled);
  void toggleEnabled();

  // Session lock state: while locked we suppress automatic preset rotation.
  // The lock-screen background runs the same libprojectM instance as the
  // wallpaper, and a hypothetical bad preset (or a libprojectM bug while
  // loading one) crashes the entire shell — which would dismiss the
  // ext-session-lock-v1 client and unlock the session without auth. Pinning
  // the preset that was already running at lock time avoids that whole class
  // of issue for the duration of the lock.
  void setSessionLocked(bool locked);

  [[nodiscard]] bool enabled() const noexcept;

private:
  void rescanPresets();
  void scheduleRotation();
  void cancelRotation();
  [[nodiscard]] std::string pickRandomPreset();
  [[nodiscard]] std::string resolvePresetsDir() const;
  void applyConfigToRenderer();
  [[nodiscard]] std::vector<std::string> resolveTextureSearchPaths() const;

  ProjectMRenderer* m_renderer = nullptr;
  ConfigService* m_config = nullptr;
  MprisService* m_mpris = nullptr;

  std::vector<std::string> m_presets;
  std::string m_currentPreset;
  std::string m_lastScannedDir;
  std::string m_lastSeenTrackId;
  std::chrono::steady_clock::time_point m_lastAdvanceAt{};
  // First MPRIS observation after init is treated as a discovery (not a
  // user-initiated track change), so we record the id without bumping the
  // preset. Instance-scoped so a shutdown()/initialize() cycle resets the
  // state — a previous implementation used a static-local which leaked
  // across re-init.
  bool m_seenFirstTrack = false;
  bool m_sessionLocked = false;

  Timer m_rotationTimer;
};
