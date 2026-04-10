#include "theme/cli.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>

#include "theme/image_loader.h"
#include "theme/json_output.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"

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
                                      "  -o <file>         Write JSON to file instead of stdout";

  } // namespace

  int runCli(int argc, char* argv[]) {
    const char* imagePath = nullptr;
    std::string schemeName = "m3-tonal-spot";
    Variant variant = Variant::Dark;
    const char* outPath = nullptr;

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
      if (!imagePath && a[0] != '-') {
        imagePath = a;
        continue;
      }
      std::fprintf(stderr, "error: unknown theme argument: %s\n", a);
      return 1;
    }

    if (!imagePath) {
      std::fputs("error: theme requires an image path (try: noctalia theme --help)\n", stderr);
      return 1;
    }

    auto schemeOpt = schemeFromString(schemeName);
    if (!schemeOpt) {
      std::fprintf(stderr, "error: unknown scheme '%s'\n", schemeName.c_str());
      return 1;
    }

    std::string err;
    auto loaded = loadAndResize(imagePath, *schemeOpt, &err);
    if (!loaded) {
      std::fprintf(stderr, "error: failed to load image: %s\n", err.c_str());
      return 1;
    }

    auto palette = generate(loaded->rgb, *schemeOpt, &err);
    if (palette.dark.empty() && palette.light.empty()) {
      std::fprintf(stderr, "error: palette generation failed: %s\n", err.empty() ? "unknown error" : err.c_str());
      return 1;
    }

    const std::string json = toJson(palette, *schemeOpt, variant);
    if (outPath) {
      std::ofstream f(outPath);
      if (!f) {
        std::fprintf(stderr, "error: cannot open output file: %s\n", outPath);
        return 1;
      }
      f << json << '\n';
    } else {
      std::fwrite(json.data(), 1, json.size(), stdout);
      std::fputc('\n', stdout);
    }
    return 0;
  }

} // namespace noctalia::theme
