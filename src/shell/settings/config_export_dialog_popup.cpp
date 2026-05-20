#include "shell/settings/config_export_dialog_popup.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/palette.h"
#include "ui/popup_chrome.h"
#include "ui/style.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <utility>

namespace settings {
  namespace {

    constexpr float kPopupWidth = 560.0f;
    constexpr float kInitialPopupHeight = 320.0f;
    constexpr float kParentMargin = 48.0f;

    PopupSurfaceConfig centeredPopupConfig(std::uint32_t parentWidth, std::uint32_t parentHeight, std::uint32_t width,
                                           std::uint32_t height, std::uint32_t serial) {
      return PopupSurfaceConfig{
          .anchorX = static_cast<std::int32_t>(parentWidth / 2),
          .anchorY = static_cast<std::int32_t>(parentHeight / 2),
          .anchorWidth = 1,
          .anchorHeight = 1,
          .width = std::max<std::uint32_t>(1, width),
          .height = std::max<std::uint32_t>(1, height),
          .anchor = XDG_POSITIONER_ANCHOR_NONE,
          .gravity = XDG_POSITIONER_GRAVITY_NONE,
          .constraintAdjustment =
              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y,
          .offsetX = 0,
          .offsetY = 0,
          .serial = serial,
          .grab = true,
      };
    }

    std::unique_ptr<Label> makeLabel(std::string text, float fontSize, ColorSpec color, bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

  } // namespace

  ConfigExportDialogPopup::~ConfigExportDialogPopup() { destroyPopup(); }

  void ConfigExportDialogPopup::initialize(WaylandConnection& wayland, ConfigService& config,
                                           RenderContext& renderContext) {
    initializeBase(wayland, config, renderContext);
  }

  void ConfigExportDialogPopup::open(xdg_surface* parentXdgSurface, wl_output* output, std::uint32_t serial,
                                     wl_surface* parentWlSurface, std::uint32_t parentWidth, std::uint32_t parentHeight,
                                     float scale, ExportCallback callback) {
    if (parentXdgSurface == nullptr || parentWlSurface == nullptr) {
      return;
    }

    if (isOpen()) {
      close();
    }

    m_scale = std::max(0.1f, scale);
    m_mode = ConfigExportMode::MergedUser;
    m_callback = std::move(callback);
    m_root = nullptr;
    m_mergedRadio = nullptr;
    m_fullRadio = nullptr;
    m_parentHeight = parentHeight;

    const float popupWidth = kPopupWidth * m_scale;
    const float popupHeight = kInitialPopupHeight * m_scale;
    const auto cfg =
        centeredPopupConfig(parentWidth, parentHeight, static_cast<std::uint32_t>(std::max(1.0f, popupWidth)),
                            static_cast<std::uint32_t>(std::max(1.0f, popupHeight)), serial);

    if (!openPopupAsChild(cfg, parentXdgSurface, parentWlSurface, output)) {
      close();
    }
  }

  void ConfigExportDialogPopup::close() { destroyPopup(); }

  bool ConfigExportDialogPopup::isOpen() const noexcept { return DialogPopupHost::isOpen(); }

  wl_surface* ConfigExportDialogPopup::wlSurface() const noexcept { return DialogPopupHost::wlSurface(); }

  void ConfigExportDialogPopup::setMode(ConfigExportMode mode) {
    m_mode = mode;
    if (m_mergedRadio != nullptr) {
      m_mergedRadio->setChecked(mode == ConfigExportMode::MergedUser);
    }
    if (m_fullRadio != nullptr) {
      m_fullRadio->setChecked(mode == ConfigExportMode::FullEffective);
    }
    requestRedraw();
  }

  void ConfigExportDialogPopup::accept() {
    const ConfigExportMode mode = m_mode;
    ExportCallback callback = std::move(m_callback);
    closeAfterAccept();
    if (callback) {
      callback(mode);
    }
  }

  std::unique_ptr<Flex> ConfigExportDialogPopup::makeOption(ConfigExportMode mode, const std::string& title,
                                                            const std::string& description) {
    auto option = std::make_unique<Flex>();
    option->setDirection(FlexDirection::Horizontal);
    option->setAlign(FlexAlign::Start);
    option->setGap(Style::spaceSm * m_scale);
    option->setPadding(Style::spaceSm * m_scale);
    option->setRadius(Style::scaledRadiusMd(m_scale));
    option->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.45f));
    option->setBorder(colorSpecFromRole(ColorRole::Outline, 0.55f), Style::borderWidth);
    option->setFillWidth(true);

    auto radio = std::make_unique<RadioButton>();
    radio->setScale(m_scale);
    radio->setChecked(m_mode == mode);
    radio->setOnChange([this, mode](bool checked) {
      if (checked) {
        setMode(mode);
      }
    });
    RadioButton* radioPtr = radio.get();
    option->addChild(std::move(radio));

    auto copy = std::make_unique<Flex>();
    copy->setDirection(FlexDirection::Vertical);
    copy->setAlign(FlexAlign::Stretch);
    copy->setGap(Style::spaceXs * m_scale);
    copy->setFlexGrow(1.0f);

    auto titleLabel = makeLabel(title, Style::fontSizeBody * m_scale, colorSpecFromRole(ColorRole::OnSurface), true);
    titleLabel->setMaxLines(1);
    copy->addChild(std::move(titleLabel));

    auto descLabel =
        makeLabel(description, Style::fontSizeCaption * m_scale, colorSpecFromRole(ColorRole::OnSurfaceVariant));
    descLabel->setMaxWidth((kPopupWidth - 92.0f) * m_scale);
    descLabel->setMaxLines(3);
    copy->addChild(std::move(descLabel));
    option->addChild(std::move(copy));

    if (mode == ConfigExportMode::MergedUser) {
      m_mergedRadio = radioPtr;
    } else {
      m_fullRadio = radioPtr;
    }
    return option;
  }

  void ConfigExportDialogPopup::populateContent(Node* contentParent, std::uint32_t /*width*/,
                                                std::uint32_t /*height*/) {
    const float popupPadding = Style::spaceMd * m_scale;
    const float popupGap = Style::spaceMd * m_scale;

    auto root = std::make_unique<Flex>();
    root->setDirection(FlexDirection::Vertical);
    root->setAlign(FlexAlign::Stretch);
    root->setGap(popupGap);
    root->setPadding(popupPadding);
    m_root = root.get();

    auto header = std::make_unique<Flex>();
    header->setDirection(FlexDirection::Horizontal);
    header->setAlign(FlexAlign::Center);
    header->setGap(Style::spaceSm * m_scale);

    auto title = makeLabel(i18n::tr("settings.export-config.title"), Style::fontSizeTitle * m_scale,
                           colorSpecFromRole(ColorRole::OnSurface), true);
    title->setFlexGrow(1.0f);
    header->addChild(std::move(title));

    auto closeBtn = std::make_unique<Button>();
    closeBtn->setGlyph("close");
    closeBtn->setVariant(ButtonVariant::Default);
    closeBtn->setGlyphSize(Style::fontSizeBody * m_scale);
    closeBtn->setMinWidth(Style::controlHeightSm * m_scale);
    closeBtn->setMinHeight(Style::controlHeightSm * m_scale);
    closeBtn->setPadding(Style::spaceXs * m_scale);
    closeBtn->setRadius(Style::scaledRadiusMd(m_scale));
    closeBtn->setOnClick([this]() { DeferredCall::callLater([this]() { close(); }); });
    header->addChild(std::move(closeBtn));
    root->addChild(std::move(header));

    auto options = std::make_unique<Flex>();
    options->setDirection(FlexDirection::Vertical);
    options->setAlign(FlexAlign::Stretch);
    options->setGap(Style::spaceSm * m_scale);
    options->addChild(makeOption(ConfigExportMode::MergedUser, i18n::tr("settings.export-config.merged-user-title"),
                                 i18n::tr("settings.export-config.merged-user-description")));
    options->addChild(makeOption(ConfigExportMode::FullEffective,
                                 i18n::tr("settings.export-config.full-effective-title"),
                                 i18n::tr("settings.export-config.full-effective-description")));
    root->addChild(std::move(options));

    auto footer = std::make_unique<Flex>();
    footer->setDirection(FlexDirection::Horizontal);
    footer->setAlign(FlexAlign::Center);
    footer->setJustify(FlexJustify::End);
    footer->setGap(Style::spaceSm * m_scale);

    auto cancelBtn = std::make_unique<Button>();
    cancelBtn->setText(i18n::tr("common.actions.cancel"));
    cancelBtn->setVariant(ButtonVariant::Ghost);
    cancelBtn->setFontSize(Style::fontSizeBody * m_scale);
    cancelBtn->setMinHeight(Style::controlHeight * m_scale);
    cancelBtn->setPadding(Style::spaceXs * m_scale, Style::spaceMd * m_scale);
    cancelBtn->setRadius(Style::scaledRadiusMd(m_scale));
    cancelBtn->setOnClick([this]() { DeferredCall::callLater([this]() { close(); }); });
    footer->addChild(std::move(cancelBtn));

    auto exportBtn = std::make_unique<Button>();
    exportBtn->setText(i18n::tr("settings.export-config.export"));
    exportBtn->setVariant(ButtonVariant::Primary);
    exportBtn->setFontSize(Style::fontSizeBody * m_scale);
    exportBtn->setMinHeight(Style::controlHeight * m_scale);
    exportBtn->setPadding(Style::spaceXs * m_scale, Style::spaceMd * m_scale);
    exportBtn->setRadius(Style::scaledRadiusMd(m_scale));
    exportBtn->setOnClick([this]() { DeferredCall::callLater([this]() { accept(); }); });
    footer->addChild(std::move(exportBtn));
    root->addChild(std::move(footer));

    contentParent->addChild(std::move(root));
  }

  void ConfigExportDialogPopup::layoutSheet(float contentWidth, float contentHeight) {
    if (m_root == nullptr || renderContext() == nullptr || m_surface == nullptr) {
      return;
    }

    Renderer& renderer = *renderContext();
    const float pad = computePadding(uiScale());
    const float panelW = kPopupWidth * m_scale;

    float cw = std::max(1.0f, contentWidth);
    float ch = std::max(1.0f, contentHeight);

    LayoutSize pref = m_root->measure(renderer, LayoutConstraints::available(cw, 1.0e6f));
    const float panelH = std::ceil(pref.height + pad * 2.0f);
    const ShellConfig::ShadowConfig shadow =
        config() != nullptr ? config()->config().shell.shadow : ShellConfig::ShadowConfig{};
    const auto geo = popup_chrome::computeGeometry(panelW, panelH, shadow);
    const float maxOuterHeight =
        m_parentHeight > 0 ? std::max(1.0f, static_cast<float>(m_parentHeight) - (kParentMargin * m_scale)) : 1.0e6f;
    const std::uint32_t nextHeight =
        static_cast<std::uint32_t>(std::max(1.0f, std::min(static_cast<float>(geo.surfaceHeight), maxOuterHeight)));
    const std::uint32_t nextWidth = geo.surfaceWidth;

    if (m_surface->height() != nextHeight || m_surface->width() != nextWidth) {
      m_surface->resize(nextWidth, nextHeight);
      syncSceneGeometryFromSurface();
      cw = std::max(1.0f, m_chrome.contentWidth - pad * 2.0f);
      ch = std::max(1.0f, m_chrome.contentHeight - pad * 2.0f);
      pref = m_root->measure(renderer, LayoutConstraints::available(cw, 1.0e6f));
    }

    const float sheetH = std::max(1.0f, std::min(pref.height, ch));
    m_root->arrange(renderer, LayoutRect{.x = 0.0f, .y = 0.0f, .width = cw, .height = sheetH});
  }

  void ConfigExportDialogPopup::cancelToFacade() {}

  InputArea* ConfigExportDialogPopup::initialFocusArea() { return nullptr; }

} // namespace settings
