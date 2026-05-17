#include "shell/settings/widget_add_popup.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "i18n/i18n.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/settings/widget_settings_registry.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>

namespace settings {
  namespace {

    std::string laneLabel(std::string_view lane) {
      if (lane == "start") {
        return i18n::tr("settings.entities.widget.lanes.start");
      }
      if (lane == "center") {
        return i18n::tr("settings.entities.widget.lanes.center");
      }
      if (lane == "end") {
        return i18n::tr("settings.entities.widget.lanes.end");
      }
      return std::string(lane);
    }

    std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ColorSpec& color, bool bold = false) {
      auto label = std::make_unique<Label>();
      label->setText(text);
      label->setFontSize(fontSize);
      label->setColor(color);
      label->setBold(bold);
      return label;
    }

    void sortSearchOptions(std::vector<SearchPickerOption>& options) {
      std::sort(options.begin(), options.end(), [](const SearchPickerOption& a, const SearchPickerOption& b) {
        const std::string aLabel = StringUtils::toLower(a.label);
        const std::string bLabel = StringUtils::toLower(b.label);
        if (aLabel == bLabel) {
          return a.value < b.value;
        }
        return aLabel < bLabel;
      });
    }

    void collectWidgetReferenceNames(const std::vector<std::string>& widgets, std::unordered_set<std::string>& seen) {
      for (const auto& widget : widgets) {
        seen.insert(widget);
      }
    }

    bool widgetReferenceNameExists(const Config& cfg, std::string_view name) {
      const std::string key(name);
      if (isBuiltInWidgetType(name) || cfg.widgets.contains(key)) {
        return true;
      }

      std::unordered_set<std::string> seen;
      for (const auto& bar : cfg.bars) {
        collectWidgetReferenceNames(bar.startWidgets, seen);
        collectWidgetReferenceNames(bar.centerWidgets, seen);
        collectWidgetReferenceNames(bar.endWidgets, seen);
        for (const auto& ovr : bar.monitorOverrides) {
          if (ovr.startWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.startWidgets, seen);
          }
          if (ovr.centerWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.centerWidgets, seen);
          }
          if (ovr.endWidgets.has_value()) {
            collectWidgetReferenceNames(*ovr.endWidgets, seen);
          }
        }
      }
      return seen.contains(key);
    }

    bool isValidWidgetInstanceId(std::string_view id) {
      if (id.empty()) {
        return false;
      }
      for (const unsigned char c : id) {
        if (!std::isalnum(c) && c != '_' && c != '-') {
          return false;
        }
      }
      return true;
    }

    std::string normalizedWidgetInstanceBase(std::string_view type) {
      std::string out;
      out.reserve(type.size());
      bool lastUnderscore = false;
      for (const unsigned char c : type) {
        if (std::isalnum(c)) {
          out.push_back(static_cast<char>(std::tolower(c)));
          lastUnderscore = false;
        } else if (!lastUnderscore && !out.empty()) {
          out.push_back('_');
          lastUnderscore = true;
        }
      }
      while (!out.empty() && out.back() == '_') {
        out.pop_back();
      }
      return out.empty() ? std::string("widget") : out;
    }

    std::string nextWidgetInstanceId(const Config& cfg, std::string_view type) {
      const std::string base = normalizedWidgetInstanceBase(type);
      for (std::size_t index = 2; index < 10000; ++index) {
        const std::string candidate = base + "_" + std::to_string(index);
        if (!widgetReferenceNameExists(cfg, candidate)) {
          return candidate;
        }
      }
      return base + "_custom";
    }

    std::string trimmedText(std::string_view text) {
      std::size_t start = 0;
      while (start < text.size() && std::isspace(static_cast<unsigned char>(text[start]))) {
        ++start;
      }

      std::size_t end = text.size();
      while (end > start && std::isspace(static_cast<unsigned char>(text[end - 1]))) {
        --end;
      }

      return std::string(text.substr(start, end - start));
    }

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

  WidgetAddPopup::~WidgetAddPopup() { destroyPopup(); }

  void WidgetAddPopup::initialize(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext) {
    initializeBase(wayland, config, renderContext);
  }

  void WidgetAddPopup::setOnSelect(SelectCallback callback) { m_onSelect = std::move(callback); }

  void WidgetAddPopup::setOnDismissed(std::function<void()> callback) { m_onDismissed = std::move(callback); }

  void WidgetAddPopup::open(xdg_surface* parentXdgSurface, wl_output* output, std::uint32_t serial,
                            wl_surface* parentWlSurface, std::uint32_t parentWidth, std::uint32_t parentHeight,
                            const std::vector<std::string>& lanePath, const Config& config, float scale) {
    if (parentXdgSurface == nullptr || parentWlSurface == nullptr) {
      return;
    }

    const auto pickerEntries = widgetPickerEntries(config);
    std::vector<SearchPickerOption> normalOptions;
    std::vector<SearchPickerOption> instanceOptions;
    normalOptions.reserve(pickerEntries.size());
    instanceOptions.reserve(pickerEntries.size());

    for (const auto& entry : pickerEntries) {
      normalOptions.push_back(SearchPickerOption{
          .value = entry.value, .label = entry.label, .description = entry.description, .enabled = true});

      if (entry.kind != WidgetReferenceKind::BuiltIn) {
        continue;
      }
      for (const auto& spec : widgetTypeSpecs()) {
        if (spec.type != entry.value || !spec.supportsMultipleInstances) {
          continue;
        }
        instanceOptions.push_back(SearchPickerOption{
            .value = entry.value,
            .label = entry.label,
            .description = i18n::tr("settings.entities.widget.picker.instance-description", "type", entry.value),
            .enabled = true,
        });
        break;
      }
    }

    if (normalOptions.empty()) {
      return;
    }

    sortSearchOptions(normalOptions);
    sortSearchOptions(instanceOptions);

    if (isOpen()) {
      close();
    }

    m_scale = std::max(0.1f, scale);
    m_config = &config;
    m_normalOptions = std::move(normalOptions);
    m_instanceOptions = std::move(instanceOptions);
    m_lanePath = lanePath;
    m_root = nullptr;
    m_headerRow = nullptr;
    m_createActions = nullptr;
    m_searchPicker = nullptr;
    m_createTitle = nullptr;
    m_instanceInput = nullptr;
    m_instanceModeEnabled = false;
    m_createFormVisible = false;
    m_createType.clear();
    m_createLabel.clear();

    m_parentXdgSurface = parentXdgSurface;
    m_parentWlSurface = parentWlSurface;
    m_output = output;
    m_serial = serial;
    m_parentWidth = parentWidth;
    m_parentHeight = parentHeight;

    reopenForCurrentMode();
  }

  void WidgetAddPopup::close() { destroyPopup(); }

  bool WidgetAddPopup::isOpen() const noexcept { return DialogPopupHost::isOpen(); }

  bool WidgetAddPopup::onPointerEvent(const PointerEvent& event) { return DialogPopupHost::onPointerEvent(event); }

  void WidgetAddPopup::onKeyboardEvent(const KeyboardEvent& event) { DialogPopupHost::onKeyboardEvent(event); }

  wl_surface* WidgetAddPopup::wlSurface() const noexcept { return DialogPopupHost::wlSurface(); }

  void WidgetAddPopup::requestLayout() { DialogPopupHost::requestLayout(); }

  void WidgetAddPopup::requestRedraw() { DialogPopupHost::requestRedraw(); }

  void WidgetAddPopup::refreshPickerOptions() {
    if (m_searchPicker == nullptr) {
      return;
    }
    m_searchPicker->setOptions(m_instanceModeEnabled ? m_instanceOptions : m_normalOptions);
  }

  void WidgetAddPopup::refreshBodyState() {
    if (m_searchPicker != nullptr) {
      m_searchPicker->setVisible(!m_createFormVisible);
      m_searchPicker->setParticipatesInLayout(!m_createFormVisible);
      if (!m_createFormVisible) {
        refreshPickerOptions();
      }
    }
    if (m_createTitle != nullptr) {
      m_createTitle->setVisible(m_createFormVisible);
      m_createTitle->setParticipatesInLayout(m_createFormVisible);
    }
    if (m_instanceInput != nullptr) {
      m_instanceInput->setVisible(m_createFormVisible);
      m_instanceInput->setParticipatesInLayout(m_createFormVisible);
    }
    if (m_createActions != nullptr) {
      m_createActions->setVisible(m_createFormVisible);
      m_createActions->setParticipatesInLayout(m_createFormVisible);
    }

    if (!m_createFormVisible && m_searchPicker != nullptr) {
      if (auto* filter = m_searchPicker->filterInputArea(); filter != nullptr) {
        inputDispatcher().setFocus(filter);
      }
    }
    if (m_createFormVisible && m_instanceInput != nullptr && m_instanceInput->inputArea() != nullptr) {
      inputDispatcher().setFocus(m_instanceInput->inputArea());
    }
  }

  std::string WidgetAddPopup::suggestedInstanceId(std::string_view type) const {
    if (m_config == nullptr) {
      return std::string(type);
    }
    return nextWidgetInstanceId(*m_config, type);
  }

  bool WidgetAddPopup::canCreateInstanceId(std::string_view id) const {
    if (m_config == nullptr) {
      return false;
    }
    return isValidWidgetInstanceId(id) && !widgetReferenceNameExists(*m_config, id);
  }

  void WidgetAddPopup::beginCreateFlow(const SearchPickerOption& option) {
    m_createType = option.value;
    m_createLabel = option.label;
    m_createFormVisible = true;
    if (m_createTitle != nullptr) {
      m_createTitle->setText(i18n::tr("settings.entities.widget.instance.create-title", "type", m_createType));
    }
    if (m_instanceInput != nullptr) {
      m_instanceInput->setValue(suggestedInstanceId(m_createType));
      m_instanceInput->setInvalid(false);
    }
    reopenForCurrentMode();
  }

  void WidgetAddPopup::finishCreateFlow() {
    if (m_instanceInput == nullptr) {
      return;
    }
    const std::string id = trimmedText(m_instanceInput->value());
    if (!canCreateInstanceId(id)) {
      m_instanceInput->setInvalid(true);
      return;
    }
    m_instanceInput->setInvalid(false);
    if (m_onSelect) {
      m_onSelect(m_lanePath, id, m_createType, id);
    }
    DeferredCall::callLater([this]() { close(); });
  }

  void WidgetAddPopup::populateContent(Node* contentParent, std::uint32_t /*width*/, std::uint32_t /*height*/) {
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
    m_headerRow = header.get();

    const std::string lane = laneLabel(m_lanePath.empty() ? "" : m_lanePath.back());
    const std::string title =
        m_createFormVisible
            ? i18n::tr("settings.entities.widget.inspector.add-instance-title", "widget", m_createLabel, "lane", lane)
            : i18n::tr("settings.entities.widget.inspector.add-title", "lane", lane);
    header->addChild(makeLabel(title, Style::fontSizeBody * m_scale, colorSpecFromRole(ColorRole::OnSurface), true));

    auto spacer = std::make_unique<Flex>();
    spacer->setFlexGrow(1.0f);
    header->addChild(std::move(spacer));

    if (!m_createFormVisible) {
      header->addChild(makeLabel(i18n::tr("settings.entities.widget.picker.instance-toggle"),
                                 Style::fontSizeCaption * m_scale, colorSpecFromRole(ColorRole::OnSurfaceVariant),
                                 false));

      auto instanceToggle = std::make_unique<Toggle>();
      instanceToggle->setScale(m_scale);
      instanceToggle->setChecked(m_instanceModeEnabled);
      instanceToggle->setOnChange([this](bool value) {
        m_instanceModeEnabled = value;
        m_createFormVisible = false;
        m_createType.clear();
        m_createLabel.clear();
        if (m_instanceInput != nullptr) {
          m_instanceInput->setInvalid(false);
        }
        refreshBodyState();
        requestLayout();
      });
      header->addChild(std::move(instanceToggle));
    }

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
    picker->setPlaceholder(i18n::tr("settings.entities.widget.picker.placeholder"));
    picker->setEmptyText(i18n::tr("settings.entities.widget.picker.empty"));
    picker->clearFill();
    picker->clearBorder();
    picker->setRadius(0.0f);
    picker->setPadding(0.0f);
    picker->setFlexGrow(1.0f);
    picker->setOptions(m_normalOptions);
    picker->setOnActivated([this](const SearchPickerOption& option) {
      if (option.value.empty()) {
        return;
      }
      if (m_instanceModeEnabled) {
        beginCreateFlow(option);
        return;
      }
      if (m_onSelect) {
        m_onSelect(m_lanePath, option.value, {}, {});
      }
      DeferredCall::callLater([this]() { close(); });
    });
    picker->setOnCancel([this]() { DeferredCall::callLater([this]() { close(); }); });
    m_searchPicker = picker.get();
    root->addChild(std::move(picker));

    auto createTitle = makeLabel("", Style::fontSizeCaption * m_scale, colorSpecFromRole(ColorRole::OnSurfaceVariant));
    createTitle->setVisible(false);
    createTitle->setParticipatesInLayout(false);
    m_createTitle = createTitle.get();
    root->addChild(std::move(createTitle));

    auto instanceInput = std::make_unique<Input>();
    instanceInput->setPlaceholder(i18n::tr("settings.entities.widget.instance.id-placeholder"));
    instanceInput->setFontSize(Style::fontSizeBody * m_scale);
    instanceInput->setControlHeight(Style::controlHeight * m_scale);
    instanceInput->setHorizontalPadding(Style::spaceSm * m_scale);
    instanceInput->setSize(260.0f * m_scale, Style::controlHeight * m_scale);
    instanceInput->setVisible(false);
    instanceInput->setParticipatesInLayout(false);
    instanceInput->setOnChange([this](const std::string& /*value*/) {
      if (m_instanceInput != nullptr) {
        m_instanceInput->setInvalid(false);
      }
    });
    instanceInput->setOnSubmit([this](const std::string& /*value*/) { finishCreateFlow(); });
    m_instanceInput = instanceInput.get();
    root->addChild(std::move(instanceInput));

    auto actionRow = std::make_unique<Flex>();
    actionRow->setDirection(FlexDirection::Horizontal);
    actionRow->setAlign(FlexAlign::Center);
    actionRow->setGap(Style::spaceSm * m_scale);
    actionRow->setVisible(false);
    actionRow->setParticipatesInLayout(false);
    m_createActions = actionRow.get();

    auto backBtn = std::make_unique<Button>();
    backBtn->setText(i18n::tr("common.actions.cancel"));
    backBtn->setVariant(ButtonVariant::Ghost);
    backBtn->setFontSize(Style::fontSizeCaption * m_scale);
    backBtn->setMinHeight(Style::controlHeightSm * m_scale);
    backBtn->setPadding(Style::spaceXs * m_scale, Style::spaceSm * m_scale);
    backBtn->setRadius(Style::scaledRadiusSm(m_scale));
    backBtn->setOnClick([this]() {
      m_createFormVisible = false;
      m_createType.clear();
      m_createLabel.clear();
      if (m_instanceInput != nullptr) {
        m_instanceInput->setInvalid(false);
      }
      reopenForCurrentMode();
    });
    actionRow->addChild(std::move(backBtn));

    auto createBtn = std::make_unique<Button>();
    createBtn->setText(i18n::tr("settings.entities.widget.instance.create-save"));
    createBtn->setVariant(ButtonVariant::Default);
    createBtn->setFontSize(Style::fontSizeCaption * m_scale);
    createBtn->setMinHeight(Style::controlHeightSm * m_scale);
    createBtn->setPadding(Style::spaceXs * m_scale, Style::spaceSm * m_scale);
    createBtn->setRadius(Style::scaledRadiusSm(m_scale));
    createBtn->setOnClick([this]() { finishCreateFlow(); });
    actionRow->addChild(std::move(createBtn));
    root->addChild(std::move(actionRow));

    contentParent->addChild(std::move(root));

    refreshBodyState();
  }

  void WidgetAddPopup::layoutSheet(float contentWidth, float contentHeight) {
    if (m_root == nullptr || renderContext() == nullptr) {
      return;
    }

    m_root->setSize(contentWidth, contentHeight);
    m_root->layout(*renderContext());
  }

  std::pair<float, float> WidgetAddPopup::popupSize() const {
    if (m_createFormVisible) {
      return {360.0f * m_scale, 165.0f * m_scale};
    }
    return {520.0f * m_scale, 420.0f * m_scale};
  }

  void WidgetAddPopup::reopenForCurrentMode() {
    if (m_parentXdgSurface == nullptr || m_parentWlSurface == nullptr) {
      return;
    }

    const auto [panelWidth, panelHeight] = popupSize();
    const auto cfg =
        centeredPopupConfig(m_parentWidth, m_parentHeight, static_cast<std::uint32_t>(std::max(1.0f, panelWidth)),
                            static_cast<std::uint32_t>(std::max(1.0f, panelHeight)), m_serial);

    m_internalReopen = true;
    const bool opened = openPopupAsChild(cfg, m_parentXdgSurface, m_parentWlSurface, m_output);
    m_internalReopen = false;
    if (!opened) {
      close();
    }
  }

  void WidgetAddPopup::cancelToFacade() {}

  InputArea* WidgetAddPopup::initialFocusArea() {
    if (m_createFormVisible && m_instanceInput != nullptr) {
      return m_instanceInput->inputArea();
    }
    return m_searchPicker != nullptr ? m_searchPicker->filterInputArea() : nullptr;
  }

  void WidgetAddPopup::onSheetClose() {
    if (m_internalReopen) {
      return;
    }
    m_normalOptions.clear();
    m_instanceOptions.clear();
    m_config = nullptr;
    m_parentXdgSurface = nullptr;
    m_parentWlSurface = nullptr;
    m_output = nullptr;
    m_serial = 0;
    m_parentWidth = 0;
    m_parentHeight = 0;
    m_lanePath.clear();
    m_root = nullptr;
    m_headerRow = nullptr;
    m_createActions = nullptr;
    m_searchPicker = nullptr;
    m_createTitle = nullptr;
    m_instanceInput = nullptr;
    m_instanceModeEnabled = false;
    m_createFormVisible = false;
    m_createType.clear();
    m_createLabel.clear();
    if (m_onDismissed) {
      m_onDismissed();
    }
  }

} // namespace settings
