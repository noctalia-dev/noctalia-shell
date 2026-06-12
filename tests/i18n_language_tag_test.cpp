#include "i18n/language_tag.h"

#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace {

  bool expectEqual(std::string_view actual, std::string_view expected, const char* message) {
    if (actual != expected) {
      std::fprintf(
          stderr, "i18n_language_tag_test: %s: expected '%.*s', got '%.*s'\n", message,
          static_cast<int>(expected.size()), expected.data(), static_cast<int>(actual.size()), actual.data()
      );
      return false;
    }
    return true;
  }

  bool expectCandidates(std::string_view raw, const std::vector<std::string>& expected, const char* message) {
    const std::vector<std::string> actual = i18n::detail::catalogLanguageCandidates(raw);
    if (actual == expected) {
      return true;
    }

    std::fprintf(
        stderr, "i18n_language_tag_test: %s: candidates for '%.*s' differed\n", message, static_cast<int>(raw.size()),
        raw.data()
    );
    std::fprintf(stderr, "  expected:");
    for (const auto& candidate : expected) {
      std::fprintf(stderr, " %s", candidate.c_str());
    }
    std::fprintf(stderr, "\n  actual:");
    for (const auto& candidate : actual) {
      std::fprintf(stderr, " %s", candidate.c_str());
    }
    std::fprintf(stderr, "\n");
    return false;
  }

} // namespace

int main() {
  bool ok = true;

  ok = expectEqual(i18n::detail::normalizeLanguageTag("zh_CN.UTF-8"), "zh-CN", "normalizes POSIX locale") && ok;
  ok = expectEqual(i18n::detail::normalizeLanguageTag("pt-br"), "pt-BR", "canonicalizes region case") && ok;
  ok = expectEqual(i18n::detail::normalizeLanguageTag("zh_hans_cn"), "zh-Hans-CN", "canonicalizes script case") && ok;
  ok = expectEqual(i18n::detail::normalizeLanguageTag("C.UTF-8"), "", "ignores C locale") && ok;

  ok = expectCandidates("zh_CN.UTF-8", {"zh-Hans-CN", "zh-CN", "zh-Hans", "zh"}, "infers Simplified Chinese from China")
      && ok;
  ok = expectCandidates("zh_TW", {"zh-Hant-TW", "zh-TW", "zh-Hant", "zh"}, "infers Traditional Chinese from Taiwan")
      && ok;
  ok = expectCandidates("zh-Hans-CN", {"zh-Hans-CN", "zh-CN", "zh-Hans", "zh"}, "keeps explicit Chinese script first")
      && ok;
  ok = expectCandidates("pt_BR.UTF-8", {"pt-BR", "pt"}, "uses generic language fallback for regional locale") && ok;
  ok = expectCandidates("en_US", {"en-US", "en"}, "does not infer scripts for non-Chinese locales") && ok;
  ok = expectCandidates("C.UTF-8", {}, "does not build candidates for the C locale") && ok;

  return ok ? 0 : 1;
}
