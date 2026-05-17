#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

class SystemBus;
class IpcService;

namespace sdbus {
  class IProxy;
}

[[nodiscard]] std::string profileLabel(std::string_view profile);
[[nodiscard]] std::string_view profileGlyphName(std::string_view profile);

struct PowerProfilesState {
  std::string activeProfile;
  std::vector<std::string> profiles;
  std::string performanceInhibited;

  bool operator==(const PowerProfilesState&) const = default;
};

enum class PowerProfilesChangeOrigin : std::uint8_t {
  External,
  Noctalia,
};

class PowerProfilesService {
public:
  using ChangeCallback = std::function<void(const PowerProfilesState&, PowerProfilesChangeOrigin)>;

  explicit PowerProfilesService(SystemBus& bus);

  void setChangeCallback(ChangeCallback callback);
  void refresh();

  [[nodiscard]] const PowerProfilesState& state() const noexcept { return m_state; }
  [[nodiscard]] const std::string& activeProfile() const noexcept { return m_state.activeProfile; }
  [[nodiscard]] const std::vector<std::string>& profiles() const noexcept { return m_state.profiles; }

  [[nodiscard]] bool setActiveProfile(std::string_view profile);
  /// Advance to the next profile in the service's ordered list (wraps). Fails if no profiles are known.
  [[nodiscard]] bool cycleActiveProfile();

  void registerIpc(IpcService& ipc);

private:
  [[nodiscard]] PowerProfilesState readState() const;
  [[nodiscard]] PowerProfilesChangeOrigin consumeActiveProfileChangeOrigin(std::string_view profile);
  void emitChangedIfNeeded(const PowerProfilesState& next);

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_proxy;
  PowerProfilesState m_state;
  std::optional<std::string> m_pendingLocalActiveProfile;
  ChangeCallback m_changeCallback;
};
