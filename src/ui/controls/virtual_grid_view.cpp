#include "ui/controls/virtual_grid_view.h"

#include "render/scene/input_area.h"
#include "ui/controls/scroll_view.h"

#include <algorithm>
#include <cmath>
#include <linux/input-event-codes.h>
#include <memory>

// Internal canvas that reports a virtual size set externally and never moves
// its children during its own layout pass — VirtualGridView positions pool
// tiles and the overlay InputArea explicitly.
class VirtualGridView::Canvas : public Node {
public:
  Canvas() = default;

  void setVirtualSize(float width, float height) {
    m_virtualWidth = std::max(0.0f, width);
    m_virtualHeight = std::max(0.0f, height);
    setSize(m_virtualWidth, m_virtualHeight);
  }

protected:
  LayoutSize doMeasure(Renderer& /*renderer*/, const LayoutConstraints& constraints) override {
    return constraints.constrain(LayoutSize{.width = m_virtualWidth, .height = m_virtualHeight});
  }

  void doLayout(Renderer& /*renderer*/) override {
    // Tiles and the input overlay are positioned by VirtualGridView::doLayout.
  }

  void doArrange(Renderer& /*renderer*/, const LayoutRect& rect) override {
    setPosition(rect.x, rect.y);
    setSize(m_virtualWidth, m_virtualHeight);
  }

private:
  float m_virtualWidth = 0.0f;
  float m_virtualHeight = 0.0f;
};

VirtualGridView::VirtualGridView() {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(0.0f);
  setPadding(0.0f);
  setFillWidth(true);
  setFillHeight(true);

  auto scroll = std::make_unique<ScrollView>();
  scroll->setFlexGrow(1.0f);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(0.0f);
  scroll->setOnScrollChanged([this](float offset) { onScrollChanged(offset); });
  m_scroll = static_cast<ScrollView*>(addChild(std::move(scroll)));

  auto canvas = std::make_unique<Canvas>();
  m_canvas = static_cast<Canvas*>(m_scroll->content()->addChild(std::move(canvas)));

  auto inputArea = std::make_unique<InputArea>();
  inputArea->setZIndex(50);
  inputArea->setOnEnter([this](const InputArea::PointerData& data) { onPointerEnter(data.localX, data.localY); });
  inputArea->setOnMotion([this](const InputArea::PointerData& data) { onPointerMotion(data.localX, data.localY); });
  inputArea->setOnLeave([this]() { onPointerLeave(); });
  inputArea->setOnPress([this](const InputArea::PointerData& data) {
    if (!data.pressed || data.button != BTN_LEFT) {
      return;
    }
    onPointerPress(data.localX, data.localY);
  });
  m_inputArea = static_cast<InputArea*>(m_canvas->addChild(std::move(inputArea)));
}

void VirtualGridView::setAdapter(VirtualGridAdapter* adapter) {
  if (m_adapter == adapter) {
    return;
  }
  m_adapter = adapter;
  // Drop the existing pool — tiles were built by the previous adapter's createTile().
  for (Node* tile : m_pool) {
    if (tile != nullptr) {
      m_canvas->removeChild(tile);
    }
  }
  m_pool.clear();
  m_slotBoundIndex.clear();
  m_selectedIndex.reset();
  m_hoveredIndex.reset();
  markLayoutDirty();
}

void VirtualGridView::notifyDataChanged() {
  // Force every visible slot to rebind on the next layout.
  std::fill(m_slotBoundIndex.begin(), m_slotBoundIndex.end(), std::nullopt);
  markLayoutDirty();
}

void VirtualGridView::notifyItemChanged(std::size_t index) {
  for (std::size_t slot = 0; slot < m_slotBoundIndex.size(); ++slot) {
    if (m_slotBoundIndex[slot].has_value() && *m_slotBoundIndex[slot] == index) {
      m_slotBoundIndex[slot].reset();
      markLayoutDirty();
      return;
    }
  }
}

void VirtualGridView::setColumns(std::size_t columns) {
  if (m_columns == columns) {
    return;
  }
  m_columns = columns;
  notifyDataChanged();
}

void VirtualGridView::setMinCellWidth(float width) {
  m_minCellWidth = std::max(1.0f, width);
  notifyDataChanged();
}

void VirtualGridView::setCellHeight(float height) {
  m_cellHeight = std::max(1.0f, height);
  notifyDataChanged();
}

void VirtualGridView::setSquareCells(bool square) {
  if (m_squareCells == square) {
    return;
  }
  m_squareCells = square;
  notifyDataChanged();
}

void VirtualGridView::setColumnGap(float gap) {
  m_columnGap = std::max(0.0f, gap);
  notifyDataChanged();
}

void VirtualGridView::setRowGap(float gap) {
  m_rowGap = std::max(0.0f, gap);
  notifyDataChanged();
}

void VirtualGridView::setOverscanRows(std::size_t rows) {
  m_overscanRows = rows;
  markLayoutDirty();
}

void VirtualGridView::scrollToIndex(std::size_t index) {
  m_pendingScrollToIndex = true;
  m_pendingScrollIndex = index;
  markLayoutDirty();
}

void VirtualGridView::setSelectedIndex(std::optional<std::size_t> index) {
  if (m_selectedIndex == index) {
    return;
  }
  m_selectedIndex = index;
  markLayoutDirty();
  if (m_onSelectionChanged) {
    m_onSelectionChanged(m_selectedIndex);
  }
}

void VirtualGridView::setOnSelectionChanged(std::function<void(std::optional<std::size_t>)> callback) {
  m_onSelectionChanged = std::move(callback);
}

void VirtualGridView::doLayout(Renderer& renderer) {
  if (m_adapter == nullptr || m_scroll == nullptr || m_canvas == nullptr || m_inputArea == nullptr) {
    Flex::doLayout(renderer);
    return;
  }

  // Step 1: estimate the canvas's virtual size so ScrollView can measure
  // content height correctly. Use our own width minus the scrollbar gutter
  // assuming the bar is shown — for large lists that estimate is exact, and
  // for small lists the only visible artifact is a few pixels of right pad.
  constexpr float kScrollbarGutter = 14.0f; // matches ScrollView's internal width + gap
  const float ourW = std::max(0.0f, width());
  const float ourH = std::max(0.0f, height());
  const float viewportW = std::max(0.0f, ourW - kScrollbarGutter);
  const float viewportH = ourH;

  m_itemCount = m_adapter->itemCount();
  const std::size_t columns =
      m_columns > 0
          ? std::max<std::size_t>(1, m_columns)
          : std::max<std::size_t>(1, static_cast<std::size_t>(std::floor(
                                         (viewportW + m_columnGap) / std::max(1.0f, m_minCellWidth + m_columnGap))));
  const float columnsF = static_cast<float>(columns);
  const float cellW = columns == 0 ? 0.0f : std::max(0.0f, (viewportW - (columnsF - 1.0f) * m_columnGap) / columnsF);
  const float cellH = m_squareCells ? cellW : m_cellHeight;
  const std::size_t rowCount = (m_itemCount + columns - 1) / columns;
  const float virtualHeight =
      rowCount == 0 ? 0.0f : (static_cast<float>(rowCount) * cellH + static_cast<float>(rowCount - 1) * m_rowGap);

  m_layoutColumns = columns;
  m_cellWidth = cellW;
  m_cellHeightResolved = cellH;
  m_virtualWidth = viewportW;
  m_virtualHeight = virtualHeight;

  m_canvas->setVirtualSize(viewportW, virtualHeight);

  // Apply any pending scrollToIndex now that we know cell geometry — this must
  // happen before ScrollView lays out so its scroll offset is current.
  if (m_pendingScrollToIndex) {
    m_pendingScrollToIndex = false;
    if (m_pendingScrollIndex < m_itemCount && columns > 0) {
      const std::size_t row = m_pendingScrollIndex / columns;
      const float targetTop = static_cast<float>(row) * (cellH + m_rowGap);
      m_scroll->setScrollOffset(targetTop);
    }
  }

  // Step 2: determine the visible row range from current scroll offset, with overscan.
  const float rowStride = cellH + m_rowGap;
  const float scrollY = m_scroll->scrollOffset();
  std::size_t firstRow = 0;
  std::size_t lastRow = 0;
  if (rowStride > 0.0f && rowCount > 0) {
    const long firstRaw = static_cast<long>(std::floor(scrollY / rowStride)) - static_cast<long>(m_overscanRows);
    const long lastRaw =
        static_cast<long>(std::ceil((scrollY + viewportH) / rowStride)) + static_cast<long>(m_overscanRows);
    firstRow = static_cast<std::size_t>(std::max<long>(0, firstRaw));
    lastRow = static_cast<std::size_t>(std::max<long>(0, std::min<long>(lastRaw, static_cast<long>(rowCount) - 1)));
  }
  const std::size_t visibleRowCount = (rowCount == 0 || lastRow < firstRow) ? 0 : (lastRow - firstRow + 1);
  const std::size_t desiredPoolSize = visibleRowCount * columns;

  // Step 3: grow the pool if needed (never shrink — avoids realloc thrash on resize).
  while (m_pool.size() < desiredPoolSize) {
    auto tile = m_adapter->createTile();
    if (tile == nullptr) {
      break;
    }
    tile->setVisible(false);
    tile->setParticipatesInLayout(false);
    Node* raw = m_canvas->addChild(std::move(tile));
    m_pool.push_back(raw);
    m_slotBoundIndex.emplace_back();
  }

  // Step 4: bind / position pool slots.
  m_visibleStartIndex = firstRow * columns;
  for (std::size_t slot = 0; slot < m_pool.size(); ++slot) {
    Node* tile = m_pool[slot];
    if (tile == nullptr) {
      continue;
    }
    const std::size_t logicalIndex = m_visibleStartIndex + slot;
    const bool active = slot < desiredPoolSize && logicalIndex < m_itemCount;
    if (!active) {
      tile->setVisible(false);
      m_slotBoundIndex[slot].reset();
      continue;
    }

    const bool selected = m_selectedIndex.has_value() && *m_selectedIndex == logicalIndex;
    const bool hovered = m_hoveredIndex.has_value() && *m_hoveredIndex == logicalIndex;
    m_adapter->bindTile(*tile, logicalIndex, selected, hovered);
    m_slotBoundIndex[slot] = logicalIndex;

    const std::size_t row = logicalIndex / columns;
    const std::size_t col = logicalIndex % columns;
    const float x = static_cast<float>(col) * (cellW + m_columnGap);
    const float y = static_cast<float>(row) * (cellH + m_rowGap);
    tile->setPosition(x, y);
    tile->setSize(cellW, cellH);
    tile->setVisible(true);
    // Canvas's doLayout is a no-op, so we lay out each pool tile explicitly
    // here — otherwise the inner glyph/label children never get measured.
    tile->layout(renderer);
  }

  // Step 5: position the input overlay across the entire virtual canvas.
  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setFrameSize(viewportW, virtualHeight);

  // Step 6: run the outer Flex layout so ScrollView lays itself out around
  // the canvas with its now-correct virtual size.
  Flex::doLayout(renderer);
}

LayoutSize VirtualGridView::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  return measureByLayout(renderer, constraints);
}

void VirtualGridView::doArrange(Renderer& renderer, const LayoutRect& rect) { arrangeByLayout(renderer, rect); }

void VirtualGridView::onScrollChanged(float /*offset*/) { markLayoutDirty(); }

void VirtualGridView::onPointerEnter(float localX, float localY) { onPointerMotion(localX, localY); }

void VirtualGridView::onPointerMotion(float localX, float localY) {
  const auto idx = indexAt(localX, localY);
  if (idx == m_hoveredIndex) {
    return;
  }
  m_hoveredIndex = idx;
  markLayoutDirty();
}

void VirtualGridView::onPointerLeave() {
  if (!m_hoveredIndex.has_value()) {
    return;
  }
  m_hoveredIndex.reset();
  markLayoutDirty();
}

void VirtualGridView::onPointerPress(float localX, float localY) {
  const auto idx = indexAt(localX, localY);
  if (!idx.has_value()) {
    return;
  }
  setSelectedIndex(idx);
  if (m_adapter != nullptr) {
    m_adapter->onActivate(*idx);
  }
}

std::optional<std::size_t> VirtualGridView::indexAt(float localX, float localY) const noexcept {
  if (m_layoutColumns == 0 || m_cellWidth <= 0.0f || m_cellHeightResolved <= 0.0f || m_itemCount == 0) {
    return std::nullopt;
  }
  const float colStride = m_cellWidth + m_columnGap;
  const float rowStride = m_cellHeightResolved + m_rowGap;
  if (localX < 0.0f || localY < 0.0f || colStride <= 0.0f || rowStride <= 0.0f) {
    return std::nullopt;
  }
  const auto colF = localX / colStride;
  const auto rowF = localY / rowStride;
  const auto col = static_cast<std::size_t>(std::floor(colF));
  const auto row = static_cast<std::size_t>(std::floor(rowF));
  if (col >= m_layoutColumns) {
    return std::nullopt;
  }
  // Reject the gutter region between cells.
  const float cellLocalX = localX - static_cast<float>(col) * colStride;
  const float cellLocalY = localY - static_cast<float>(row) * rowStride;
  if (cellLocalX > m_cellWidth || cellLocalY > m_cellHeightResolved) {
    return std::nullopt;
  }
  const std::size_t idx = row * m_layoutColumns + col;
  if (idx >= m_itemCount) {
    return std::nullopt;
  }
  return idx;
}
