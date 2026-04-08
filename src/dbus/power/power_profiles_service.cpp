#include "dbus/power/power_profiles_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <algorithm>
#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>

namespace {

static const sdbus::ServiceName k_powerProfilesBusName{"org.freedesktop.UPower.PowerProfiles"};
static const sdbus::ObjectPath k_powerProfilesObjectPath{"/org/freedesktop/UPower/PowerProfiles"};
static constexpr auto k_powerProfilesInterface = "org.freedesktop.UPower.PowerProfiles";
static constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

template <typename T>
T getPropertyOr(sdbus::IProxy& proxy, std::string_view propertyName, T fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(propertyName).onInterface(k_powerProfilesInterface);
    return value.get<T>();
  } catch (const sdbus::Error&) {
    return fallback;
  }
}

std::vector<std::string> decodeProfiles(const sdbus::Variant& value) {
  std::vector<std::string> profiles;

  try {
    const auto profileMaps = value.get<std::vector<std::map<std::string, sdbus::Variant>>>();
    profiles.reserve(profileMaps.size());
    for (const auto& profileMap : profileMaps) {
      auto it = profileMap.find("Profile");
      if (it == profileMap.end()) {
        continue;
      }
      try {
        const std::string profile = it->second.get<std::string>();
        if (!profile.empty()) {
          profiles.push_back(profile);
        }
      } catch (const sdbus::Error&) {
      }
    }
  } catch (const sdbus::Error&) {
  }

  std::ranges::sort(profiles);
  profiles.erase(std::unique(profiles.begin(), profiles.end()), profiles.end());
  return profiles;
}

} // namespace

PowerProfilesService::PowerProfilesService(SystemBus& bus) : m_bus(bus) {
  m_proxy = sdbus::createProxy(m_bus.connection(), k_powerProfilesBusName, k_powerProfilesObjectPath);

  m_proxy->uponSignal("PropertiesChanged")
      .onInterface(k_propertiesInterface)
      .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& changedProperties,
                   const std::vector<std::string>& invalidatedProperties) {
        if (interfaceName != k_powerProfilesInterface) {
          return;
        }

        bool relevant = changedProperties.contains("ActiveProfile") || changedProperties.contains("Profiles") ||
                        changedProperties.contains("PerformanceInhibited");

        if (!relevant) {
          relevant = std::ranges::find(invalidatedProperties, "ActiveProfile") != invalidatedProperties.end() ||
                     std::ranges::find(invalidatedProperties, "Profiles") != invalidatedProperties.end() ||
                     std::ranges::find(invalidatedProperties, "PerformanceInhibited") != invalidatedProperties.end();
        }

        if (relevant) {
          refresh();
        }
      });

  refresh();
}

void PowerProfilesService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void PowerProfilesService::refresh() { emitChangedIfNeeded(readState()); }

bool PowerProfilesService::setActiveProfile(std::string_view profile) {
  if (profile.empty()) {
    return false;
  }

  try {
    m_proxy->setProperty("ActiveProfile").onInterface(k_powerProfilesInterface).toValue(std::string(profile));
    refresh();
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("power profile change failed profile={} err={}", std::string(profile), e.what());
    return false;
  }
}

PowerProfilesState PowerProfilesService::readState() const {
  PowerProfilesState next;
  next.activeProfile = getPropertyOr<std::string>(*m_proxy, "ActiveProfile", "");
  next.performanceInhibited = getPropertyOr<std::string>(*m_proxy, "PerformanceInhibited", "");

  try {
    const sdbus::Variant profilesVariant = m_proxy->getProperty("Profiles").onInterface(k_powerProfilesInterface);
    next.profiles = decodeProfiles(profilesVariant);
  } catch (const sdbus::Error&) {
    next.profiles.clear();
  }

  return next;
}

void PowerProfilesService::emitChangedIfNeeded(const PowerProfilesState& next) {
  if (next == m_state) {
    return;
  }

  m_state = next;
  if (m_changeCallback) {
    m_changeCallback(m_state);
  }
}
