#pragma once

#include <functional>
#include <optional>
#include <string>
#include <unordered_map>

class StateService {
public:
  using ChangeCallback = std::function<void()>;

  StateService();
  ~StateService();

  StateService(const StateService&) = delete;
  StateService& operator=(const StateService&) = delete;

  [[nodiscard]] std::string getWallpaperPath(const std::string& connectorName) const;
  [[nodiscard]] std::string getDefaultWallpaperPath() const;

  // Updates state.toml atomically and fires the wallpaper change callback
  // directly. Pass nullopt as connector to update the default path.
  void setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path);

  void setWallpaperChangeCallback(ChangeCallback callback);
  void checkReload();
  [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }

private:
  void loadFromFile(const std::string& path);
  void setupWatch();
  bool writeToFile() const;

  std::string m_statePath;
  std::string m_defaultWallpaperPath;
  std::unordered_map<std::string, std::string> m_monitorWallpaperPaths;

  ChangeCallback m_wallpaperChangeCallback;
  int m_inotifyFd = -1;
  int m_watchDescriptor = -1;
  bool m_ownWritePending = false;
};
