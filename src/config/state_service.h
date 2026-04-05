#pragma once

#include <functional>
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

  void setWallpaperChangeCallback(ChangeCallback callback);
  void checkReload();
  [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }

private:
  void loadFromFile(const std::string& path);
  void setupWatch();

  std::string m_statePath;
  std::string m_defaultWallpaperPath;
  std::unordered_map<std::string, std::string> m_monitorWallpaperPaths;

  ChangeCallback m_wallpaperChangeCallback;
  int m_inotifyFd = -1;
  int m_watchDescriptor = -1;
};
