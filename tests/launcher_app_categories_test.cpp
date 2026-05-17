#include "launcher/app_categories.h"

#include <iostream>
#include <string>
#include <vector>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

  DesktopEntry entryWithCategories(std::string categories) {
    DesktopEntry entry;
    entry.name = "Example";
    entry.categories = std::move(categories);
    return entry;
  }

  class CategoryAwareProvider final : public LauncherProvider {
  public:
    [[nodiscard]] std::string_view prefix() const override { return ""; }
    [[nodiscard]] std::string_view name() const override { return "category-aware"; }
    [[nodiscard]] std::vector<LauncherResult> query(std::string_view /*text*/,
                                                    std::string_view category = {}) const override {
      LauncherResult result;
      result.id = std::string(category);
      return {result};
    }
    bool activate(const LauncherResult& /*result*/) override { return false; }
  };

} // namespace

int main() {
  bool ok = true;

  const std::vector<DesktopEntry> entries = {
      entryWithCategories("Development;IDE;"),
      entryWithCategories("Audio;Player;"),
      entryWithCategories("Science;"),
      entryWithCategories(""),
  };

  const auto categories = availableLauncherAppCategories(entries);

  ok &= check(!categories.empty(), "available categories should include the provider default category");
  ok &= check(categories.front().id == LauncherAppCategories::All, "first category should be all");

  bool foundDevelopment = false;
  bool foundAudioVideo = false;
  bool foundEducation = false;
  bool foundNetwork = false;
  for (const auto& category : categories) {
    foundDevelopment = foundDevelopment || category.id == "Development";
    foundAudioVideo = foundAudioVideo || category.id == "AudioVideo";
    foundEducation = foundEducation || category.id == "Education";
    foundNetwork = foundNetwork || category.id == "Network";
  }

  ok &= check(foundDevelopment, "development category should be present");
  ok &= check(foundAudioVideo, "audio alias should expose AudioVideo category");
  ok &= check(foundEducation, "science alias should expose Education category");
  ok &= check(!foundNetwork, "missing categories should not be exposed");

  ok &= check(launcherAppEntryMatchesCategory(entries[0], "Development"), "development entry should match Development");
  ok &= check(launcherAppEntryMatchesCategory(entries[1], "AudioVideo"), "audio entry should match AudioVideo");
  ok &= check(launcherAppEntryMatchesCategory(entries[2], "Education"), "science entry should match Education");
  ok &= check(launcherAppEntryMatchesCategory(entries[3], LauncherAppCategories::All),
              "uncategorized entry should match All");
  ok &= check(!launcherAppEntryMatchesCategory(entries[3], "Development"),
              "uncategorized entry should not match Development");

  CategoryAwareProvider provider;
  const auto filtered = provider.query("", "Development");
  ok &= check(!filtered.empty() && filtered.front().id == "Development",
              "launcher providers should accept an opaque category id at query time");

  return ok ? 0 : 1;
}
