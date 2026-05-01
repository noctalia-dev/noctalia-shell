#pragma once

#include "dbus/network/network_secret_agent.h"
#include "dbus/network/network_service.h"
#include "shell/control_center/tab.h"

#include <string>
#include <vector>

class Button;
class Flex;
class Input;
class Label;
class ScrollView;
class Spinner;
class Toggle;

class NetworkTab : public Tab {
public:
  NetworkTab(NetworkService* network, NetworkSecretAgent* secrets);
  ~NetworkTab() override;

  std::unique_ptr<Flex> create() override;
  std::unique_ptr<Flex> createHeaderActions() override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;

  void syncCurrentCard();
  void rebuildApList(Renderer& renderer);
  void syncPasswordCard();
  void showPasswordPrompt(const NetworkSecretAgent::SecretRequest& request);
  void clearPasswordPrompt();
  [[nodiscard]] std::string apListKey(const std::vector<AccessPointInfo>& aps) const;

  NetworkService* m_network = nullptr;
  NetworkSecretAgent* m_secrets = nullptr;

  Flex* m_rootLayout = nullptr;
  Flex* m_currentCard = nullptr;
  Label* m_currentTitle = nullptr;
  Label* m_currentDetail = nullptr;
  Flex* m_passwordCard = nullptr;
  Label* m_passwordTitle = nullptr;
  Input* m_passwordInput = nullptr;
  Flex* m_listCard = nullptr;
  ScrollView* m_listScroll = nullptr;
  Flex* m_list = nullptr;

  Button* m_rescanButton = nullptr;
  Toggle* m_wifiToggle = nullptr;
  Flex* m_disconnectRow = nullptr;
  Button* m_disconnectButton = nullptr;
  Spinner* m_scanSpinner = nullptr;

  std::string m_lastListKey;
  float m_lastListWidth = -1.0f;

  bool m_hasPendingSecret = false;
  std::string m_pendingSsid;
};
