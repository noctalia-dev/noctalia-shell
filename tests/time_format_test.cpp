#include "time/time_format.h"

#include <cstdio>
#include <string_view>

namespace {

  bool expectEqual(std::string_view actual, std::string_view expected, const char* message) {
    if (actual != expected) {
      std::fprintf(
          stderr, "time_format_test: %s: expected '%.*s', got '%.*s'\n", message, static_cast<int>(expected.size()),
          expected.data(), static_cast<int>(actual.size()), actual.data()
      );
      return false;
    }
    return true;
  }

} // namespace

int main() {
  bool ok = true;
  ok = expectEqual(formatLocalUnixTime(1700000000, "%s"), "1700000000", "formats unix epoch token") && ok;
  ok = expectEqual(
           formatLocalUnixTime(1700000000, "recording_%s"), "recording_1700000000",
           "formats epoch inside filename pattern"
       )
      && ok;
  ok = expectEqual(formatLocalUnixTime(1700000000, "%%s_%s"), "%s_1700000000", "keeps escaped percent literal") && ok;
  return ok ? 0 : 1;
}
