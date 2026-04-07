#pragma once

#include "launcher/launcher_provider.h"

#include <string>
#include <vector>

class ClipboardService;

class EmojiProvider : public LauncherProvider {
public:
  explicit EmojiProvider(ClipboardService* clipboard) : m_clipboard(clipboard) {}

  [[nodiscard]] std::string_view prefix() const override { return "/emo"; }
  [[nodiscard]] std::string_view name() const override { return "Emoji"; }

  void initialize() override;

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;

private:
  struct EmojiEntry {
    std::string emoji;
    std::string name;
    std::string nameLower;
    std::vector<std::string> keywords;
    std::string category;
  };

  std::vector<EmojiEntry> m_entries;
  ClipboardService* m_clipboard = nullptr;
};
