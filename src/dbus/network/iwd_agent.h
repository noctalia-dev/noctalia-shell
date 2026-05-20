#pragma once

#include <functional>
#include <memory>
#include <string>

class SystemBus;

namespace sdbus {
  class IObject;
}

// IWD passphrase agent. Registers with net.connman.iwd.AgentManager on the system bus
// and answers RequestPassphrase calls so the UI can supply PSKs for secured networks.
//
// Mirrors the public interface of NetworkSecretAgent so NetworkTab can use either.
class IwdAgent {
public:
  struct SecretRequest {
    std::string ssid;      // SSID of the network needing a passphrase
    std::string netPath;   // IWD network object path
  };

  using RequestCallback = std::function<void(const SecretRequest&)>;

  explicit IwdAgent(SystemBus& bus);
  ~IwdAgent();

  IwdAgent(const IwdAgent&) = delete;
  IwdAgent& operator=(const IwdAgent&) = delete;

  void setRequestCallback(RequestCallback callback);

  void submitSecret(const std::string& psk);
  void cancelSecret();

  [[nodiscard]] bool hasPendingRequest() const noexcept;

private:
  struct Impl;
  std::unique_ptr<Impl> m_impl;
};
