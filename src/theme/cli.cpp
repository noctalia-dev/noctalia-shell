#include "theme/cli.h"

#include "core/resource_paths.h"
#include "core/toml.h"
#include "theme/color.h"
#include "theme/fixed_palette.h"
#include "theme/image_loader.h"
#include "theme/json_output.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"
#include "theme/template_engine.h"
#include "util/file_utils.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <json.hpp>
#include <optional>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

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
                                      "  --builtin-config  Process the shipped built-in template catalog\n"
                                      "  --list-builtins   List built-in templates from the shipped catalog\n"
                                      "  --default-mode    Template default mode: dark or light";

    std::filesystem::path builtinTemplateConfigPath() { return paths::assetPath("templates/builtin.toml"); }

    struct BuiltinTemplateInfo {
      std::string id;
      std::string name;
      std::string category;
    };

    std::vector<BuiltinTemplateInfo> loadBuiltinTemplateInfo(std::string& err) {
      toml::table root;
      try {
        root = toml::parse_file(builtinTemplateConfigPath().string());
      } catch (const toml::parse_error& e) {
        err = e.description();
        return {};
      }

      std::vector<BuiltinTemplateInfo> out;
      const toml::table* catalog = root["catalog"].as_table();
      if (catalog == nullptr)
        return out;

      for (const auto& [idNode, node] : *catalog) {
        const toml::table* info = node.as_table();
        if (info == nullptr)
          continue;
        BuiltinTemplateInfo entry;
        entry.id = std::string(idNode.str());
        if (const auto name = info->get_as<std::string>("name"))
          entry.name = name->get();
        if (const auto category = info->get_as<std::string>("category"))
          entry.category = category->get();
        out.push_back(std::move(entry));
      }

      std::sort(out.begin(), out.end(), [](const BuiltinTemplateInfo& lhs, const BuiltinTemplateInfo& rhs) {
        if (lhs.category != rhs.category)
          return lhs.category < rhs.category;
        return lhs.id < rhs.id;
      });
      return out;
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

    void setToken(TokenMap& dst, std::string_view key, std::string_view hex) {
      dst[std::string(key)] = Color::fromHex(hex).toArgb();
    }

    std::optional<::Palette> parseFixedPaletteJson(const nlohmann::json& src, std::string& err) {
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

      if (!primary || !onPrimary || !secondary || !onSecondary || !tertiary || !onTertiary || !error || !onError ||
          !surface || !onSurface || !surfaceVariant || !onSurfaceVariant || !outlineRaw) {
        err = "fixed palette json is missing required colors";
        return std::nullopt;
      }
      return ::Palette{
          .primary = rgbHex(primary->toArgb() & 0x00FFFFFFU),
          .onPrimary = rgbHex(onPrimary->toArgb() & 0x00FFFFFFU),
          .secondary = rgbHex(secondary->toArgb() & 0x00FFFFFFU),
          .onSecondary = rgbHex(onSecondary->toArgb() & 0x00FFFFFFU),
          .tertiary = rgbHex(tertiary->toArgb() & 0x00FFFFFFU),
          .onTertiary = rgbHex(onTertiary->toArgb() & 0x00FFFFFFU),
          .error = rgbHex(error->toArgb() & 0x00FFFFFFU),
          .onError = rgbHex(onError->toArgb() & 0x00FFFFFFU),
          .surface = rgbHex(surface->toArgb() & 0x00FFFFFFU),
          .onSurface = rgbHex(onSurface->toArgb() & 0x00FFFFFFU),
          .surfaceVariant = rgbHex(surfaceVariant->toArgb() & 0x00FFFFFFU),
          .onSurfaceVariant = rgbHex(onSurfaceVariant->toArgb() & 0x00FFFFFFU),
          .outline = rgbHex(outlineRaw->toArgb() & 0x00FFFFFFU),
          .shadow = rgbHex(shadow.toArgb() & 0x00FFFFFFU),
          .hover = rgbHex(tertiary->toArgb() & 0x00FFFFFFU),
          .onHover = rgbHex(onTertiary->toArgb() & 0x00FFFFFFU),
      };
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

      auto loadFixedPalette = [&](const nlohmann::json& src, std::string_view mode, TokenMap& dst) -> bool {
        auto parsed = parseFixedPaletteJson(src, err);
        if (!parsed)
          return false;
        dst = expandFixedPaletteMode(*parsed, mode == "dark");
        injectTerminalColors(dst, src);
        return true;
      };

      auto isFixedPaletteMode = [](const nlohmann::json& src) { return src.is_object() && src.contains("mPrimary"); };

      if (root.contains("dark") || root.contains("light")) {
        if (root.contains("dark")) {
          if (isFixedPaletteMode(root["dark"])) {
            if (!loadFixedPalette(root["dark"], "dark", palette.dark))
              return false;
          } else {
            loadTokenMode(root["dark"], palette.dark);
          }
        }
        if (root.contains("light")) {
          if (isFixedPaletteMode(root["light"])) {
            if (!loadFixedPalette(root["light"], "light", palette.light))
              return false;
          } else {
            loadTokenMode(root["light"], palette.light);
          }
        }
      } else if (isFixedPaletteMode(root)) {
        if (!loadFixedPalette(root, "dark", palette.dark) || !loadFixedPalette(root, "light", palette.light))
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
    std::string builtinConfigPathStorage;
    bool builtinConfig = false;
    bool listBuiltins = false;
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
      if (std::strcmp(a, "--builtin-config") == 0) {
        builtinConfig = true;
        continue;
      }
      if (std::strcmp(a, "--list-builtins") == 0) {
        listBuiltins = true;
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

    if (listBuiltins) {
      std::string err;
      const auto builtins = loadBuiltinTemplateInfo(err);
      if (!err.empty()) {
        std::fprintf(stderr, "error: failed to load built-in templates: %s\n", err.c_str());
        return 1;
      }
      for (const auto& builtin : builtins) {
        if (builtin.category.empty())
          std::printf("%s\t%s\n", builtin.id.c_str(), builtin.name.c_str());
        else
          std::printf("%s\t%s\t%s\n", builtin.id.c_str(), builtin.category.c_str(), builtin.name.c_str());
      }
      return 0;
    }

    if (builtinConfig) {
      if (configPath != nullptr) {
        std::fputs("error: --builtin-config cannot be combined with --config\n", stderr);
        return 1;
      }
      builtinConfigPathStorage = builtinTemplateConfigPath().string();
      configPath = builtinConfigPathStorage.c_str();
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
      if (!loadThemeJson(FileUtils::expandUserPath(themeJsonPath), palette, err)) {
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
        const std::filesystem::path input = FileUtils::expandUserPath(spec.substr(0, colon));
        const std::filesystem::path output = FileUtils::expandUserPath(spec.substr(colon + 1));
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
