#pragma once

#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

class SystemBus;

namespace sdbus {
class IProxy;
}

struct PowerProfilesState {
  std::string activeProfile;
  std::vector<std::string> profiles;
  std::string performanceInhibited;

  bool operator==(const PowerProfilesState&) const = default;
};

class PowerProfilesService {
public:
  using ChangeCallback = std::function<void(const PowerProfilesState&)>;

  explicit PowerProfilesService(SystemBus& bus);

  void setChangeCallback(ChangeCallback callback);
  void refresh();

  [[nodiscard]] const PowerProfilesState& state() const noexcept { return m_state; }
  [[nodiscard]] const std::string& activeProfile() const noexcept { return m_state.activeProfile; }
  [[nodiscard]] const std::vector<std::string>& profiles() const noexcept { return m_state.profiles; }

  [[nodiscard]] bool setActiveProfile(std::string_view profile);

private:
  [[nodiscard]] PowerProfilesState readState() const;
  void emitChangedIfNeeded(const PowerProfilesState& next);

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_proxy;
  PowerProfilesState m_state;
  ChangeCallback m_changeCallback;
};
