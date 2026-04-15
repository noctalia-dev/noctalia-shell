#include "theme/theme_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "net/http_client.h"
#include "theme/builtin_palettes.h"
#include "theme/fixed_palette.h"
#include "theme/image_loader.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"

#include <cctype>
#include <chrono>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <format>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>

#include <json.hpp>

namespace noctalia::theme {

  namespace {

    constexpr auto kLog = Logger("theme");

    constexpr float kTransitionDurationMs = 400.0f;
    constexpr std::chrono::milliseconds kTransitionTick{8};

    struct ResolvedTheme {
      GeneratedPalette generated;
      Palette palette;
      std::string mode;
    };

    std::string resolvedModeName(const ThemeConfig& cfg) { return cfg.mode == ThemeMode::Light ? "light" : "dark"; }

    ResolvedTheme resolveBuiltin(const ThemeConfig& cfg) {
      const auto* palette = findBuiltinPalette(cfg.builtinPalette);
      if (palette == nullptr) {
        kLog.warn("unknown builtin palette '{}', falling back to Noctalia", cfg.builtinPalette);
        palette = findBuiltinPalette("Noctalia");
      }
      const std::string mode = resolvedModeName(cfg);
      const GeneratedPalette generated = expandBuiltinPalette(*palette);
      return {
          .generated = generated,
          .palette = mapGeneratedPaletteMode(mode == "light" ? generated.light : generated.dark),
          .mode = mode,
      };
    }

    std::optional<ResolvedTheme> resolveWallpaper(const ThemeConfig& cfg, const std::string& wallpaperPath) {
      if (wallpaperPath.empty()) {
        kLog.warn("wallpaper theme requested but no wallpaper path set");
        return std::nullopt;
      }
      auto scheme = schemeFromString(cfg.wallpaperScheme);
      if (!scheme.has_value()) {
        kLog.warn("unknown wallpaper scheme '{}', falling back to m3-content", cfg.wallpaperScheme);
        scheme = Scheme::Content;
      }
      std::string err;
      auto image = loadAndResize(wallpaperPath, *scheme, &err);
      if (!image.has_value()) {
        kLog.warn("failed to load wallpaper '{}': {}", wallpaperPath, err);
        return std::nullopt;
      }
      auto generated = generate(image->rgb, *scheme, &err);
      if (generated.dark.empty()) {
        kLog.warn("failed to generate palette from wallpaper: {}", err);
        return std::nullopt;
      }
      const std::string mode = resolvedModeName(cfg);
      return ResolvedTheme{
          .generated = generated,
          .palette = mapGeneratedPaletteMode(mode == "light" ? generated.light : generated.dark),
          .mode = mode,
      };
    }

    std::string urlEncode(std::string_view text) {
      std::string encoded;
      encoded.reserve(text.size() * 3);
      auto isUnreserved = [](unsigned char ch) {
        return std::isalnum(ch) != 0 || ch == '-' || ch == '_' || ch == '.' || ch == '~';
      };
      for (char rawCh : text) {
        const auto ch = static_cast<unsigned char>(rawCh);
        if (isUnreserved(ch)) {
          encoded.push_back(static_cast<char>(ch));
        } else {
          encoded += std::format("%{:02X}", static_cast<unsigned int>(ch));
        }
      }
      return encoded;
    }

    std::filesystem::path communityPaletteCacheDir() {
      if (const char* xdg = std::getenv("XDG_CACHE_HOME"); xdg != nullptr && xdg[0] != '\0') {
        return std::filesystem::path(xdg) / "noctalia" / "community-palettes";
      }
      if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
        return std::filesystem::path(home) / ".cache" / "noctalia" / "community-palettes";
      }
      return std::filesystem::path("/tmp") / "noctalia" / "community-palettes";
    }

    std::filesystem::path communityPaletteCachePath(std::string_view encodedName) {
      return communityPaletteCacheDir() / (std::string(encodedName) + ".json");
    }

    // Reads a color key from a JSON object, looking first for the `m`-prefixed form
    // (e.g. `mPrimary`) and falling back to the unprefixed name. Returns fallback
    // (transparent black) if the key is missing or the value is not a hex string.
    Color readColorField(const nlohmann::json& obj, std::string_view camelField) {
      std::string prefixed = "m";
      prefixed.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(camelField[0]))));
      prefixed.append(camelField.substr(1));
      auto tryRead = [&](const std::string& key) -> std::optional<Color> {
        auto it = obj.find(key);
        if (it == obj.end() || !it->is_string()) {
          return std::nullopt;
        }
        try {
          return hex(it->get<std::string>());
        } catch (const std::exception&) {
          return std::nullopt;
        }
      };
      if (auto c = tryRead(prefixed))
        return *c;
      if (auto c = tryRead(std::string(camelField)))
        return *c;
      return Color{};
    }

    Palette readPaletteJson(const nlohmann::json& obj) {
      return Palette{
          .primary = readColorField(obj, "primary"),
          .onPrimary = readColorField(obj, "onPrimary"),
          .secondary = readColorField(obj, "secondary"),
          .onSecondary = readColorField(obj, "onSecondary"),
          .tertiary = readColorField(obj, "tertiary"),
          .onTertiary = readColorField(obj, "onTertiary"),
          .error = readColorField(obj, "error"),
          .onError = readColorField(obj, "onError"),
          .surface = readColorField(obj, "surface"),
          .onSurface = readColorField(obj, "onSurface"),
          .surfaceVariant = readColorField(obj, "surfaceVariant"),
          .onSurfaceVariant = readColorField(obj, "onSurfaceVariant"),
          .outline = readColorField(obj, "outline"),
          .shadow = readColorField(obj, "shadow"),
          .hover = readColorField(obj, "hover"),
          .onHover = readColorField(obj, "onHover"),
      };
    }

    TerminalAnsiColors readAnsiJson(const nlohmann::json& obj) {
      return TerminalAnsiColors{
          .black = readColorField(obj, "black"),
          .red = readColorField(obj, "red"),
          .green = readColorField(obj, "green"),
          .yellow = readColorField(obj, "yellow"),
          .blue = readColorField(obj, "blue"),
          .magenta = readColorField(obj, "magenta"),
          .cyan = readColorField(obj, "cyan"),
          .white = readColorField(obj, "white"),
      };
    }

    TerminalPalette readTerminalJson(const nlohmann::json& obj) {
      TerminalPalette tp{};
      if (auto it = obj.find("normal"); it != obj.end() && it->is_object()) {
        tp.normal = readAnsiJson(*it);
      }
      if (auto it = obj.find("bright"); it != obj.end() && it->is_object()) {
        tp.bright = readAnsiJson(*it);
      }
      tp.foreground = readColorField(obj, "foreground");
      tp.background = readColorField(obj, "background");
      tp.selectionFg = readColorField(obj, "selectionFg");
      tp.selectionBg = readColorField(obj, "selectionBg");
      tp.cursorText = readColorField(obj, "cursorText");
      tp.cursor = readColorField(obj, "cursor");
      return tp;
    }

    struct ParsedCommunityPalette {
      Palette dark;
      Palette light;
      TerminalPalette darkTerminal;
      TerminalPalette lightTerminal;
    };

    std::optional<ParsedCommunityPalette> parseCommunityPaletteJson(const std::filesystem::path& path) {
      try {
        std::ifstream in(path);
        if (!in)
          return std::nullopt;
        std::stringstream buf;
        buf << in.rdbuf();
        auto root = nlohmann::json::parse(buf.str());
        if (!root.is_object())
          return std::nullopt;
        ParsedCommunityPalette out{};
        if (auto it = root.find("dark"); it != root.end() && it->is_object()) {
          out.dark = readPaletteJson(*it);
        } else {
          return std::nullopt;
        }
        if (auto it = root.find("light"); it != root.end() && it->is_object()) {
          out.light = readPaletteJson(*it);
        } else {
          out.light = out.dark;
        }
        if (auto it = root.find("darkTerminal"); it != root.end() && it->is_object()) {
          out.darkTerminal = readTerminalJson(*it);
        }
        if (auto it = root.find("lightTerminal"); it != root.end() && it->is_object()) {
          out.lightTerminal = readTerminalJson(*it);
        }
        return out;
      } catch (const std::exception& e) {
        kLog.warn("failed to parse community palette '{}': {}", path.string(), e.what());
        return std::nullopt;
      }
    }

    ResolvedTheme makeResolvedFromParsed(const ParsedCommunityPalette& parsed, const ThemeConfig& cfg) {
      BuiltinPalette bp{
          .name = "community",
          .dark = parsed.dark,
          .light = parsed.light,
          .darkTerminal = parsed.darkTerminal,
          .lightTerminal = parsed.lightTerminal,
      };
      const std::string mode = resolvedModeName(cfg);
      const GeneratedPalette generated = expandBuiltinPalette(bp);
      return {
          .generated = generated,
          .palette = mapGeneratedPaletteMode(mode == "light" ? generated.light : generated.dark),
          .mode = mode,
      };
    }

  } // namespace

  ThemeService::ThemeService(ConfigService& config, HttpClient& httpClient)
      : m_config(config), m_httpClient(httpClient) {}

  void ThemeService::apply() { resolveAndSet(/*animate=*/false); }

  void ThemeService::onConfigReload() { resolveAndSet(/*animate=*/true); }

  void ThemeService::onWallpaperChange() {
    if (m_config.config().theme.source == ThemeSource::Wallpaper) {
      resolveAndSet(/*animate=*/true);
    }
  }

  void ThemeService::toggleLightDark() {
    const auto next = m_isLightMode ? ThemeMode::Dark : ThemeMode::Light;
    // Persist via ConfigService → StateService. The resulting overrides-change
    // callback rebuilds the Config and fires the reload callbacks, which call
    // ThemeService::onConfigReload() to transition to the new palette.
    m_config.setThemeMode(next);
  }

  bool ThemeService::isLightMode() const noexcept { return m_isLightMode; }

  void ThemeService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  void ThemeService::setResolvedCallback(ResolvedCallback callback) { m_resolvedCallback = std::move(callback); }

  void ThemeService::startCommunityDownload(const std::string& name) {
    if (m_inflightCommunityName == name) {
      return;
    }
    m_inflightCommunityName = name;
    const std::string encoded = urlEncode(name);
    const auto cachePath = communityPaletteCachePath(encoded);
    std::error_code ec;
    std::filesystem::create_directories(cachePath.parent_path(), ec);
    const std::string url = "https://api.noctalia.dev/palette/" + encoded;
    kLog.info("fetching community palette '{}' from {}", name, url);
    m_httpClient.download(url, cachePath, [this, name, cachePath](bool success) {
      if (m_inflightCommunityName == name) {
        m_inflightCommunityName.clear();
      }
      if (!success) {
        kLog.warn("community palette download failed for '{}'", name);
        return;
      }
      // Validate the just-downloaded file. If it parses, trigger a re-resolve.
      if (!parseCommunityPaletteJson(cachePath).has_value()) {
        kLog.warn("community palette '{}' downloaded but failed to parse; removing cache", name);
        std::error_code rmEc;
        std::filesystem::remove(cachePath, rmEc);
        return;
      }
      resolveAndSet(/*animate=*/true);
    });
  }

  void ThemeService::resolveAndSet(bool animate) {
    const auto& cfg = m_config.config().theme;
    std::optional<ResolvedTheme> resolved;
    if (cfg.source == ThemeSource::Wallpaper) {
      resolved = resolveWallpaper(cfg, m_config.getDefaultWallpaperPath());
    } else if (cfg.source == ThemeSource::Community && !cfg.communityPalette.empty()) {
      const auto cachePath = communityPaletteCachePath(urlEncode(cfg.communityPalette));
      if (std::filesystem::exists(cachePath)) {
        if (auto parsed = parseCommunityPaletteJson(cachePath)) {
          resolved = makeResolvedFromParsed(*parsed, cfg);
        } else {
          std::error_code rmEc;
          std::filesystem::remove(cachePath, rmEc);
        }
      }
      if (!resolved.has_value()) {
        startCommunityDownload(cfg.communityPalette);
      }
    }
    if (!resolved.has_value()) {
      resolved = resolveBuiltin(cfg);
    }

    if (m_resolvedCallback) {
      m_resolvedCallback(resolved->generated, resolved->mode);
    }

    m_isLightMode = resolved->mode == "light";

    if (animate) {
      startTransition(resolved->palette);
    } else {
      if (m_transitionAnimId == 0 && palette == resolved->palette) {
        return;
      }
      if (m_transitionAnimId != 0) {
        m_animations.cancel(m_transitionAnimId);
        m_transitionAnimId = 0;
      }
      m_transitionTimer.stop();
      setPalette(resolved->palette);
      if (m_changeCallback) {
        m_changeCallback();
      }
    }
  }

  void ThemeService::startTransition(const Palette& target) {
    if (m_transitionAnimId == 0 && palette == target) {
      return;
    }
    if (m_transitionAnimId != 0 && m_targetPalette == target) {
      return;
    }
    // Capture the currently-displayed palette (possibly mid-fade) so a new
    // transition starts from wherever the previous one had reached.
    if (m_transitionAnimId != 0) {
      m_animations.cancel(m_transitionAnimId);
      m_transitionAnimId = 0;
    }
    m_fromPalette = palette;
    m_targetPalette = target;
    m_transitionAnimId = m_animations.animate(
        0.0f, 1.0f, kTransitionDurationMs, Easing::EaseOutCubic,
        [this](float t) {
          setPalette(lerpPalette(m_fromPalette, m_targetPalette, t));
          if (m_changeCallback) {
            m_changeCallback();
          }
        },
        [this]() {
          m_transitionAnimId = 0;
          m_transitionTimer.stop();
          setPalette(m_targetPalette);
          if (m_changeCallback) {
            m_changeCallback();
          }
        });
    if (m_transitionAnimId == 0) {
      m_transitionTimer.stop();
      return;
    }
    m_transitionTimer.startRepeating(kTransitionTick, [this] { tickTransition(); });
  }

  void ThemeService::tickTransition() {
    if (!m_animations.hasActive()) {
      m_transitionTimer.stop();
      return;
    }
    m_animations.tick(static_cast<float>(kTransitionTick.count()));
  }

} // namespace noctalia::theme
