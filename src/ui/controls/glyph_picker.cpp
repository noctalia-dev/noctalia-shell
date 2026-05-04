#include "ui/controls/glyph_picker.h"

#include "i18n/i18n.h"
#include "render/scene/input_area.h"
#include "ui/controls/button.h"
#include "ui/controls/glyph.h"
#include "ui/controls/glyph_registry.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/spacer.h"
#include "ui/controls/virtual_grid_view.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <memory>
#include <unordered_set>

namespace {

  void configureDialogActionButton(Button& button, float scale) {
    button.setMinHeight(Style::controlHeight * scale);
    button.setMinWidth(92.0f * scale);
    button.setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    button.setRadius(Style::radiusMd * scale);
  }

  void configureDialogCloseButton(Button& button, float scale) {
    button.setVariant(ButtonVariant::Default);
    button.setGlyph("close");
    button.setGlyphSize(Style::fontSizeBody * scale);
    button.setMinWidth(Style::controlHeightSm * scale);
    button.setMinHeight(Style::controlHeightSm * scale);
    button.setPadding(Style::spaceXs * scale);
    button.setRadius(Style::radiusMd * scale);
  }

  std::string toLowerCopy(std::string_view value) {
    std::string out(value);
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
  }

} // namespace

class GlyphGridAdapter : public VirtualGridAdapter {
public:
  struct Entry {
    std::string name;
    char32_t codepoint = 0;
  };

  GlyphGridAdapter(float chromeScale) : m_chromeScale(chromeScale) {
    const auto& tabler = GlyphRegistry::tablerIcons();
    const auto& aliases = GlyphRegistry::aliases();

    std::unordered_set<std::string> seen;
    seen.reserve(tabler.size() + aliases.size());
    m_master.reserve(tabler.size() + aliases.size());

    for (const auto& [name, codepoint] : aliases) {
      if (seen.insert(name).second) {
        m_master.push_back({name, codepoint});
      }
    }
    for (const auto& [name, codepoint] : tabler) {
      if (seen.insert(name).second) {
        m_master.push_back({name, codepoint});
      }
    }
    std::sort(m_master.begin(), m_master.end(), [](const Entry& a, const Entry& b) { return a.name < b.name; });

    m_visible.reserve(m_master.size());
    rebuildVisible({});
  }

  [[nodiscard]] std::size_t itemCount() const override { return m_visible.size(); }

  [[nodiscard]] std::unique_ptr<Node> createTile() override {
    auto tile = std::make_unique<Flex>();
    tile->setDirection(FlexDirection::Vertical);
    tile->setAlign(FlexAlign::Center);
    tile->setJustify(FlexJustify::Center);
    tile->setPadding(0.0f);
    tile->setRadius(Style::radiusMd * m_chromeScale);
    tile->clearBorder();

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyphSize(28.0f * m_chromeScale);
    Glyph* glyphRaw = glyph.get();
    tile->addChild(std::move(glyph));
    tile->setUserData(glyphRaw);
    return tile;
  }

  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override {
    if (index >= m_visible.size()) {
      tile.setVisible(false);
      return;
    }
    const Entry& entry = m_master[m_visible[index]];

    auto* flex = static_cast<Flex*>(&tile);
    auto* glyph = static_cast<Glyph*>(flex->userData());

    if (selected) {
      flex->setFill(colorSpecFromRole(ColorRole::Primary));
      if (glyph != nullptr) {
        glyph->setColor(colorSpecFromRole(ColorRole::OnPrimary));
      }
    } else if (hovered) {
      flex->setFill(colorSpecFromRole(ColorRole::Hover));
      if (glyph != nullptr) {
        glyph->setColor(colorSpecFromRole(ColorRole::OnHover));
      }
    } else {
      flex->clearFill();
      if (glyph != nullptr) {
        glyph->setColor(colorSpecFromRole(ColorRole::OnSurface));
      }
    }
    if (glyph != nullptr) {
      glyph->setGlyph(entry.name);
    }
  }

  void rebuildVisible(std::string_view filter) {
    m_visible.clear();
    if (filter.empty()) {
      m_visible.reserve(m_master.size());
      for (std::size_t i = 0; i < m_master.size(); ++i) {
        m_visible.push_back(i);
      }
      return;
    }
    const std::string needle = toLowerCopy(filter);
    for (std::size_t i = 0; i < m_master.size(); ++i) {
      // Names in the registry are already lowercase; no need to lower each entry.
      if (m_master[i].name.find(needle) != std::string::npos) {
        m_visible.push_back(i);
      }
    }
  }

  [[nodiscard]] std::optional<std::size_t> indexOfName(std::string_view name) const {
    for (std::size_t i = 0; i < m_visible.size(); ++i) {
      if (m_master[m_visible[i]].name == name) {
        return i;
      }
    }
    return std::nullopt;
  }

  [[nodiscard]] const Entry& entryAt(std::size_t visibleIndex) const { return m_master[m_visible[visibleIndex]]; }

private:
  float m_chromeScale = 1.0f;
  std::vector<Entry> m_master;
  std::vector<std::size_t> m_visible;
};

GlyphPicker::GlyphPicker(float chromeScale) : m_chromeScale(std::max(0.1f, chromeScale)) {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(Style::spaceMd * m_chromeScale);
  setPadding(Style::spaceSm * m_chromeScale);

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setGap(Style::spaceSm * m_chromeScale);

  auto title = std::make_unique<Label>();
  title->setText(i18n::tr("ui.dialogs.glyph-picker.title"));
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * m_chromeScale);
  title->setColor(colorSpecFromRole(ColorRole::Primary));
  title->setStableBaseline(true);
  m_title = static_cast<Label*>(header->addChild(std::move(title)));

  header->addChild(std::make_unique<Spacer>());

  auto closeButton = std::make_unique<Button>();
  configureDialogCloseButton(*closeButton, m_chromeScale);
  closeButton->setOnClick([this]() {
    if (m_onCancel) {
      m_onCancel();
    }
  });
  header->addChild(std::move(closeButton));

  addChild(std::move(header));

  auto searchInput = std::make_unique<Input>();
  searchInput->setControlHeight(Style::controlHeight * m_chromeScale);
  searchInput->setHorizontalPadding(Style::spaceMd * m_chromeScale);
  searchInput->setFontSize(Style::fontSizeBody * m_chromeScale);
  searchInput->setPlaceholder(i18n::tr("ui.dialogs.glyph-picker.search-placeholder"));
  searchInput->setClearButtonEnabled(true);
  searchInput->setOnChange([this](const std::string& value) { applyFilter(value); });
  m_searchInput = static_cast<Input*>(addChild(std::move(searchInput)));

  m_adapter = std::make_unique<GlyphGridAdapter>(m_chromeScale);

  auto grid = std::make_unique<VirtualGridView>();
  grid->setMinCellWidth(56.0f * m_chromeScale);
  grid->setSquareCells(true);
  grid->setColumnGap(Style::spaceXs * m_chromeScale);
  grid->setRowGap(Style::spaceXs * m_chromeScale);
  grid->setOverscanRows(2);
  grid->setFlexGrow(1.0f);
  grid->setAdapter(m_adapter.get());
  grid->setOnSelectionChanged([this](std::optional<std::size_t>) { applySelectionToButton(); });
  m_grid = static_cast<VirtualGridView*>(addChild(std::move(grid)));

  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setJustify(FlexJustify::End);
  actions->setGap(Style::spaceSm * m_chromeScale);

  auto cancel = std::make_unique<Button>();
  cancel->setText(i18n::tr("common.actions.cancel"));
  cancel->setVariant(ButtonVariant::Secondary);
  configureDialogActionButton(*cancel, m_chromeScale);
  cancel->setOnClick([this]() {
    if (m_onCancel) {
      m_onCancel();
    }
  });
  actions->addChild(std::move(cancel));

  auto apply = std::make_unique<Button>();
  apply->setText(i18n::tr("common.actions.apply"));
  apply->setVariant(ButtonVariant::Accent);
  configureDialogActionButton(*apply, m_chromeScale);
  apply->setOnClick([this]() {
    if (!m_onApply) {
      return;
    }
    const auto result = currentResult();
    if (result.has_value()) {
      m_onApply(*result);
    }
  });
  m_applyButton = static_cast<Button*>(actions->addChild(std::move(apply)));

  addChild(std::move(actions));

  applySelectionToButton();
}

GlyphPicker::~GlyphPicker() {
  // Detach the adapter before m_grid (a child) gets destroyed by ~Node, since
  // VirtualGridView's pool tiles were minted by m_adapter and reference it.
  if (m_grid != nullptr) {
    m_grid->setAdapter(nullptr);
  }
}

void GlyphPicker::setTitle(std::string_view title) {
  if (m_title != nullptr) {
    m_title->setText(title.empty() ? i18n::tr("ui.dialogs.glyph-picker.title") : std::string(title));
  }
}

void GlyphPicker::setInitialGlyph(std::optional<std::string> name) {
  m_pendingInitialGlyph = std::move(name);
  m_pendingInitialApplied = false;
  markLayoutDirty();
}

InputArea* GlyphPicker::initialFocusArea() const noexcept {
  return m_searchInput != nullptr ? m_searchInput->inputArea() : nullptr;
}

std::optional<GlyphPickerResult> GlyphPicker::currentResult() const {
  if (m_grid == nullptr || m_adapter == nullptr) {
    return std::nullopt;
  }
  const auto idx = m_grid->selectedIndex();
  if (!idx.has_value() || *idx >= m_adapter->itemCount()) {
    return std::nullopt;
  }
  const auto& entry = m_adapter->entryAt(*idx);
  return GlyphPickerResult{.name = entry.name, .codepoint = entry.codepoint};
}

void GlyphPicker::doLayout(Renderer& renderer) {
  Flex::doLayout(renderer);

  if (!m_pendingInitialApplied && m_pendingInitialGlyph.has_value() && m_grid != nullptr && m_adapter != nullptr) {
    if (const auto idx = m_adapter->indexOfName(*m_pendingInitialGlyph); idx.has_value()) {
      m_grid->setSelectedIndex(*idx);
      m_grid->scrollToIndex(*idx);
    }
    m_pendingInitialApplied = true;
  }
}

LayoutSize GlyphPicker::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  return measureByLayout(renderer, constraints);
}

void GlyphPicker::doArrange(Renderer& renderer, const LayoutRect& rect) { arrangeByLayout(renderer, rect); }

void GlyphPicker::applyFilter(const std::string& filter) {
  if (m_adapter == nullptr || m_grid == nullptr) {
    return;
  }
  const auto previousResult = currentResult();
  m_adapter->rebuildVisible(filter);
  // Drop selection if the previously selected name is no longer visible.
  if (previousResult.has_value()) {
    if (const auto idx = m_adapter->indexOfName(previousResult->name); idx.has_value()) {
      m_grid->setSelectedIndex(*idx);
    } else {
      m_grid->setSelectedIndex(std::nullopt);
    }
  }
  m_grid->notifyDataChanged();
  m_grid->scrollView().setScrollOffset(0.0f);
}

void GlyphPicker::applySelectionToButton() {
  if (m_applyButton == nullptr) {
    return;
  }
  const bool hasSelection = m_grid != nullptr && m_grid->selectedIndex().has_value();
  m_applyButton->setEnabled(hasSelection);
}

float GlyphPicker::preferredDialogWidth(float scale) { return 540.0f * std::max(0.1f, scale); }

float GlyphPicker::preferredDialogHeight(float scale) { return 540.0f * std::max(0.1f, scale); }
