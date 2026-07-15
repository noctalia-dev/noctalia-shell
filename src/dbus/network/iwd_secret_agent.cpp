#include "dbus/network/iwd_secret_agent.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <optional>
#include <sdbus-c++/IConnection.h>
#include <sdbus-c++/IObject.h>
#include <sdbus-c++/MethodResult.h>
#include <sdbus-c++/Types.h>
#include <sdbus-c++/VTableItems.h>
#include <string>
#include <utility>

namespace {

  constexpr Logger kLog("iwd");

  // No well-known name on the system bus — iwd tracks the agent by the sender's
  // unique name from RegisterAgent, and claiming a name would need a dbus policy.
  const sdbus::ObjectPath kAgentObjectPath{"/net/connman/iwd/Agent"};
  constexpr auto kAgentInterface = "net.connman.iwd.Agent";

  const sdbus::ServiceName kIwdBusName{"net.connman.iwd"};
  const sdbus::ObjectPath kAgentManagerObjectPath{"/net/connman/iwd"};
  constexpr auto kAgentManagerInterface = "net.connman.iwd.AgentManager";

} // namespace

struct IwdSecretAgent::Impl {
  SystemBus& bus;
  std::unique_ptr<sdbus::IObject> object;
  RequestCallback requestCallback;
  std::optional<sdbus::Result<std::string>> pendingResult;

  explicit Impl(SystemBus& b) : bus(b) {}

  void onRequestPassphrase(sdbus::Result<std::string>&& result, const sdbus::ObjectPath& networkPath) {
    if (pendingResult.has_value()) {
      kLog.debug("RequestPassphrase while another is pending -> Cancel");
      result.returnError(
          sdbus::Error{sdbus::Error::Name{"net.connman.iwd.Agent.Error.Canceled"}, "another request is already pending"}
      );
      return;
    }

    // Extract SSID from the network path if possible (format: /net/connman/iwd/station0/OrderedNetwork/X/Network/Y)
    SecretRequest request;
    request.ssid = std::string(networkPath);
    kLog.info("RequestPassphrase path={}", request.ssid);

    pendingResult = std::move(result);

    if (requestCallback) {
      requestCallback(request);
    } else {
      // No UI available; fail fast so iwd doesn't sit waiting.
      cancelPending("no UI handler");
    }
  }

  void cancelPending(const std::string& reason) {
    if (!pendingResult.has_value()) {
      return;
    }
    constexpr auto kErrorName = "net.connman.iwd.Agent.Error.Canceled";
    pendingResult->returnError(sdbus::Error{sdbus::Error::Name{kErrorName}, reason});
    pendingResult.reset();
  }

  void submitPending(const std::string& psk) {
    if (!pendingResult.has_value()) {
      return;
    }
    pendingResult->returnResults(psk);
    pendingResult.reset();
  }
};

IwdSecretAgent::IwdSecretAgent(SystemBus& bus) : m_impl(std::make_unique<Impl>(bus)) {
  m_impl->object = sdbus::createObject(bus.connection(), kAgentObjectPath);

  m_impl->object
      ->addVTable(
          sdbus::registerMethod("RequestPassphrase")
              .withInputParamNames("network")
              .withOutputParamNames("passphrase")
              .implementedAs([this](sdbus::Result<std::string>&& result, const sdbus::ObjectPath& networkPath) {
                m_impl->onRequestPassphrase(std::move(result), networkPath);
              }),
          sdbus::registerMethod("Cancel").withInputParamNames("reason").implementedAs(
              [this](const std::string& reason) { m_impl->cancelPending(reason); }
          )
      )
      .forInterface(kAgentInterface);

  // Register with iwd's agent manager.
  try {
    auto agentManager = sdbus::createProxy(bus.connection(), kIwdBusName, kAgentManagerObjectPath);
    agentManager->callMethod("RegisterAgent")
        .onInterface(kAgentManagerInterface)
        .withArguments(sdbus::ObjectPath{kAgentObjectPath});
    kLog.info("registered iwd secret agent at {}", std::string(kAgentObjectPath));
  } catch (const sdbus::Error& e) {
    kLog.warn("iwd secret agent registration failed: {}", e.what());
  }
}

IwdSecretAgent::~IwdSecretAgent() {
  if (m_impl == nullptr) {
    return;
  }
  m_impl->cancelPending("agent shutting down");
  try {
    auto agentManager = sdbus::createProxy(m_impl->bus.connection(), kIwdBusName, kAgentManagerObjectPath);
    agentManager->callMethod("UnregisterAgent")
        .onInterface(kAgentManagerInterface)
        .withArguments(sdbus::ObjectPath{kAgentObjectPath});
  } catch (const sdbus::Error& e) {
    kLog.debug("iwd secret agent unregister failed: {}", e.what());
  }
}

void IwdSecretAgent::setRequestCallback(RequestCallback callback) {
  if (m_impl != nullptr) {
    m_impl->requestCallback = std::move(callback);
  }
}

void IwdSecretAgent::submitSecret(const std::string& psk) {
  if (m_impl != nullptr) {
    m_impl->submitPending(psk);
  }
}

void IwdSecretAgent::cancelSecret() {
  if (m_impl != nullptr) {
    m_impl->cancelPending("user canceled");
  }
}

bool IwdSecretAgent::hasPendingRequest() const noexcept {
  return m_impl != nullptr && m_impl->pendingResult.has_value();
}
