#include "ui/controls/grid_view.h"

#include "render/core/renderer.h"

#include <algorithm>
#include <numeric>
#include <vector>

void GridView::setColumns(std::size_t columns) {
  const std::size_t normalized = std::max<std::size_t>(1, columns);
  if (m_columns == normalized) {
    return;
  }
  m_columns = normalized;
  markDirty();
}

void GridView::setColumnGap(float gap) {
  if (m_columnGap == gap && m_rowGap == gap) {
    return;
  }
  m_columnGap = gap;
  m_rowGap = gap;
  markDirty();
}

void GridView::setRowGap(float gap) {
  // GridView keeps row/column spacing symmetric by design.
  setColumnGap(gap);
}

void GridView::setPadding(float top, float right, float bottom, float left) {
  m_paddingTop = top;
  m_paddingRight = right;
  m_paddingBottom = bottom;
  m_paddingLeft = left;
  markDirty();
}

void GridView::setPadding(float all) { setPadding(all, all, all, all); }

void GridView::setPadding(float vertical, float horizontal) { setPadding(vertical, horizontal, vertical, horizontal); }

void GridView::setStretchItems(bool stretch) {
  if (m_stretchItems == stretch) {
    return;
  }
  m_stretchItems = stretch;
  markDirty();
}

void GridView::setUniformCellSize(bool uniform) {
  if (m_uniformCellSize == uniform) {
    return;
  }
  m_uniformCellSize = uniform;
  markDirty();
}

void GridView::setMinCellWidth(float width) {
  const float normalized = std::max(0.0f, width);
  if (m_minCellWidth == normalized) {
    return;
  }
  m_minCellWidth = normalized;
  markDirty();
}

void GridView::setMinCellHeight(float height) {
  const float normalized = std::max(0.0f, height);
  if (m_minCellHeight == normalized) {
    return;
  }
  m_minCellHeight = normalized;
  markDirty();
}

void GridView::doLayout(Renderer& renderer) {
  auto layoutWithAssignedSize = [&renderer](Node* child, float assignedWidth, float assignedHeight) {
    child->setSize(assignedWidth, assignedHeight);
    child->layout(renderer);
    // Clamp so controls that resize during layout still match the grid cell.
    child->setSize(assignedWidth, assignedHeight);
  };

  std::vector<Node*> visibleChildren;
  visibleChildren.reserve(children().size());
  for (auto& child : children()) {
    if (child->visible()) {
      visibleChildren.push_back(child.get());
    }
  }

  if (visibleChildren.empty()) {
    setSize(std::max(width(), m_paddingLeft + m_paddingRight), std::max(height(), m_paddingTop + m_paddingBottom));
    return;
  }

  const std::size_t columns = std::min(m_columns, visibleChildren.size());
  const std::size_t rows = (visibleChildren.size() + columns - 1) / columns;

  const bool hasFixedWidth = width() > 0.0f;
  const bool hasFixedHeight = height() > 0.0f;
  const float fixedWidth = width();
  const float fixedHeight = height();

  std::vector<float> columnWidths(columns, 0.0f);
  std::vector<float> rowHeights(rows, 0.0f);

  float stretchedWidth = 0.0f;
  if (hasFixedWidth && m_stretchItems && columns > 0) {
    const float innerWidth =
        std::max(0.0f, fixedWidth - m_paddingLeft - m_paddingRight - m_columnGap * static_cast<float>(columns - 1));
    stretchedWidth = innerWidth / static_cast<float>(columns);
  }

  if (m_uniformCellSize) {
    // Pass 1: measure natural child sizes without imposed cell width.
    float maxMeasuredWidth = 0.0f;
    float maxMeasuredHeight = 0.0f;
    for (Node* child : visibleChildren) {
      child->layout(renderer);
      maxMeasuredWidth = std::max(maxMeasuredWidth, child->width());
      maxMeasuredHeight = std::max(maxMeasuredHeight, child->height());
    }

    float uniformWidth = maxMeasuredWidth;
    if (hasFixedWidth && columns > 0) {
      const float innerWidth = std::max(
          0.0f,
          fixedWidth - m_paddingLeft - m_paddingRight - m_columnGap * static_cast<float>(columns - 1));
      uniformWidth = std::max(uniformWidth, innerWidth / static_cast<float>(columns));
    } else if (hasFixedWidth && m_stretchItems && stretchedWidth > 0.0f) {
      uniformWidth = std::max(uniformWidth, stretchedWidth);
    }
    uniformWidth = std::max(uniformWidth, m_minCellWidth);
    const float uniformHeight = std::max(maxMeasuredHeight, m_minCellHeight);

    std::fill(columnWidths.begin(), columnWidths.end(), uniformWidth);
    std::fill(rowHeights.begin(), rowHeights.end(), uniformHeight);

    for (Node* child : visibleChildren) {
      layoutWithAssignedSize(child, uniformWidth, uniformHeight);
    }
  } else {
    if (hasFixedWidth && m_stretchItems) {
      std::fill(columnWidths.begin(), columnWidths.end(), stretchedWidth);
    }

    for (std::size_t index = 0; index < visibleChildren.size(); ++index) {
      Node* child = visibleChildren[index];
      const std::size_t col = index % columns;
      const std::size_t row = index / columns;

      if (hasFixedWidth && m_stretchItems && stretchedWidth > 0.0f) {
        layoutWithAssignedSize(child, columnWidths[col], child->height());
      } else {
        child->layout(renderer);
      }

      if (!hasFixedWidth || !m_stretchItems) {
        columnWidths[col] = std::max(columnWidths[col], child->width());
      }
      rowHeights[row] = std::max(rowHeights[row], child->height());
    }

    for (auto& columnWidth : columnWidths) {
      columnWidth = std::max(columnWidth, m_minCellWidth);
    }
    for (auto& rowHeight : rowHeights) {
      rowHeight = std::max(rowHeight, m_minCellHeight);
    }
  }

  const float contentWidth = std::max(
      0.0f, std::accumulate(columnWidths.begin(), columnWidths.end(), 0.0f) +
                m_columnGap * static_cast<float>(columns > 0 ? columns - 1 : 0));
  const float contentHeight = std::max(
      0.0f, std::accumulate(rowHeights.begin(), rowHeights.end(), 0.0f) +
                m_rowGap * static_cast<float>(rows > 0 ? rows - 1 : 0));

  const float computedWidth = m_paddingLeft + contentWidth + m_paddingRight;
  const float computedHeight = m_paddingTop + contentHeight + m_paddingBottom;
  setSize(hasFixedWidth ? std::max(fixedWidth, computedWidth) : computedWidth,
          hasFixedHeight ? std::max(fixedHeight, computedHeight) : computedHeight);

  std::vector<float> columnOffsets(columns, m_paddingLeft);
  for (std::size_t col = 1; col < columns; ++col) {
    columnOffsets[col] = columnOffsets[col - 1] + columnWidths[col - 1] + m_columnGap;
  }

  std::vector<float> rowOffsets(rows, m_paddingTop);
  for (std::size_t row = 1; row < rows; ++row) {
    rowOffsets[row] = rowOffsets[row - 1] + rowHeights[row - 1] + m_rowGap;
  }

  for (std::size_t index = 0; index < visibleChildren.size(); ++index) {
    Node* child = visibleChildren[index];
    const std::size_t col = index % columns;
    const std::size_t row = index / columns;
    child->setPosition(columnOffsets[col], rowOffsets[row]);
  }
}
