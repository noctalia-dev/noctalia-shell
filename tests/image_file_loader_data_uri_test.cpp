#include "render/core/image_file_loader.h"

#include <cstdio>
#include <string>

namespace {

  bool check(bool condition, const char* message) {
    if (!condition) {
      std::fprintf(stderr, "image_file_loader_data_uri_test: %s\n", message);
    }
    return condition;
  }

} // namespace

int main() {
  bool ok = true;

  // A 1x1 PNG deliberately declared as image/jpeg. The loader should trust the
  // decoded bytes, not the data URI media type.
  const std::string mismatchedDataUri =
      "data:image/jpeg;base64,"
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=";

  std::string error;
  auto image = loadImageFile(mismatchedDataUri, 0, &error);
  ok = check(image.has_value(), error.empty() ? "failed to decode mismatched data URI" : error.c_str()) && ok;
  if (image.has_value()) {
    ok = check(image->width == 1, "decoded data URI width should be 1") && ok;
    ok = check(image->height == 1, "decoded data URI height should be 1") && ok;
    ok = check(image->rgba.size() == 4, "decoded data URI should contain one RGBA pixel") && ok;
  }

  const std::string pngDeclaredJpegDataUri =
      "data:image/png;base64,"
      "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8Q"
      "EBEQCgwSExIQEw8QEBD/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQ"
      "EAAD8AVN//2Q==";

  error.clear();
  image = loadImageFile(pngDeclaredJpegDataUri, 0, &error);
  ok = check(image.has_value(), error.empty() ? "failed to decode PNG-declared JPEG data URI" : error.c_str()) && ok;
  if (image.has_value()) {
    ok = check(image->width == 1, "decoded JPEG data URI width should be 1") && ok;
    ok = check(image->height == 1, "decoded JPEG data URI height should be 1") && ok;
    ok = check(image->rgba.size() == 4, "decoded JPEG data URI should contain one RGBA pixel") && ok;
  }

  error.clear();
  image = loadImageFile("data:image/png;base64,not_base64!", 0, &error);
  ok = check(!image.has_value(), "invalid base64 data URI should fail") && ok;
  ok = check(error.find("base64") != std::string::npos, "invalid base64 failure should explain the data issue") && ok;

  error.clear();
  image = loadImageFile("data:image/png;base64", 0, &error);
  ok = check(!image.has_value(), "data URI without comma should fail") && ok;
  ok = check(error.find("separator") != std::string::npos, "missing comma failure should mention separator") && ok;

  return ok ? 0 : 1;
}
