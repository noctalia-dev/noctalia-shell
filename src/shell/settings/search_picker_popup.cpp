#include "shell/settings/search_picker_popup.h"

#include "core/deferred_call.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <utility>

namespace settings {

  namespace {

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

  } // namespace

  SearchPickerPopup::~SearchPickerPopup() { destroyPopup(); }

  void SearchPickerPopup::initialize(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext) {
    initializeBase(wayland, config, renderContext);
  }

  void SearchPickerPopup::setOnSelect(SelectCallback callback) { m_onSelect = std::move(callback); }

  void SearchPickerPopup::setOnDismissed(std::function<void()> callback) { m_onDismissed = std::move(callback); }

  void SearchPickerPopup::open(xdg_surface* parentXdgSurface, wl_output* output, std::uint32_t serial,
                               wl_surface* parentWlSurface, std::uint32_t parentWidth, std::uint32_t parentHeight,
                               const std::string& title, const std::vector<SearchPickerOption>& options,
                               const std::string& selectedValue, const std::string& placeholder,
                               const std::string& emptyText, float scale) {
    if (parentXdgSurface == nullptr || parentWlSurface == nullptr || options.empty()) {
      return;
    }

    if (isOpen()) {
      close();
    }

    m_scale = std::max(0.1f, scale);
    m_title = title;
    m_options = options;
    m_selectedValue = selectedValue;
    m_placeholder = placeholder;
    m_emptyText = emptyText;
    m_root = nullptr;
    m_searchPicker = nullptr;

    const float panelWidth = 420.0f * m_scale;
    const float panelHeight = 380.0f * m_scale;
    const auto cfg =
        centeredPopupConfig(parentWidth, parentHeight, static_cast<std::uint32_t>(std::max(1.0f, panelWidth)),
                            static_cast<std::uint32_t>(std::max(1.0f, panelHeight)), serial);

    if (!openPopupAsChild(cfg, parentXdgSurface, parentWlSurface, output)) {
      close();
    }
  }

  void SearchPickerPopup::close() { destroyPopup(); }

  bool SearchPickerPopup::isOpen() const noexcept { return DialogPopupHost::isOpen(); }

  bool SearchPickerPopup::onPointerEvent(const PointerEvent& event) { return DialogPopupHost::onPointerEvent(event); }

  void SearchPickerPopup::onKeyboardEvent(const KeyboardEvent& event) { DialogPopupHost::onKeyboardEvent(event); }

  wl_surface* SearchPickerPopup::wlSurface() const noexcept { return DialogPopupHost::wlSurface(); }

  void SearchPickerPopup::populateContent(Node* contentParent, std::uint32_t /*width*/, std::uint32_t /*height*/) {
    const float panelPadding = Style::spaceSm * m_scale;
    const float panelGap = Style::spaceSm * m_scale;

    auto root = std::make_unique<Flex>();
    root->setDirection(FlexDirection::Vertical);
    root->setAlign(FlexAlign::Stretch);
    root->setGap(panelGap);
    root->setPadding(panelPadding);
    m_root = root.get();

    auto header = std::make_unique<Flex>();
    header->setDirection(FlexDirection::Horizontal);
    header->setAlign(FlexAlign::Center);
    header->setGap(Style::spaceSm * m_scale);

    auto titleLabel = std::make_unique<Label>();
    titleLabel->setText(m_title);
    titleLabel->setFontSize(Style::fontSizeBody * m_scale);
    titleLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
    titleLabel->setBold(true);
    header->addChild(std::move(titleLabel));

    auto spacer = std::make_unique<Flex>();
    spacer->setFlexGrow(1.0f);
    header->addChild(std::move(spacer));

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

    auto picker = std::make_unique<SearchPicker>();
    if (!m_placeholder.empty()) {
      picker->setPlaceholder(m_placeholder);
    }
    if (!m_emptyText.empty()) {
      picker->setEmptyText(m_emptyText);
    }
    picker->clearFill();
    picker->clearBorder();
    picker->setRadius(0.0f);
    picker->setPadding(0.0f);
    picker->setFlexGrow(1.0f);
    picker->setSelectedValue(m_selectedValue);
    picker->setOptions(m_options);
    picker->setOnActivated([this](const SearchPickerOption& option) {
      if (option.value.empty()) {
        return;
      }
      if (m_onSelect) {
        m_onSelect(option.value);
      }
      DeferredCall::callLater([this]() { close(); });
    });
    picker->setOnCancel([this]() { DeferredCall::callLater([this]() { close(); }); });
    m_searchPicker = picker.get();
    root->addChild(std::move(picker));

    contentParent->addChild(std::move(root));
  }

  void SearchPickerPopup::layoutSheet(float contentWidth, float contentHeight) {
    if (m_root == nullptr || renderContext() == nullptr) {
      return;
    }
    m_root->setSize(contentWidth, contentHeight);
    m_root->layout(*renderContext());
  }

  void SearchPickerPopup::cancelToFacade() {}

  InputArea* SearchPickerPopup::initialFocusArea() {
    return m_searchPicker != nullptr ? m_searchPicker->filterInputArea() : nullptr;
  }

  void SearchPickerPopup::onSheetClose() {
    m_options.clear();
    m_root = nullptr;
    m_searchPicker = nullptr;
    if (m_onDismissed) {
      DeferredCall::callLater([callback = m_onDismissed]() { callback(); });
    }
  }

} // namespace settings
