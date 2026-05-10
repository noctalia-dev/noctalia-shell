#include "shell/launcher/launcher_result_adapter.h"

#include "render/core/async_texture_cache.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <utility>

namespace {

  constexpr float kIconSize = 32.0f;

  class LauncherResultRow final : public Node {
  public:
    LauncherResultRow(float scale, AsyncTextureCache* asyncTextures)
        : m_scale(scale), m_rowHeight(launcherResultRowHeight(scale)), m_asyncTextures(asyncTextures) {
      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Center);
      row->setGap(Style::spaceMd * scale);
      row->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      row->setRadius(Style::radiusMd * scale);
      m_row = static_cast<Flex*>(addChild(std::move(row)));

      auto actionLabel = std::make_unique<Label>();
      actionLabel->setFontSize(kIconSize * scale);
      actionLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
      actionLabel->setVisible(false);
      m_actionLabel = static_cast<Label*>(m_row->addChild(std::move(actionLabel)));

      auto image = std::make_unique<Image>();
      image->setSize(kIconSize * scale, kIconSize * scale);
      image->setVisible(false);
      m_image = static_cast<Image*>(m_row->addChild(std::move(image)));

      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyphSize(kIconSize * scale);
      glyph->setColor(colorSpecFromRole(ColorRole::OnSurface));
      glyph->setVisible(false);
      m_glyph = static_cast<Glyph*>(m_row->addChild(std::move(glyph)));

      m_image->setAsyncReadyCallback([this]() {
        if (m_actionTextVisible || m_iconPath.empty() || m_image == nullptr || m_glyph == nullptr ||
            !m_image->hasImage()) {
          return;
        }
        m_image->setVisible(true);
        m_glyph->setVisible(false);
      });

      auto textCol = std::make_unique<Flex>();
      textCol->setDirection(FlexDirection::Vertical);
      textCol->setAlign(FlexAlign::Start);
      textCol->setGap(Style::spaceXs * 0.5f * scale);
      textCol->setFlexGrow(1.0f);
      m_textCol = static_cast<Flex*>(m_row->addChild(std::move(textCol)));

      auto title = std::make_unique<Label>();
      title->setFontSize(Style::fontSizeBody * scale);
      title->setBold(true);
      title->setColor(colorSpecFromRole(ColorRole::OnSurface));
      title->setMaxLines(1);
      m_title = static_cast<Label*>(m_textCol->addChild(std::move(title)));

      auto subtitle = std::make_unique<Label>();
      subtitle->setCaptionStyle();
      subtitle->setFontSize(Style::fontSizeCaption * scale);
      subtitle->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      subtitle->setMaxLines(1);
      m_subtitle = static_cast<Label*>(m_textCol->addChild(std::move(subtitle)));
    }

    void bind(Renderer& renderer, const LauncherResult& result, float width, bool selected, bool hovered) {
      m_selected = selected;
      m_hovered = hovered;
      m_iconPath = result.iconPath;
      m_fallbackGlyph = result.glyphName.empty() ? "app-window" : result.glyphName;
      m_iconTargetSize = static_cast<int>(std::round(kIconSize * m_scale));
      m_actionTextVisible = !result.actionText.empty();

      setSize(width, m_rowHeight);
      m_row->setFrameSize(width, m_rowHeight);

      m_actionLabel->setVisible(false);
      m_image->setVisible(false);
      m_glyph->setVisible(false);

      if (m_actionTextVisible) {
        m_actionLabel->setText(result.actionText);
        m_actionLabel->setSize(kIconSize * m_scale, kIconSize * m_scale);
        m_actionLabel->setVisible(true);
        m_image->clear(renderer);
      } else if (!m_iconPath.empty()) {
        const bool ready = refreshAsyncIcon(renderer);
        m_image->setVisible(ready);
        m_glyph->setGlyph(m_fallbackGlyph);
        m_glyph->setVisible(!ready);
      } else {
        m_image->clear(renderer);
        m_glyph->setGlyph(m_fallbackGlyph);
        m_glyph->setVisible(true);
      }

      const float textWidth =
          std::max(0.0f, width - kIconSize * m_scale - Style::spaceSm * m_scale * 2.0f - Style::spaceMd * m_scale);
      m_title->setText(result.title);
      m_title->setMaxWidth(textWidth);

      if (result.subtitle.empty()) {
        m_subtitle->setVisible(false);
        m_subtitle->setText("");
      } else {
        m_subtitle->setVisible(true);
        m_subtitle->setText(result.subtitle);
        m_subtitle->setMaxWidth(textWidth);
      }

      applyVisualState();
    }

    bool refreshAsyncIcon(Renderer& renderer) {
      if (m_actionTextVisible || m_iconPath.empty()) {
        return false;
      }

      bool ready = false;
      if (m_asyncTextures != nullptr) {
        ready = m_image->setSourceFileAsync(renderer, *m_asyncTextures, m_iconPath, m_iconTargetSize, true);
      } else {
        ready = m_image->setSourceFile(renderer, m_iconPath, m_iconTargetSize, true);
      }

      m_image->setSize(kIconSize * m_scale, kIconSize * m_scale);
      m_image->setVisible(ready);
      m_glyph->setGlyph(m_fallbackGlyph);
      m_glyph->setVisible(!ready);
      return ready;
    }

  protected:
    void doLayout(Renderer& renderer) override {
      if (!m_actionTextVisible && !m_iconPath.empty()) {
        (void)refreshAsyncIcon(renderer);
      }
      Node::doLayout(renderer);
    }

  private:
    void applyVisualState() {
      if (m_selected) {
        m_row->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
      } else if (m_hovered) {
        m_row->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.45f));
      } else {
        m_row->setFill(rgba(0, 0, 0, 0));
      }
    }

    float m_scale = 1.0f;
    float m_rowHeight = 0.0f;
    bool m_selected = false;
    bool m_hovered = false;
    Flex* m_row = nullptr;
    Label* m_actionLabel = nullptr;
    Image* m_image = nullptr;
    Glyph* m_glyph = nullptr;
    Flex* m_textCol = nullptr;
    Label* m_title = nullptr;
    Label* m_subtitle = nullptr;
    AsyncTextureCache* m_asyncTextures = nullptr;
    std::string m_iconPath;
    std::string m_fallbackGlyph;
    int m_iconTargetSize = 0;
    bool m_actionTextVisible = false;
  };

} // namespace

float launcherResultRowHeight(float scale) {
  const float paddingY = Style::spaceXs * scale;
  const float textGap = Style::spaceXs * scale;
  const float titleHeight = Style::fontSizeBody * scale * 1.35f;
  const float subtitleHeight = Style::fontSizeCaption * scale * 1.25f;
  const float textHeight = titleHeight + textGap + subtitleHeight;
  return std::ceil(std::max(kIconSize * scale, textHeight) + paddingY * 2.0f);
}

LauncherResultAdapter::LauncherResultAdapter(float scale, AsyncTextureCache* cache) : m_scale(scale), m_cache(cache) {}

void LauncherResultAdapter::setResults(const std::vector<LauncherResult>* results) { m_results = results; }

void LauncherResultAdapter::setRenderer(Renderer* renderer) { m_renderer = renderer; }

void LauncherResultAdapter::setOnActivate(ActivateCallback callback) { m_onActivate = std::move(callback); }

void LauncherResultAdapter::setOnSecondaryActivate(SecondaryActivateCallback callback) {
  m_onSecondaryActivate = std::move(callback);
}

std::size_t LauncherResultAdapter::itemCount() const { return m_results == nullptr ? 0u : m_results->size(); }

std::unique_ptr<Node> LauncherResultAdapter::createTile() {
  return std::make_unique<LauncherResultRow>(m_scale, m_cache);
}

void LauncherResultAdapter::bindTile(Node& tile, std::size_t index, bool selected, bool hovered) {
  if (m_renderer == nullptr || m_results == nullptr || index >= m_results->size()) {
    return;
  }
  auto* row = static_cast<LauncherResultRow*>(&tile);
  row->bind(*m_renderer, (*m_results)[index], tile.width(), selected, hovered);
}

void LauncherResultAdapter::onActivate(std::size_t index) {
  if (m_onActivate) {
    m_onActivate(index);
  }
}

void LauncherResultAdapter::onSecondaryActivate(std::size_t index, float anchorX, float anchorY) {
  if (m_onSecondaryActivate) {
    m_onSecondaryActivate(index, anchorX, anchorY);
  }
}
