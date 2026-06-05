#include "shell/greeter/greeter_appearance_sync.h"

#include "config/config_service.h"
#include "config/config_types.h"
#include "core/log.h"
#include "core/process.h"
#include "ipc/ipc_service.h"
#include "render/core/color.h"
#include "ui/palette.h"
#include "util/string_utils.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <json.hpp>
#include <memory>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace {

  constexpr Logger kLog("greeter-sync");

  constexpr std::string_view kApplyHelperName = "noctalia-greeter-apply-appearance";
  constexpr std::string_view kGreeterName = "noctalia-greeter";

  [[nodiscard]] std::string
  resolveProgramPath(std::string_view name, std::initializer_list<const char*> fallbackPaths) {
    if (process::commandExists(std::string(name).c_str())) {
      return std::string(name);
    }
    for (const char* candidate : fallbackPaths) {
      std::error_code ec;
      if (std::filesystem::exists(candidate, ec) && !ec) {
        return candidate;
      }
    }
    return {};
  }

  [[nodiscard]] bool programExists(std::string_view name, std::initializer_list<const char*> fallbackPaths) {
    return !resolveProgramPath(name, fallbackPaths).empty();
  }

  Color resolveWallpaperFillColor(const WallpaperConfig& config) {
    if (!config.fillColor) {
      return rgba(0.0f, 0.0f, 0.0f, 0.0f);
    }
    return resolveColorSpec(*config.fillColor);
  }

  void putPaletteColor(nlohmann::json& palette, std::string_view key, const Color& color) {
    palette[std::string(key)] = formatRgbHex(color);
  }

  [[nodiscard]] std::string findApplyHelper() {
    return resolveProgramPath(
        kApplyHelperName,
        {"/usr/bin/noctalia-greeter-apply-appearance", "/usr/local/bin/noctalia-greeter-apply-appearance"}
    );
  }

  [[nodiscard]] std::filesystem::path makeStagingDirectory() {
    const char* runtimeDir = std::getenv("XDG_RUNTIME_DIR");
    const std::filesystem::path base = runtimeDir != nullptr && runtimeDir[0] != '\0'
        ? std::filesystem::path(runtimeDir)
        : std::filesystem::temp_directory_path();
    const auto staging = base / "noctalia-greeter-sync";
    std::error_code ec;
    std::filesystem::remove_all(staging, ec);
    std::filesystem::create_directories(staging, ec);
    if (ec) {
      return {};
    }
    return staging;
  }

  [[nodiscard]] bool writeManifest(
      const std::filesystem::path& staging, const Config& config, std::string_view resolvedMode,
      const std::string& wallpaperPath, const std::string& installedWallpaperName
  ) {
    nlohmann::json root;
    root["version"] = 1;
    root["theme_mode"] = resolvedMode;

    nlohmann::json palette;
    putPaletteColor(palette, "primary", ::palette.primary);
    putPaletteColor(palette, "on_primary", ::palette.onPrimary);
    putPaletteColor(palette, "secondary", ::palette.secondary);
    putPaletteColor(palette, "on_secondary", ::palette.onSecondary);
    putPaletteColor(palette, "tertiary", ::palette.tertiary);
    putPaletteColor(palette, "on_tertiary", ::palette.onTertiary);
    putPaletteColor(palette, "error", ::palette.error);
    putPaletteColor(palette, "on_error", ::palette.onError);
    putPaletteColor(palette, "surface", ::palette.surface);
    putPaletteColor(palette, "on_surface", ::palette.onSurface);
    putPaletteColor(palette, "surface_variant", ::palette.surfaceVariant);
    putPaletteColor(palette, "on_surface_variant", ::palette.onSurfaceVariant);
    putPaletteColor(palette, "outline", ::palette.outline);
    putPaletteColor(palette, "shadow", ::palette.shadow);
    putPaletteColor(palette, "hover", ::palette.hover);
    putPaletteColor(palette, "on_hover", ::palette.onHover);
    root["palette"] = std::move(palette);

    nlohmann::json wallpaper;
    if (!installedWallpaperName.empty()) {
      wallpaper["path"] = (std::filesystem::path("/var/lib/noctalia-greeter") / installedWallpaperName).string();
    } else if (!wallpaperPath.empty()) {
      wallpaper["path"] = wallpaperPath;
    }
    wallpaper["fill_mode"] = std::string(enumToKey(kWallpaperFillModes, config.wallpaper.fillMode));
    const Color fillColor = resolveWallpaperFillColor(config.wallpaper);
    if (fillColor.a > 0.0f) {
      wallpaper["fill_color"] = formatRgbHex(fillColor);
    }
    root["wallpaper"] = std::move(wallpaper);

    const auto manifestPath = staging / "appearance.json";
    std::ofstream out(manifestPath);
    if (!out.is_open()) {
      kLog.warn("failed to open staging manifest '{}'", manifestPath.string());
      return false;
    }
    out << root.dump(2) << '\n';
    return true;
  }

  [[nodiscard]] std::string stageWallpaper(const std::filesystem::path& staging, std::string_view sourcePath) {
    if (sourcePath.empty()) {
      return {};
    }
    if (sourcePath.starts_with("color:")) {
      return {};
    }

    std::error_code ec;
    const std::filesystem::path source(sourcePath);
    if (!std::filesystem::is_regular_file(source, ec) || ec) {
      return {};
    }

    const std::string extension = source.extension().string();
    const std::string installedName = extension.empty() ? "wallpaper" : "wallpaper" + extension;
    const auto destination = staging / installedName;
    std::filesystem::copy_file(source, destination, std::filesystem::copy_options::overwrite_existing, ec);
    if (ec) {
      kLog.warn("failed to stage wallpaper '{}': {}", source.string(), ec.message());
      return {};
    }
    return installedName;
  }

} // namespace

namespace greeter {

  bool appearanceSyncAvailable() {
    return programExists(kGreeterName, {"/usr/bin/noctalia-greeter", "/usr/local/bin/noctalia-greeter"})
        && !findApplyHelper().empty()
        && process::commandExists("pkexec");
  }

  bool syncAppearanceToGreeterAsync(
      const ConfigService& configService, std::string_view resolvedThemeMode, SyncCompletion onComplete
  ) {
    const auto completion = std::make_shared<SyncCompletion>(std::move(onComplete));
    const auto finish = [completion](bool success) {
      if (completion && *completion) {
        (*completion)(success);
      }
    };

    const auto helper = findApplyHelper();
    if (helper.empty()) {
      kLog.warn("greeter sync helper is not installed");
      finish(false);
      return false;
    }
    if (!process::commandExists("pkexec")) {
      kLog.warn("pkexec is not available");
      finish(false);
      return false;
    }

    const auto staging = makeStagingDirectory();
    if (staging.empty()) {
      kLog.warn("failed to create greeter sync staging directory");
      finish(false);
      return false;
    }

    const Config& config = configService.config();
    const std::string wallpaperPath = configService.getDefaultWallpaperPath();
    const std::string installedWallpaperName = stageWallpaper(staging, wallpaperPath);
    if (!writeManifest(staging, config, resolvedThemeMode, wallpaperPath, installedWallpaperName)) {
      finish(false);
      return false;
    }

    const std::vector<std::string> args = {"pkexec", helper, staging.string()};
    process::RunCallbacks callbacks;
    callbacks.onExit = [finish](const process::RunResult& result) {
      if (!result) {
        if (!result.err.empty()) {
          kLog.warn("greeter sync failed: {}", result.err);
        } else {
          kLog.warn("greeter sync failed with exit code {}", result.exitCode);
        }
        finish(false);
        return;
      }
      kLog.info("synced shell appearance to greeter");
      finish(true);
    };
    const bool launched = process::runAsync(args, std::move(callbacks));
    if (!launched) {
      finish(false);
      return false;
    }
    return true;
  }

  void registerIpc(IpcService& ipc, const ConfigService& config, std::function<std::string_view()> resolvedThemeMode) {
    ipc.registerHandler(
        "greeter-sync",
        [&config, resolvedThemeMode = std::move(resolvedThemeMode)](const std::string& args) -> std::string {
          if (!StringUtils::trim(args).empty()) {
            return "error: usage: greeter-sync\n";
          }
          if (!appearanceSyncAvailable()) {
            return "error: noctalia greeter is not installed\n";
          }
          if (!syncAppearanceToGreeterAsync(config, resolvedThemeMode(), {})) {
            return "error: failed to start greeter appearance sync\n";
          }
          return "ok\n";
        },
        "greeter-sync", "Sync wallpaper and colors to Noctalia Greeter"
    );
  }

} // namespace greeter
