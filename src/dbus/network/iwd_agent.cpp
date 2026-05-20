#include "dbus/network/iwd_agent.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <optional>
#include <sdbus-c++/IConnection.h>
#include <sdbus-c++/IObject.h>
#include <sdbus-c++/MethodResult.h>
#include <sdbus-c++/Types.h>
#include <sdbus-c++/VTableItems.h>
#include <string>

namespace {

  constexpr Logger kLog("iwd");

  const sdbus::ServiceName k_iwdBusName{"net.connman.iwd"};
  const sdbus::ObjectPath k_agentManagerPath{"/net/connman/iwd"};
  const sdbus::ObjectPath k_agentObjectPath{"/org/noctalia/IwdAgent"};
  constexpr auto k_agentManagerInterface = "net.connman.iwd.AgentManager";
  constexpr auto k_agentInterface = "net.connman.iwd.Agent";
  constexpr auto k_networkInterface = "net.connman.iwd.Network";
  constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

} // namespace

struct IwdAgent::Impl {
  SystemBus& bus;
  std::unique_ptr<sdbus::IObject> object;
  RequestCallback requestCallback;
  std::optional<sdbus::Result<std::string>> pendingResult;
  std::string pendingNetPath;

  explicit Impl(SystemBus& b) : bus(b) {}

  void onRequestPassphrase(sdbus::Result<std::string>&& result, sdbus::ObjectPath netPath) {
    if (pendingResult.has_value()) {
      result.returnError(
          sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, "another request is pending"});
      return;
    }

    // Look up the SSID from the network object.
    std::string ssid;
    try {
      auto proxy = sdbus::createProxy(bus.connection(), k_iwdBusName, netPath);
      ssid = proxy->getProperty("Name").onInterface(k_networkInterface).get<std::string>();
    } catch (const sdbus::Error&) {
    }

    kLog.info("RequestPassphrase for ssid=\"{}\" path={}", ssid, std::string(netPath));

    pendingResult = std::move(result);
    pendingNetPath = std::string(netPath);

    if (requestCallback) {
      requestCallback(SecretRequest{ssid, pendingNetPath});
    } else {
      cancelPending("no UI handler");
    }
  }

  void cancelPending(const std::string& reason) {
    if (!pendingResult.has_value())
      return;
    pendingResult->returnError(
        sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, reason});
    pendingResult.reset();
    pendingNetPath.clear();
  }

  void submitPending(const std::string& psk) {
    if (!pendingResult.has_value())
      return;
    pendingResult->returnResults(psk);
    pendingResult.reset();
    pendingNetPath.clear();
  }
};

IwdAgent::IwdAgent(SystemBus& bus) : m_impl(std::make_unique<Impl>(bus)) {
  m_impl->object = sdbus::createObject(bus.connection(), k_agentObjectPath);

  m_impl->object
      ->addVTable(
          sdbus::registerMethod("Release")
              .implementedAs([]() {}),
          sdbus::registerMethod("RequestPassphrase")
              .withInputParamNames("network")
              .withOutputParamNames("passphrase")
              .implementedAs([this](sdbus::Result<std::string>&& result, sdbus::ObjectPath network) {
                m_impl->onRequestPassphrase(std::move(result), std::move(network));
              }),
          sdbus::registerMethod("RequestPrivateKeyPassphrase")
              .withInputParamNames("network")
              .withOutputParamNames("passphrase")
              .implementedAs([this](sdbus::Result<std::string>&& result, sdbus::ObjectPath /*network*/) {
                result.returnError(
                    sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, "not supported"});
              }),
          sdbus::registerMethod("RequestUserNameAndPassword")
              .withInputParamNames("network")
              .withOutputParamNames("user", "password")
              .implementedAs(
                  [](sdbus::Result<std::string, std::string>&& result, sdbus::ObjectPath /*network*/) {
                    result.returnError(
                        sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, "not supported"});
                  }),
          sdbus::registerMethod("RequestUserPassword")
              .withInputParamNames("network", "user")
              .withOutputParamNames("password")
              .implementedAs([](sdbus::Result<std::string>&& result, sdbus::ObjectPath /*network*/,
                                std::string /*user*/) {
                result.returnError(
                    sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, "not supported"});
              }),
          sdbus::registerMethod("Cancel")
              .withInputParamNames("reason")
              .implementedAs([this](std::string reason) { m_impl->cancelPending(reason); }))
      .forInterface(k_agentInterface);

  try {
    auto mgr = sdbus::createProxy(bus.connection(), k_iwdBusName, k_agentManagerPath);
    mgr->callMethod("RegisterAgent").onInterface(k_agentManagerInterface).withArguments(k_agentObjectPath);
    kLog.info("registered IWD agent at {}", std::string(k_agentObjectPath));
  } catch (const sdbus::Error& e) {
    kLog.warn("IWD agent registration failed: {}", e.what());
  }
}

IwdAgent::~IwdAgent() {
  if (!m_impl)
    return;
  m_impl->cancelPending("agent shutting down");
  try {
    auto mgr = sdbus::createProxy(m_impl->bus.connection(), k_iwdBusName, k_agentManagerPath);
    mgr->callMethod("UnregisterAgent").onInterface(k_agentManagerInterface).withArguments(k_agentObjectPath);
  } catch (const sdbus::Error& e) {
    kLog.debug("IWD agent unregister failed: {}", e.what());
  }
}

void IwdAgent::setRequestCallback(RequestCallback callback) {
  if (m_impl)
    m_impl->requestCallback = std::move(callback);
}

void IwdAgent::submitSecret(const std::string& psk) {
  if (m_impl)
    m_impl->submitPending(psk);
}

void IwdAgent::cancelSecret() {
  if (m_impl)
    m_impl->cancelPending("user canceled");
}

bool IwdAgent::hasPendingRequest() const noexcept {
  return m_impl && m_impl->pendingResult.has_value();
}
