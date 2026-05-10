#pragma once

#include "launcher/launcher_provider.h"
#include "ui/controls/virtual_grid_view.h"

#include <cstddef>
#include <functional>
#include <memory>
#include <vector>

class AsyncTextureCache;
class Renderer;

[[nodiscard]] float launcherResultRowHeight(float scale);

class LauncherResultAdapter final : public VirtualGridAdapter {
public:
  using ActivateCallback = std::function<void(std::size_t)>;
  using SecondaryActivateCallback = std::function<void(std::size_t, float, float)>;

  LauncherResultAdapter(float scale, AsyncTextureCache* cache);

  void setResults(const std::vector<LauncherResult>* results);
  void setRenderer(Renderer* renderer);
  void setOnActivate(ActivateCallback callback);
  void setOnSecondaryActivate(SecondaryActivateCallback callback);

  [[nodiscard]] std::size_t itemCount() const override;
  [[nodiscard]] std::unique_ptr<Node> createTile() override;
  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override;
  void onActivate(std::size_t index) override;
  void onSecondaryActivate(std::size_t index, float anchorX, float anchorY) override;

private:
  float m_scale = 1.0f;
  AsyncTextureCache* m_cache = nullptr;
  Renderer* m_renderer = nullptr;
  const std::vector<LauncherResult>* m_results = nullptr;
  ActivateCallback m_onActivate;
  SecondaryActivateCallback m_onSecondaryActivate;
};
