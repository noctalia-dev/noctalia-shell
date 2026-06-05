#pragma once

#include "capture/screencopy_capture.h"
#include "capture/screenshot_region_overlay.h"

#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class ClipboardService;
class CompositorPlatform;
class ConfigService;
class IpcService;
class NotificationManager;
struct Config;
class RenderContext;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct wl_output;

class ScreenshotService {
public:
  struct OutputOptions {
    bool saveToFile = true;
    bool copyToClipboard = false;
    bool pipeToCommand = false;
    bool freezeScreen = false;
    std::string pipeCommand;
    std::string directory;
    std::string filenamePattern;
  };

  ScreenshotService(
      WaylandConnection& wayland, CompositorPlatform& platform, NotificationManager& notifications,
      ClipboardService* clipboard = nullptr
  );
  ~ScreenshotService();

  [[nodiscard]] bool available() const noexcept;

  void captureFullscreen(const OutputOptions& options, wl_output* output = nullptr);
  void captureFullscreenInteractive(RenderContext& renderContext, const OutputOptions& options);
  void beginRegionCapture(RenderContext& renderContext, const OutputOptions& options);
  void beginFullscreenCapture(RenderContext& renderContext, const OutputOptions& options);

  void onOutputChange();

  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);
  [[nodiscard]] bool onKeyboardEvent(const KeyboardEvent& event);

  [[nodiscard]] static OutputOptions outputOptionsFromConfig(const Config& config);

  void registerIpc(IpcService& ipc, const ConfigService& configService);

private:
  struct PendingCapture {
    wl_output* output = nullptr;
    std::optional<LogicalRect> region;
    OutputOptions outputOptions{};
    std::optional<std::filesystem::path> destPath;
  };

  struct AllOutputCaptureTarget {
    wl_output* output = nullptr;
    std::string label;
  };

  struct AllOutputsBatch {
    OutputOptions options{};
    std::vector<AllOutputCaptureTarget> targets;
    std::vector<capture::FrozenScreenshot> frames;
    std::size_t next = 0;
  };

  void captureOutput(
      wl_output* output, std::optional<LogicalRect> region, const std::string& labelBase, const OutputOptions& options,
      int pathSuffix = 0
  );
  void ensureRegionOverlay();
  void startRegionOverlay(RenderContext& renderContext);
  void startFullscreenOverlay(RenderContext& renderContext);
  void beginFreezeCapture();
  void finishFreezeCapture();
  void abortFreezeCapture(const std::string& message);
  void cancelRegionCapture();
  void deliverFrozenRegion(LogicalRect region, wl_output* output, const OutputOptions& options);
  void completeFullscreenSelection(wl_output* output, const OutputOptions& options);
  void startNextQueuedCapture();
  void captureAllOutputs(const OutputOptions& options);
  void startNextAllOutputsCapture();
  void onAllOutputsFrameCaptured(
      wl_output* output, const std::string& label, std::optional<ScreencopyImage> image, const std::string& error
  );
  void finishAllOutputsBatch();
  void cancelAllOutputsBatch();
  void deliverCaptureResult(
      ScreencopyImage image, const OutputOptions& options, std::optional<std::filesystem::path> destPath
  );
  void onCaptureComplete(
      std::optional<ScreencopyImage> image, const std::string& error, OutputOptions options,
      std::optional<std::filesystem::path> destPath, wl_output* output
  );
  [[nodiscard]] wl_output* preferredCaptureOutput() const;
  [[nodiscard]] std::filesystem::path defaultPicturesDirectory() const;
  [[nodiscard]] std::filesystem::path outputDirectory(const OutputOptions& options) const;
  [[nodiscard]] std::filesystem::path
  makeScreenshotPath(const OutputOptions& options, const std::string& labelBase, int suffix = 0) const;
  void notifySaved(const std::filesystem::path& path);
  void notifyError(const std::string& message);

  WaylandConnection& m_wayland;
  CompositorPlatform& m_platform;
  NotificationManager& m_notifications;
  ClipboardService* m_clipboard = nullptr;
  ScreencopyCapture m_capture;
  std::unique_ptr<capture::ScreenshotRegionOverlay> m_regionOverlay;
  std::vector<PendingCapture> m_captureQueue;
  std::optional<AllOutputsBatch> m_allOutputsBatch;
  OutputOptions m_regionOutputOptions{};
  RenderContext* m_regionRenderContext = nullptr;
  bool m_regionFullscreenPick = false;
  std::vector<capture::FrozenScreenshot> m_frozenScreenshots;
  std::vector<wl_output*> m_pendingFreezeOutputs;
  bool m_freezeCaptureActive = false;
};
