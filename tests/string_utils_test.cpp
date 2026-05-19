#include "util/string_utils.h"

#include <cstdio>
#include <string_view>

namespace {

  bool expectEqual(std::string_view actual, std::string_view expected, const char* message) {
    if (actual != expected) {
      std::fprintf(stderr, "string_utils_test: %s: expected '%.*s', got '%.*s'\n", message,
                   static_cast<int>(expected.size()), expected.data(), static_cast<int>(actual.size()), actual.data());
      return false;
    }
    return true;
  }

} // namespace

int main() {
  bool ok = true;
  ok = expectEqual(StringUtils::urlEncode("abc-_.~09AZaz"), "abc-_.~09AZaz", "keeps unreserved characters") && ok;
  ok = expectEqual(StringUtils::urlEncode("hello world"), "hello%20world", "encodes spaces as percent escapes") && ok;
  ok = expectEqual(StringUtils::urlEncode("dir/file?x=1&y=%"), "dir%2Ffile%3Fx%3D1%26y%3D%25",
                   "encodes reserved URL characters") &&
       ok;
  ok = expectEqual(StringUtils::urlEncode("\xC3\xA9"), "%C3%A9", "encodes non-ASCII bytes") && ok;
  return ok ? 0 : 1;
}
