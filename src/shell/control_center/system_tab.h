#pragma once

#include "shell/control_center/tab.h"

#include <chrono>
#include <string>

class Flex;
class Glyph;
class GraphNode;
class Label;
class SystemMonitorService;

class SystemTab : public Tab {
public:
  explicit SystemTab(SystemMonitorService* monitor);
  ~SystemTab() override;

  std::unique_ptr<Flex> create() override;
  void onClose() override;
  void setActive(bool active) override;
  void onFrameTick(float deltaMs) override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;

  void updateGraphs(Renderer& renderer);
  void syncLabels();
  [[nodiscard]] static float scrollProgressForSample(std::chrono::steady_clock::time_point sampledAt);
  [[nodiscard]] static std::string formatBytesPerSec(double bytesPerSec);

  SystemMonitorService* m_monitor;
  bool m_active = false;
  bool m_graphInitialized = false;
  float m_scrollProgress = 1.0f;
  std::chrono::steady_clock::time_point m_lastSampleAt{};

  double m_tempMin = 30.0;
  double m_tempMax = 80.0;
  double m_netPeak = 0.0;

  Flex* m_root = nullptr;

  GraphNode* m_cpuGraph = nullptr;
  GraphNode* m_ramGraph = nullptr;
  GraphNode* m_netGraph = nullptr;

  Flex* m_cpuCard = nullptr;
  Flex* m_ramCard = nullptr;
  Flex* m_netCard = nullptr;
  Flex* m_loadCard = nullptr;
  Flex* m_infoCard = nullptr;

  Glyph* m_cpuPctIcon = nullptr;
  Label* m_cpuPctLabel = nullptr;
  Glyph* m_cpuTempIcon = nullptr;
  Label* m_cpuTempLabel = nullptr;
  Glyph* m_ramIcon = nullptr;
  Label* m_ramLabel = nullptr;
  Glyph* m_rxIcon = nullptr;
  Label* m_rxLabel = nullptr;
  Glyph* m_txIcon = nullptr;
  Label* m_txLabel = nullptr;
  Label* m_loadLabel = nullptr;
  Label* m_infoLabel = nullptr;
};
