#include "theme/cli.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

#include <json.hpp>

#include "theme/color.h"
#include "theme/contrast.h"
#include "theme/image_loader.h"
#include "theme/json_output.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"
#include "theme/template_engine.h"

namespace noctalia::theme {

  namespace {

    constexpr const char* kHelpText = "Usage: noctalia theme <image> [options]\n"
                                      "\n"
                                      "Generate a color palette from an image. Material You and custom\n"
                                      "schemes produce very different results.\n"
                                      "\n"
                                      "Options:\n"
                                      "  --scheme <name>   Material You (Material Design 3):\n"
                                      "                      m3-tonal-spot  (default)\n"
                                      "                      m3-content\n"
                                      "                      m3-fruit-salad\n"
                                      "                      m3-rainbow\n"
                                      "                      m3-monochrome\n"
                                      "                    Custom (HSL-space, non-M3):\n"
                                      "                      vibrant\n"
                                      "                      faithful\n"
                                      "                      dysfunctional\n"
                                      "                      muted\n"
                                      "  --dark            Emit only the dark variant (default)\n"
                                      "  --light           Emit only the light variant\n"
                                      "  --both            Emit both variants under dark/light keys\n"
                                      "  --theme-json <f>  Load precomputed dark/light token maps from JSON\n"
                                      "  -o <file>         Write JSON to file instead of stdout\n"
                                      "  -r <in:out>       Render a template file to an output path\n"
                                      "  -c <file>         Process a TOML template config file\n"
                                      "  --default-mode    Template default mode: dark or light";

    std::filesystem::path expandUserPath(const std::string& path) {
      if (path.empty() || path[0] != '~')
        return std::filesystem::path(path);
      const char* home = std::getenv("HOME");
      if (home == nullptr || home[0] == '\0')
        return std::filesystem::path(path);
      if (path.size() == 1)
        return std::filesystem::path(home);
      if (path[1] == '/')
        return std::filesystem::path(home) / path.substr(2);
      return std::filesystem::path(path);
    }

    using TokenMap = std::unordered_map<std::string, uint32_t>;

    std::optional<Color> loadHexColor(const nlohmann::json& src, const char* key) {
      if (!src.contains(key) || !src[key].is_string())
        return std::nullopt;
      try {
        return Color::fromHex(src[key].get<std::string>());
      } catch (...) {
        return std::nullopt;
      }
    }

    Color interpolateColor(const Color& a, const Color& b, double t) {
      auto mix = [t](int lhs, int rhs) { return static_cast<int>(lhs + (rhs - lhs) * t); };
      return Color(mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b));
    }

    void setToken(TokenMap& dst, std::string_view key, const Color& color) { dst[std::string(key)] = color.toArgb(); }

    void setToken(TokenMap& dst, std::string_view key, std::string_view hex) {
      dst[std::string(key)] = Color::fromHex(hex).toArgb();
    }

    std::optional<TokenMap> expandPredefinedMode(const nlohmann::json& src, std::string_view mode, std::string& err) {
      const auto primary = loadHexColor(src, "mPrimary");
      const auto onPrimary = loadHexColor(src, "mOnPrimary");
      const auto secondary = loadHexColor(src, "mSecondary");
      const auto onSecondary = loadHexColor(src, "mOnSecondary");
      const auto tertiary = loadHexColor(src, "mTertiary");
      const auto onTertiary = loadHexColor(src, "mOnTertiary");
      const auto error = loadHexColor(src, "mError");
      const auto onError = loadHexColor(src, "mOnError");
      const auto surface = loadHexColor(src, "mSurface");
      const auto onSurface = loadHexColor(src, "mOnSurface");
      const auto surfaceVariant = loadHexColor(src, "mSurfaceVariant");
      const auto onSurfaceVariant = loadHexColor(src, "mOnSurfaceVariant");
      const auto outlineRaw = loadHexColor(src, "mOutline");
      const auto shadow = loadHexColor(src, "mShadow").value_or(surface.value_or(Color{}));
      const bool isDark = mode == "dark";

      if (!primary || !onPrimary || !secondary || !onSecondary || !tertiary || !onTertiary || !error || !onError ||
          !surface || !onSurface || !surfaceVariant || !onSurfaceVariant || !outlineRaw) {
        err = "predefined scheme is missing required colors";
        return std::nullopt;
      }

      auto makeContainerDark = [](const Color& base) {
        auto [h, s, l] = base.toHsl();
        return Color::fromHsl(h, std::min(s + 0.15, 1.0), std::max(l - 0.35, 0.15));
      };
      auto makeContainerLight = [](const Color& base) {
        auto [h, s, l] = base.toHsl();
        return Color::fromHsl(h, std::max(s - 0.20, 0.30), std::min(l + 0.35, 0.85));
      };
      auto makeFixedDark = [](const Color& base) {
        auto [h, s, _] = base.toHsl();
        return std::make_tuple(Color::fromHsl(h, std::max(s, 0.70), 0.85), Color::fromHsl(h, std::max(s, 0.65), 0.75));
      };
      auto makeFixedLight = [](const Color& base) {
        auto [h, s, _] = base.toHsl();
        return std::make_tuple(Color::fromHsl(h, std::max(s, 0.70), 0.40), Color::fromHsl(h, std::max(s, 0.65), 0.30));
      };

      const Color primaryContainer = isDark ? makeContainerDark(*primary) : makeContainerLight(*primary);
      const Color secondaryContainer = isDark ? makeContainerDark(*secondary) : makeContainerLight(*secondary);
      const Color tertiaryContainer = isDark ? makeContainerDark(*tertiary) : makeContainerLight(*tertiary);
      const Color errorContainer = isDark ? makeContainerDark(*error) : makeContainerLight(*error);

      const auto [primaryH, primaryS, _primaryL] = primary->toHsl();
      const auto [secondaryH, secondaryS, _secondaryL] = secondary->toHsl();
      const auto [tertiaryH, tertiaryS, _tertiaryL] = tertiary->toHsl();
      const auto [errorH, errorS, _errorL] = error->toHsl();

      const Color onPrimaryContainer =
          isDark ? ensureContrast(Color::fromHsl(primaryH, primaryS, 0.90), primaryContainer, 4.5)
                 : ensureContrast(Color::fromHsl(primaryH, primaryS, 0.15), primaryContainer, 4.5);
      const Color onSecondaryContainer =
          isDark ? ensureContrast(Color::fromHsl(secondaryH, secondaryS, 0.90), secondaryContainer, 4.5)
                 : ensureContrast(Color::fromHsl(secondaryH, secondaryS, 0.15), secondaryContainer, 4.5);
      const Color onTertiaryContainer =
          isDark ? ensureContrast(Color::fromHsl(tertiaryH, tertiaryS, 0.90), tertiaryContainer, 4.5)
                 : ensureContrast(Color::fromHsl(tertiaryH, tertiaryS, 0.15), tertiaryContainer, 4.5);
      const Color onErrorContainer = isDark ? ensureContrast(Color::fromHsl(errorH, errorS, 0.90), errorContainer, 4.5)
                                            : ensureContrast(Color::fromHsl(errorH, errorS, 0.15), errorContainer, 4.5);

      const auto [primaryFixed, primaryFixedDim] = isDark ? makeFixedDark(*primary) : makeFixedLight(*primary);
      const auto [secondaryFixed, secondaryFixedDim] = isDark ? makeFixedDark(*secondary) : makeFixedLight(*secondary);
      const auto [tertiaryFixed, tertiaryFixedDim] = isDark ? makeFixedDark(*tertiary) : makeFixedLight(*tertiary);

      const Color onPrimaryFixed = isDark ? ensureContrast(Color::fromHsl(primaryH, 0.15, 0.15), primaryFixed, 4.5)
                                          : ensureContrast(Color::fromHsl(primaryH, 0.15, 0.90), primaryFixed, 4.5);
      const Color onPrimaryFixedVariant =
          isDark ? ensureContrast(Color::fromHsl(primaryH, 0.15, 0.20), primaryFixedDim, 4.5)
                 : ensureContrast(Color::fromHsl(primaryH, 0.15, 0.85), primaryFixedDim, 4.5);
      const Color onSecondaryFixed = isDark
                                         ? ensureContrast(Color::fromHsl(secondaryH, 0.15, 0.15), secondaryFixed, 4.5)
                                         : ensureContrast(Color::fromHsl(secondaryH, 0.15, 0.90), secondaryFixed, 4.5);
      const Color onSecondaryFixedVariant =
          isDark ? ensureContrast(Color::fromHsl(secondaryH, 0.15, 0.20), secondaryFixedDim, 4.5)
                 : ensureContrast(Color::fromHsl(secondaryH, 0.15, 0.85), secondaryFixedDim, 4.5);
      const Color onTertiaryFixed = isDark ? ensureContrast(Color::fromHsl(tertiaryH, 0.15, 0.15), tertiaryFixed, 4.5)
                                           : ensureContrast(Color::fromHsl(tertiaryH, 0.15, 0.90), tertiaryFixed, 4.5);
      const Color onTertiaryFixedVariant =
          isDark ? ensureContrast(Color::fromHsl(tertiaryH, 0.15, 0.20), tertiaryFixedDim, 4.5)
                 : ensureContrast(Color::fromHsl(tertiaryH, 0.15, 0.85), tertiaryFixedDim, 4.5);

      const auto [surfaceH, surfaceS, surfaceL] = surface->toHsl();
      const auto [surfaceVariantH, surfaceVariantS, surfaceVariantL] = surfaceVariant->toHsl();
      const Color surfaceContainer = *surfaceVariant;
      const Color surfaceContainerLowest = interpolateColor(*surface, *surfaceVariant, 0.2);
      const Color surfaceContainerLow = interpolateColor(*surface, *surfaceVariant, 0.5);
      const Color surfaceContainerHigh =
          isDark ? Color::fromHsl(surfaceVariantH, surfaceVariantS, std::min(surfaceVariantL + 0.04, 0.40))
                 : Color::fromHsl(surfaceVariantH, surfaceVariantS, std::max(surfaceVariantL - 0.04, 0.60));
      const Color surfaceContainerHighest =
          isDark ? Color::fromHsl(surfaceVariantH, surfaceVariantS, std::min(surfaceVariantL + 0.08, 0.45))
                 : Color::fromHsl(surfaceVariantH, surfaceVariantS, std::max(surfaceVariantL - 0.08, 0.55));
      const Color surfaceDim =
          isDark ? Color::fromHsl(surfaceH, surfaceS, std::max(surfaceL - 0.04, 0.02))
                 : Color::fromHsl(surfaceVariantH, surfaceVariantS, std::max(surfaceVariantL - 0.12, 0.50));
      const Color surfaceBright =
          isDark ? Color::fromHsl(surfaceVariantH, surfaceVariantS, std::min(surfaceVariantL + 0.12, 0.50))
                 : Color::fromHsl(surfaceH, surfaceS, std::min(surfaceL + 0.03, 0.98));

      const Color outline = ensureContrast(*outlineRaw, *surface, 3.0);
      const auto [outlineH, outlineS, outlineL] = outline.toHsl();
      const Color outlineVariant = isDark ? Color::fromHsl(outlineH, outlineS, std::max(outlineL - 0.15, 0.1))
                                          : Color::fromHsl(outlineH, outlineS, std::min(outlineL + 0.15, 0.9));
      const Color scrim(0, 0, 0);
      const Color inverseSurface = isDark ? Color::fromHsl(surfaceH, 0.08, 0.90) : Color::fromHsl(surfaceH, 0.08, 0.15);
      const Color inverseOnSurface =
          isDark ? Color::fromHsl(surfaceH, 0.05, 0.15) : Color::fromHsl(surfaceH, 0.05, 0.90);
      const Color inversePrimary = isDark ? Color::fromHsl(primaryH, std::max(primaryS * 0.8, 0.5), 0.40)
                                          : Color::fromHsl(primaryH, std::max(primaryS * 0.8, 0.5), 0.70);
      const Color background = *surface;
      const Color onBackground = *onSurface;

      TokenMap result;
      setToken(result, "primary", *primary);
      setToken(result, "on_primary", *onPrimary);
      setToken(result, "primary_container", primaryContainer);
      setToken(result, "on_primary_container", onPrimaryContainer);
      setToken(result, "primary_fixed", primaryFixed);
      setToken(result, "primary_fixed_dim", primaryFixedDim);
      setToken(result, "on_primary_fixed", onPrimaryFixed);
      setToken(result, "on_primary_fixed_variant", onPrimaryFixedVariant);
      setToken(result, "secondary", *secondary);
      setToken(result, "on_secondary", *onSecondary);
      setToken(result, "secondary_container", secondaryContainer);
      setToken(result, "on_secondary_container", onSecondaryContainer);
      setToken(result, "secondary_fixed", secondaryFixed);
      setToken(result, "secondary_fixed_dim", secondaryFixedDim);
      setToken(result, "on_secondary_fixed", onSecondaryFixed);
      setToken(result, "on_secondary_fixed_variant", onSecondaryFixedVariant);
      setToken(result, "tertiary", *tertiary);
      setToken(result, "on_tertiary", *onTertiary);
      setToken(result, "tertiary_container", tertiaryContainer);
      setToken(result, "on_tertiary_container", onTertiaryContainer);
      setToken(result, "tertiary_fixed", tertiaryFixed);
      setToken(result, "tertiary_fixed_dim", tertiaryFixedDim);
      setToken(result, "on_tertiary_fixed", onTertiaryFixed);
      setToken(result, "on_tertiary_fixed_variant", onTertiaryFixedVariant);
      setToken(result, "error", *error);
      setToken(result, "on_error", *onError);
      setToken(result, "error_container", errorContainer);
      setToken(result, "on_error_container", onErrorContainer);
      setToken(result, "surface", *surface);
      setToken(result, "on_surface", *onSurface);
      setToken(result, "surface_variant", *surfaceVariant);
      setToken(result, "on_surface_variant", *onSurfaceVariant);
      setToken(result, "surface_container_lowest", surfaceContainerLowest);
      setToken(result, "surface_container_low", surfaceContainerLow);
      setToken(result, "surface_container", surfaceContainer);
      setToken(result, "surface_container_high", surfaceContainerHigh);
      setToken(result, "surface_container_highest", surfaceContainerHighest);
      setToken(result, "surface_dim", surfaceDim);
      setToken(result, "surface_bright", surfaceBright);
      setToken(result, "surface_tint", *primary);
      setToken(result, "outline", outline);
      setToken(result, "outline_variant", outlineVariant);
      setToken(result, "shadow", shadow);
      setToken(result, "scrim", scrim);
      setToken(result, "inverse_surface", inverseSurface);
      setToken(result, "inverse_on_surface", inverseOnSurface);
      setToken(result, "inverse_primary", inversePrimary);
      setToken(result, "background", background);
      setToken(result, "on_background", onBackground);
      return result;
    }

    void injectTerminalColors(TokenMap& dst, const nlohmann::json& modeJson) {
      if (!modeJson.contains("terminal") || !modeJson["terminal"].is_object())
        return;
      const auto& terminal = modeJson["terminal"];
      static constexpr std::pair<const char*, const char*> directKeys[] = {
          {"foreground", "terminal_foreground"},
          {"background", "terminal_background"},
          {"cursor", "terminal_cursor"},
          {"cursorText", "terminal_cursor_text"},
          {"selectionFg", "terminal_selection_fg"},
          {"selectionBg", "terminal_selection_bg"},
      };
      for (const auto& [jsonKey, flatKey] : directKeys) {
        if (terminal.contains(jsonKey) && terminal[jsonKey].is_string())
          setToken(dst, flatKey, terminal[jsonKey].get<std::string>());
      }
      for (const char* group : {"normal", "bright"}) {
        if (!terminal.contains(group) || !terminal[group].is_object())
          continue;
        for (auto it = terminal[group].begin(); it != terminal[group].end(); ++it) {
          if (!it.value().is_string())
            continue;
          setToken(dst, std::string("terminal_") + group + "_" + it.key(), it.value().get<std::string>());
        }
      }
    }

    bool loadThemeJson(const std::filesystem::path& path, GeneratedPalette& palette, std::string& err) {
      std::ifstream f(path);
      if (!f) {
        err = "cannot open theme json";
        return false;
      }

      nlohmann::json root;
      try {
        f >> root;
      } catch (const std::exception& e) {
        err = e.what();
        return false;
      }

      auto loadTokenMode = [](const nlohmann::json& src, TokenMap& dst) {
        if (!src.is_object())
          return;
        for (auto it = src.begin(); it != src.end(); ++it) {
          if (!it.value().is_string())
            continue;
          try {
            dst[it.key()] = Color::fromHex(it.value().get<std::string>()).toArgb();
          } catch (...) {
          }
        }
      };

      auto loadPredefined = [&](const nlohmann::json& src, std::string_view mode, TokenMap& dst) -> bool {
        auto expanded = expandPredefinedMode(src, mode, err);
        if (!expanded)
          return false;
        dst = std::move(*expanded);
        injectTerminalColors(dst, src);
        return true;
      };

      auto isPredefinedMode = [](const nlohmann::json& src) { return src.is_object() && src.contains("mPrimary"); };

      if (root.contains("dark") || root.contains("light")) {
        if (root.contains("dark")) {
          if (isPredefinedMode(root["dark"])) {
            if (!loadPredefined(root["dark"], "dark", palette.dark))
              return false;
          } else {
            loadTokenMode(root["dark"], palette.dark);
          }
        }
        if (root.contains("light")) {
          if (isPredefinedMode(root["light"])) {
            if (!loadPredefined(root["light"], "light", palette.light))
              return false;
          } else {
            loadTokenMode(root["light"], palette.light);
          }
        }
      } else if (isPredefinedMode(root)) {
        if (!loadPredefined(root, "dark", palette.dark) || !loadPredefined(root, "light", palette.light))
          return false;
      } else {
        loadTokenMode(root, palette.dark);
      }

      if (palette.dark.empty() && palette.light.empty()) {
        err = "theme json contained no token maps";
        return false;
      }
      return true;
    }

  } // namespace

  int runCli(int argc, char* argv[]) {
    const char* imagePath = nullptr;
    const char* themeJsonPath = nullptr;
    std::string schemeName = "m3-tonal-spot";
    Variant variant = Variant::Dark;
    const char* outPath = nullptr;
    const char* configPath = nullptr;
    std::string defaultMode = "dark";
    std::vector<std::string> renderSpecs;

    for (int i = 2; i < argc; ++i) {
      const char* a = argv[i];
      if (std::strcmp(a, "--help") == 0) {
        std::puts(kHelpText);
        return 0;
      }
      if (std::strcmp(a, "--scheme") == 0 && i + 1 < argc) {
        schemeName = argv[++i];
        continue;
      }
      if (std::strcmp(a, "--theme-json") == 0 && i + 1 < argc) {
        themeJsonPath = argv[++i];
        continue;
      }
      if (std::strcmp(a, "--dark") == 0) {
        variant = Variant::Dark;
        continue;
      }
      if (std::strcmp(a, "--light") == 0) {
        variant = Variant::Light;
        continue;
      }
      if (std::strcmp(a, "--both") == 0) {
        variant = Variant::Both;
        continue;
      }
      if (std::strcmp(a, "-o") == 0 && i + 1 < argc) {
        outPath = argv[++i];
        continue;
      }
      if ((std::strcmp(a, "--render") == 0 || std::strcmp(a, "-r") == 0) && i + 1 < argc) {
        renderSpecs.emplace_back(argv[++i]);
        continue;
      }
      if ((std::strcmp(a, "--config") == 0 || std::strcmp(a, "-c") == 0) && i + 1 < argc) {
        configPath = argv[++i];
        continue;
      }
      if (std::strcmp(a, "--default-mode") == 0 && i + 1 < argc) {
        defaultMode = argv[++i];
        continue;
      }
      if (!imagePath && a[0] != '-') {
        imagePath = a;
        continue;
      }
      std::fprintf(stderr, "error: unknown theme argument: %s\n", a);
      return 1;
    }

    if (!imagePath && !themeJsonPath) {
      std::fputs("error: theme requires an image path or --theme-json (try: noctalia theme --help)\n", stderr);
      return 1;
    }

    auto schemeOpt = schemeFromString(schemeName);
    if (!schemeOpt) {
      std::fprintf(stderr, "error: unknown scheme '%s'\n", schemeName.c_str());
      return 1;
    }

    std::string err;
    GeneratedPalette palette;
    if (themeJsonPath) {
      if (!loadThemeJson(expandUserPath(themeJsonPath), palette, err)) {
        std::fprintf(stderr, "error: failed to load theme json: %s\n", err.c_str());
        return 1;
      }
    } else {
      auto loaded = loadAndResize(imagePath, *schemeOpt, &err);
      if (!loaded) {
        std::fprintf(stderr, "error: failed to load image: %s\n", err.c_str());
        return 1;
      }

      palette = generate(loaded->rgb, *schemeOpt, &err);
      if (palette.dark.empty() && palette.light.empty()) {
        std::fprintf(stderr, "error: palette generation failed: %s\n", err.empty() ? "unknown error" : err.c_str());
        return 1;
      }
    }

    const std::string json = toJson(palette, *schemeOpt, variant);
    const bool hasTemplateWork = !renderSpecs.empty() || configPath != nullptr;
    if (outPath) {
      std::ofstream f(outPath);
      if (!f) {
        std::fprintf(stderr, "error: cannot open output file: %s\n", outPath);
        return 1;
      }
      f << json << '\n';
    } else if (!hasTemplateWork) {
      std::fwrite(json.data(), 1, json.size(), stdout);
      std::fputc('\n', stdout);
    }

    if (hasTemplateWork) {
      TemplateEngine::Options options;
      options.defaultMode = defaultMode;
      options.imagePath = imagePath ? imagePath : "";
      options.closestColor.clear();
      options.schemeType = schemeName.rfind("m3-", 0) == 0 ? schemeName.substr(3) : schemeName;
      options.verbose = true;
      TemplateEngine engine(TemplateEngine::makeThemeData(palette), std::move(options));

      for (const auto& spec : renderSpecs) {
        const size_t colon = spec.find(':');
        if (colon == std::string::npos) {
          std::fprintf(stderr, "error: invalid render spec (expected input:output): %s\n", spec.c_str());
          return 1;
        }
        const std::filesystem::path input = expandUserPath(spec.substr(0, colon));
        const std::filesystem::path output = expandUserPath(spec.substr(colon + 1));
        const auto result = engine.renderFile(input, output);
        if (!result.success)
          return 1;
      }

      if (configPath && !engine.processConfigFile(configPath))
        return 1;
    }

    return 0;
  }

} // namespace noctalia::theme
