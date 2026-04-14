#pragma once

#include "dbus/network/network_service.h"
#include "shell/widget/widget.h"

#include <string>

class Glyph;
class Label;

class NetworkWidget : public Widget {
public:
  explicit NetworkWidget(NetworkService* network, bool showLabel);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  NetworkService* m_network = nullptr;
  bool m_showLabel = true;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  NetworkState m_lastState;
  bool m_haveLastState = false;
};
