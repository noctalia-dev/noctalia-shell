#pragma once

#include "shell/control_center/tab.h"

class NetworkTab : public Tab {
public:
  std::unique_ptr<Flex> build(Renderer& renderer) override;
};
