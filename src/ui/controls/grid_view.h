#pragma once

#include "render/scene/node.h"

#include <cstddef>

class Renderer;

class GridView : public Node {
public:
  void setColumns(std::size_t columns);
  void setColumnGap(float gap);
  void setRowGap(float gap);
  void setPadding(float top, float right, float bottom, float left);
  void setPadding(float all);
  void setPadding(float vertical, float horizontal);
  void setStretchItems(bool stretch);
  void setUniformCellSize(bool uniform);
  void setMinCellWidth(float width);
  void setMinCellHeight(float height);

  [[nodiscard]] std::size_t columns() const noexcept { return m_columns; }
  [[nodiscard]] float columnGap() const noexcept { return m_columnGap; }
  [[nodiscard]] float rowGap() const noexcept { return m_rowGap; }
  [[nodiscard]] float paddingTop() const noexcept { return m_paddingTop; }
  [[nodiscard]] float paddingRight() const noexcept { return m_paddingRight; }
  [[nodiscard]] float paddingBottom() const noexcept { return m_paddingBottom; }
  [[nodiscard]] float paddingLeft() const noexcept { return m_paddingLeft; }
  [[nodiscard]] bool stretchItems() const noexcept { return m_stretchItems; }
  [[nodiscard]] bool uniformCellSize() const noexcept { return m_uniformCellSize; }
  [[nodiscard]] float minCellWidth() const noexcept { return m_minCellWidth; }
  [[nodiscard]] float minCellHeight() const noexcept { return m_minCellHeight; }

  void layout(Renderer& renderer) override;

private:
  std::size_t m_columns = 1;
  float m_columnGap = 0.0f;
  float m_rowGap = 0.0f;
  float m_paddingTop = 0.0f;
  float m_paddingRight = 0.0f;
  float m_paddingBottom = 0.0f;
  float m_paddingLeft = 0.0f;
  bool m_stretchItems = false;
  bool m_uniformCellSize = true;
  float m_minCellWidth = 0.0f;
  float m_minCellHeight = 0.0f;
};
