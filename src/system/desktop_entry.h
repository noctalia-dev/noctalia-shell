#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct DesktopAction {
  std::string id;
  std::string name;
  std::string exec;
};

struct DesktopEntry {
  std::string id;
  std::string path;
  std::string name;
  std::string genericName;
  std::string comment;
  std::string exec;
  std::string icon;
  std::string categories;
  std::string keywords;
  std::string startupWmClass;
  bool noDisplay = false;
  bool hidden = false;
  bool terminal = false;

  // Pre-lowercased for matching
  std::string nameLower;
  std::string genericNameLower;
  std::string keywordsLower;
  std::string categoriesLower;
  std::string startupWmClassLower;
  std::string idLower;
  std::string execLower;

  // Desktop file actions (e.g. "New Window", "New Private Window")
  std::vector<DesktopAction> actions;
};

std::vector<DesktopEntry> scanDesktopEntries();

const std::vector<DesktopEntry>& desktopEntries();
std::uint64_t desktopEntriesVersion();
int desktopEntryWatchFd() noexcept;
void checkDesktopEntryReload();
