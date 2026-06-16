#include "ui/ui_tree_reconciler.h"

#include "core/log.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/graph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/progress_bar.h"
#include "ui/controls/separator.h"
#include "ui/controls/spacer.h"
#include "ui/palette.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <unordered_set>
#include <utility>

namespace ui {
  namespace {

    constexpr Logger kLog("ui-tree");

    const double* numProp(const UiTreeNode& node, const char* key) {
      const auto it = node.props.find(key);
      return it != node.props.end() ? std::get_if<double>(&it->second) : nullptr;
    }

    const std::string* strProp(const UiTreeNode& node, const char* key) {
      const auto it = node.props.find(key);
      return it != node.props.end() ? std::get_if<std::string>(&it->second) : nullptr;
    }

    const bool* boolProp(const UiTreeNode& node, const char* key) {
      const auto it = node.props.find(key);
      return it != node.props.end() ? std::get_if<bool>(&it->second) : nullptr;
    }

    const std::vector<double>* arrayProp(const UiTreeNode& node, const char* key) {
      const auto it = node.props.find(key);
      return it != node.props.end() ? std::get_if<std::vector<double>>(&it->second) : nullptr;
    }

    // Role token ("primary", "on_surface", …) or hex ("#rrggbb[aa]").
    std::optional<ColorSpec> parseColor(const UiTreeNode& node, const char* key) {
      const std::string* token = strProp(node, key);
      if (token == nullptr) {
        return std::nullopt;
      }
      if (auto role = colorRoleFromToken(*token); role.has_value()) {
        return colorSpecFromRole(*role);
      }
      Color fixed;
      if (tryParseHexColor(*token, fixed)) {
        return fixedColorSpec(fixed);
      }
      kLog.warn("ui node '{}': unknown color '{}' for prop '{}'", node.type, *token, key);
      return std::nullopt;
    }

    std::optional<FontWeight> parseFontWeight(const UiTreeNode& node) {
      const std::string* token = strProp(node, "fontWeight");
      if (token == nullptr) {
        return std::nullopt;
      }
      if (*token == "thin")
        return FontWeight::Thin;
      if (*token == "light")
        return FontWeight::Light;
      if (*token == "normal")
        return FontWeight::Normal;
      if (*token == "medium")
        return FontWeight::Medium;
      if (*token == "semibold")
        return FontWeight::SemiBold;
      if (*token == "bold")
        return FontWeight::Bold;
      if (*token == "heavy")
        return FontWeight::Heavy;
      kLog.warn("ui node '{}': unknown fontWeight '{}'", node.type, *token);
      return std::nullopt;
    }

    std::optional<FlexAlign> parseAlign(const UiTreeNode& node) {
      const std::string* token = strProp(node, "align");
      if (token == nullptr) {
        return std::nullopt;
      }
      if (*token == "start")
        return FlexAlign::Start;
      if (*token == "center")
        return FlexAlign::Center;
      if (*token == "end")
        return FlexAlign::End;
      if (*token == "stretch")
        return FlexAlign::Stretch;
      kLog.warn("ui node '{}': unknown align '{}'", node.type, *token);
      return std::nullopt;
    }

    std::optional<FlexJustify> parseJustify(const UiTreeNode& node) {
      const std::string* token = strProp(node, "justify");
      if (token == nullptr) {
        return std::nullopt;
      }
      if (*token == "start")
        return FlexJustify::Start;
      if (*token == "center")
        return FlexJustify::Center;
      if (*token == "end")
        return FlexJustify::End;
      if (*token == "space_between")
        return FlexJustify::SpaceBetween;
      kLog.warn("ui node '{}': unknown justify '{}'", node.type, *token);
      return std::nullopt;
    }

    std::optional<TextAlign> parseTextAlign(const UiTreeNode& node) {
      const std::string* token = strProp(node, "textAlign");
      if (token == nullptr) {
        return std::nullopt;
      }
      if (*token == "start")
        return TextAlign::Start;
      if (*token == "center")
        return TextAlign::Center;
      if (*token == "end")
        return TextAlign::End;
      kLog.warn("ui node '{}': unknown textAlign '{}'", node.type, *token);
      return std::nullopt;
    }

    std::optional<ButtonVariant> parseButtonVariant(const UiTreeNode& node) {
      const std::string* token = strProp(node, "variant");
      if (token == nullptr) {
        return std::nullopt;
      }
      if (*token == "default")
        return ButtonVariant::Default;
      if (*token == "primary")
        return ButtonVariant::Primary;
      if (*token == "secondary")
        return ButtonVariant::Secondary;
      if (*token == "destructive")
        return ButtonVariant::Destructive;
      if (*token == "outline")
        return ButtonVariant::Outline;
      if (*token == "ghost")
        return ButtonVariant::Ghost;
      kLog.warn("ui node '{}': unknown button variant '{}'", node.type, *token);
      return std::nullopt;
    }

    std::vector<float> toFloatSeries(const std::vector<double>& values) {
      std::vector<float> out;
      out.reserve(values.size());
      for (double v : values) {
        out.push_back(std::clamp(static_cast<float>(v), 0.0f, 1.0f));
      }
      return out;
    }

    // Known prop keys per control type — an unknown prop is a loud skip, not a
    // silent no-op, so typos in plugin code surface immediately.
    const std::unordered_set<std::string>& knownProps(const std::string& type) {
      static const std::unordered_set<std::string> kCommon = {"width", "height", "flexGrow", "opacity", "visible"};
      static const std::unordered_set<std::string> kFlex = {
          "width", "height",  "flexGrow", "opacity", "visible", "gap",         "padding",  "paddingH", "paddingV",
          "align", "justify", "fill",     "radius",  "border",  "borderWidth", "minWidth", "minHeight"
      };
      static const std::unordered_set<std::string> kBox = {"width", "height", "flexGrow", "opacity",     "visible",
                                                           "fill",  "radius", "border",   "borderWidth", "softness"};
      static const std::unordered_set<std::string> kLabel = {"width",      "height",   "flexGrow", "opacity",
                                                             "visible",    "text",     "fontSize", "color",
                                                             "fontWeight", "maxWidth", "maxLines", "textAlign"};
      static const std::unordered_set<std::string> kGlyph = {"width",   "height", "flexGrow", "opacity",
                                                             "visible", "name",   "size",     "color"};
      static const std::unordered_set<std::string> kImage = {"width",   "height", "flexGrow", "opacity",
                                                             "visible", "path",   "radius",   "fit"};
      static const std::unordered_set<std::string> kSeparator = {"width",   "height",  "flexGrow",
                                                                 "opacity", "visible", "thickness",
                                                                 "color",   "spacing", "orientation"};
      static const std::unordered_set<std::string> kProgress = {"width",    "height", "flexGrow", "opacity", "visible",
                                                                "progress", "fill",   "track",    "radius"};
      static const std::unordered_set<std::string> kButton = {"width",       "height",  "flexGrow", "opacity",
                                                              "visible",     "text",    "glyph",    "fontSize",
                                                              "glyphSize",   "variant", "enabled",  "onClick",
                                                              "onRightClick"};
      static const std::unordered_set<std::string> kGraph = {"width",   "height",    "flexGrow",   "opacity",
                                                             "visible", "values",    "values2",    "color",
                                                             "color2",  "lineWidth", "fillOpacity"};

      if (type == "column" || type == "row") {
        return kFlex;
      }
      if (type == "box") {
        return kBox;
      }
      if (type == "label") {
        return kLabel;
      }
      if (type == "glyph") {
        return kGlyph;
      }
      if (type == "image") {
        return kImage;
      }
      if (type == "separator") {
        return kSeparator;
      }
      if (type == "progress") {
        return kProgress;
      }
      if (type == "button") {
        return kButton;
      }
      if (type == "graph") {
        return kGraph;
      }
      return kCommon;
    }

  } // namespace

  struct UiTreeReconciler::Slot {
    std::string type;
    std::string key;
    Node* node = nullptr;
    std::string callbackName;      // last-wired button onClick target
    std::string rightCallbackName; // last-wired button onRightClick target
    std::string imagePath;         // last-applied resolved image source
    float imageTargetSize = 0.0f;
    std::vector<Slot> children;
  };

  UiTreeReconciler::UiTreeReconciler() = default;
  UiTreeReconciler::~UiTreeReconciler() = default;

  bool UiTreeReconciler::reconcile(Flex& host, const UiTreeNode& tree, Renderer& renderer) {
    std::vector<UiTreeNode> desired;
    desired.push_back(tree); // single root child of the host container
    return syncChildren(host, m_rootSlots, desired, renderer);
  }

  std::unique_ptr<Node> UiTreeReconciler::createControl(const UiTreeNode& desired) {
    if (desired.type == "column") {
      auto flex = std::make_unique<Flex>();
      flex->setDirection(FlexDirection::Vertical);
      return flex;
    }
    if (desired.type == "row") {
      auto flex = std::make_unique<Flex>();
      flex->setDirection(FlexDirection::Horizontal);
      return flex;
    }
    if (desired.type == "box") {
      return std::make_unique<Box>();
    }
    if (desired.type == "label") {
      return std::make_unique<Label>();
    }
    if (desired.type == "glyph") {
      return std::make_unique<Glyph>();
    }
    if (desired.type == "image") {
      return std::make_unique<Image>();
    }
    if (desired.type == "separator") {
      return std::make_unique<Separator>();
    }
    if (desired.type == "spacer") {
      return std::make_unique<Spacer>();
    }
    if (desired.type == "progress") {
      return std::make_unique<ProgressBar>();
    }
    if (desired.type == "button") {
      return std::make_unique<Button>();
    }
    if (desired.type == "graph") {
      return std::make_unique<Graph>();
    }
    kLog.warn("ui tree: unknown control type '{}', node skipped", desired.type);
    return nullptr;
  }

  bool UiTreeReconciler::syncChildren(
      Node& parent, std::vector<Slot>& slots, const std::vector<UiTreeNode>& desired, Renderer& renderer
  ) {
    // Fast path: the (type, key) sequence is unchanged — update props in place.
    bool sequenceMatches = slots.size() == desired.size();
    if (sequenceMatches) {
      for (std::size_t i = 0; i < slots.size(); ++i) {
        if (slots[i].type != desired[i].type || slots[i].key != desired[i].key) {
          sequenceMatches = false;
          break;
        }
      }
    }

    bool structureChanged = false;
    if (!sequenceMatches) {
      structureChanged = true;
      // Detach the current children, then re-add in desired order, reusing a
      // detached control whose (type, key) matches; everything else is created
      // fresh and unmatched leftovers are dropped.
      struct Detached {
        Slot slot;
        std::unique_ptr<Node> node;
        bool used = false;
      };
      std::vector<Detached> detached;
      detached.reserve(slots.size());
      for (auto& slot : slots) {
        if (slot.node != nullptr) {
          auto owned = parent.removeChild(slot.node);
          detached.push_back(Detached{.slot = std::move(slot), .node = std::move(owned)});
        }
      }
      slots.clear();
      slots.reserve(desired.size());

      for (const auto& want : desired) {
        Detached* match = nullptr;
        for (auto& candidate : detached) {
          if (candidate.used || candidate.slot.type != want.type || candidate.slot.key != want.key) {
            continue;
          }
          match = &candidate;
          break;
        }
        if (match != nullptr) {
          match->used = true;
          Slot slot = std::move(match->slot);
          slot.node = parent.addChild(std::move(match->node));
          slots.push_back(std::move(slot));
          continue;
        }

        auto control = createControl(want);
        if (control == nullptr) {
          continue;
        }
        Slot slot;
        slot.type = want.type;
        slot.key = want.key;
        slot.node = parent.addChild(std::move(control));
        slots.push_back(std::move(slot));
      }
    }

    // Apply props and recurse. With a sequence mismatch slots were rebuilt above
    // and may be shorter than `desired` (unknown types skipped).
    std::size_t slotIndex = 0;
    for (const auto& want : desired) {
      if (slotIndex >= slots.size()) {
        break;
      }
      Slot& slot = slots[slotIndex];
      if (slot.type != want.type || slot.key != want.key) {
        continue; // skipped unknown type
      }
      ++slotIndex;
      applyProps(slot, want, renderer);
      if (slot.node != nullptr && !want.children.empty()) {
        if (want.type != "column" && want.type != "row") {
          kLog.warn("ui tree: '{}' cannot have children, {} dropped", want.type, want.children.size());
        } else {
          structureChanged |= syncChildren(*slot.node, slot.children, want.children, renderer);
        }
      } else if (slot.node != nullptr && want.children.empty() && !slot.children.empty()) {
        structureChanged |= syncChildren(*slot.node, slot.children, {}, renderer);
      }
    }
    return structureChanged;
  }

  void UiTreeReconciler::applyProps(Slot& slot, const UiTreeNode& desired, Renderer& renderer) {
    Node* node = slot.node;
    if (node == nullptr) {
      return;
    }

    const auto& known = knownProps(desired.type);
    for (const auto& [key, value] : desired.props) {
      (void)value;
      if (!known.contains(key)) {
        kLog.warn("ui tree: '{}' has no prop '{}', ignored", desired.type, key);
      }
    }

    const auto scaled = [this](double v) { return static_cast<float>(v) * m_scale; };

    // Common node props.
    if (const bool* visible = boolProp(desired, "visible")) {
      node->setVisible(*visible);
    }
    if (const double* opacity = numProp(desired, "opacity")) {
      node->setOpacity(std::clamp(static_cast<float>(*opacity), 0.0f, 1.0f));
    }
    if (const double* grow = numProp(desired, "flexGrow")) {
      node->setFlexGrow(static_cast<float>(*grow));
    }

    const double* width = numProp(desired, "width");
    const double* height = numProp(desired, "height");

    if (desired.type == "column" || desired.type == "row") {
      auto* flex = static_cast<Flex*>(node);
      if (const double* gap = numProp(desired, "gap")) {
        flex->setGap(scaled(*gap));
      }
      const double* padding = numProp(desired, "padding");
      const double* paddingV = numProp(desired, "paddingV");
      const double* paddingH = numProp(desired, "paddingH");
      if (padding != nullptr || paddingV != nullptr || paddingH != nullptr) {
        const float fallback = padding != nullptr ? scaled(*padding) : 0.0f;
        flex->setPadding(
            paddingV != nullptr ? scaled(*paddingV) : fallback, paddingH != nullptr ? scaled(*paddingH) : fallback
        );
      }
      if (auto align = parseAlign(desired)) {
        flex->setAlign(*align);
      }
      if (auto justify = parseJustify(desired)) {
        flex->setJustify(*justify);
      }
      if (auto fill = parseColor(desired, "fill")) {
        flex->setFill(*fill);
      }
      if (const double* radius = numProp(desired, "radius")) {
        flex->setRadius(scaled(*radius));
      }
      if (auto border = parseColor(desired, "border")) {
        const double* borderWidth = numProp(desired, "borderWidth");
        flex->setBorder(*border, borderWidth != nullptr ? scaled(*borderWidth) : 1.0f);
      }
      if (const double* minWidth = numProp(desired, "minWidth")) {
        flex->setMinWidth(scaled(*minWidth));
      }
      if (const double* minHeight = numProp(desired, "minHeight")) {
        flex->setMinHeight(scaled(*minHeight));
      }
      if (width != nullptr) {
        flex->setMinWidth(scaled(*width));
        flex->setMaxWidth(scaled(*width));
      }
      if (height != nullptr) {
        flex->setMinHeight(scaled(*height));
        flex->setMaxHeight(scaled(*height));
      }
      return;
    }

    if (desired.type == "box") {
      auto* box = static_cast<Box*>(node);
      if (auto fill = parseColor(desired, "fill")) {
        box->setFill(*fill);
      }
      if (const double* radius = numProp(desired, "radius")) {
        box->setRadius(scaled(*radius));
      }
      if (auto border = parseColor(desired, "border")) {
        const double* borderWidth = numProp(desired, "borderWidth");
        box->setBorder(*border, borderWidth != nullptr ? scaled(*borderWidth) : 1.0f);
      }
      if (const double* softness = numProp(desired, "softness")) {
        box->setSoftness(static_cast<float>(*softness));
      }
      box->setSize(
          width != nullptr ? scaled(*width) : node->width(), height != nullptr ? scaled(*height) : node->height()
      );
      return;
    }

    if (desired.type == "label") {
      auto* label = static_cast<Label*>(node);
      if (const std::string* text = strProp(desired, "text")) {
        label->setText(*text);
      }
      if (const double* fontSize = numProp(desired, "fontSize")) {
        label->setFontSize(scaled(*fontSize));
      }
      if (auto color = parseColor(desired, "color")) {
        label->setColor(*color);
      }
      if (auto weight = parseFontWeight(desired)) {
        label->setFontWeight(*weight);
      }
      if (const double* maxWidth = numProp(desired, "maxWidth")) {
        label->setMaxWidth(scaled(*maxWidth));
      }
      if (const double* maxLines = numProp(desired, "maxLines")) {
        label->setMaxLines(static_cast<int>(*maxLines));
      }
      if (auto align = parseTextAlign(desired)) {
        label->setTextAlign(*align);
      }
      return;
    }

    if (desired.type == "glyph") {
      auto* glyph = static_cast<Glyph*>(node);
      if (const std::string* name = strProp(desired, "name")) {
        glyph->setGlyph(*name);
      }
      if (const double* size = numProp(desired, "size")) {
        glyph->setGlyphSize(scaled(*size));
      }
      if (auto color = parseColor(desired, "color")) {
        glyph->setColor(*color);
      }
      return;
    }

    if (desired.type == "image") {
      auto* image = static_cast<Image*>(node);
      if (const double* radius = numProp(desired, "radius")) {
        image->setRadius(scaled(*radius));
      }
      if (const std::string* fit = strProp(desired, "fit")) {
        if (*fit == "contain") {
          image->setFit(ImageFit::Contain);
        } else if (*fit == "cover") {
          image->setFit(ImageFit::Cover);
        } else if (*fit == "stretch") {
          image->setFit(ImageFit::Stretch);
        } else {
          kLog.warn("ui tree: image has unknown fit '{}'", *fit);
        }
      }
      const float imageWidth = width != nullptr ? scaled(*width) : node->width();
      const float imageHeight = height != nullptr ? scaled(*height) : imageWidth;
      image->setSize(imageWidth, imageHeight);
      if (const std::string* path = strProp(desired, "path")) {
        const std::string resolved = m_resolver ? m_resolver(*path) : *path;
        const float targetSize = std::max(1.0f, std::max(imageWidth, imageHeight) * 3.0f);
        if (resolved != slot.imagePath || targetSize > slot.imageTargetSize) {
          slot.imagePath = resolved;
          slot.imageTargetSize = targetSize;
          if (!image->setSourceFile(renderer, resolved, static_cast<int>(std::round(targetSize)), true)) {
            kLog.warn("ui tree: image failed to load '{}'", resolved);
          }
        }
      }
      return;
    }

    if (desired.type == "separator") {
      auto* separator = static_cast<Separator*>(node);
      if (const double* thickness = numProp(desired, "thickness")) {
        separator->setThickness(scaled(*thickness));
      }
      if (auto color = parseColor(desired, "color")) {
        separator->setColor(*color);
      }
      if (const double* spacing = numProp(desired, "spacing")) {
        separator->setSpacing(scaled(*spacing));
      }
      if (const std::string* orientation = strProp(desired, "orientation")) {
        if (*orientation == "horizontal") {
          separator->setOrientation(SeparatorOrientation::HorizontalRule);
        } else if (*orientation == "vertical") {
          separator->setOrientation(SeparatorOrientation::VerticalRule);
        } else if (*orientation == "auto") {
          separator->setOrientation(SeparatorOrientation::Auto);
        } else {
          kLog.warn("ui tree: separator has unknown orientation '{}'", *orientation);
        }
      }
      return;
    }

    if (desired.type == "progress") {
      auto* progress = static_cast<ProgressBar*>(node);
      if (const double* value = numProp(desired, "progress")) {
        progress->setProgress(std::clamp(static_cast<float>(*value), 0.0f, 1.0f));
      }
      if (auto fill = parseColor(desired, "fill")) {
        progress->setFill(*fill);
      }
      if (auto track = parseColor(desired, "track")) {
        progress->setTrack(*track);
      }
      if (const double* radius = numProp(desired, "radius")) {
        progress->setRadius(scaled(*radius));
      }
      progress->setSize(
          width != nullptr ? scaled(*width) : node->width(), height != nullptr ? scaled(*height) : node->height()
      );
      return;
    }

    if (desired.type == "button") {
      auto* button = static_cast<Button*>(node);
      if (const std::string* text = strProp(desired, "text")) {
        button->setText(*text);
      }
      if (const std::string* glyph = strProp(desired, "glyph")) {
        button->setGlyph(*glyph);
      }
      if (const double* fontSize = numProp(desired, "fontSize")) {
        button->setFontSize(scaled(*fontSize));
      }
      if (const double* glyphSize = numProp(desired, "glyphSize")) {
        button->setGlyphSize(scaled(*glyphSize));
      }
      if (auto variant = parseButtonVariant(desired)) {
        button->setVariant(*variant);
      }
      if (const bool* enabled = boolProp(desired, "enabled")) {
        button->setEnabled(*enabled);
      }
      if (const std::string* onClick = strProp(desired, "onClick");
          onClick != nullptr && *onClick != slot.callbackName) {
        slot.callbackName = *onClick;
        button->setOnClick([this, name = slot.callbackName]() {
          if (m_sink) {
            m_sink(name);
          }
        });
      }
      if (const std::string* onRightClick = strProp(desired, "onRightClick");
          onRightClick != nullptr && *onRightClick != slot.rightCallbackName) {
        slot.rightCallbackName = *onRightClick;
        button->setOnRightClick([this, name = slot.rightCallbackName]() {
          if (m_sink) {
            m_sink(name);
          }
        });
      }
      if (width != nullptr) {
        button->setMinWidth(scaled(*width));
        button->setMaxWidth(scaled(*width));
      }
      if (height != nullptr) {
        button->setMinHeight(scaled(*height));
        button->setMaxHeight(scaled(*height));
      }
      return;
    }

    if (desired.type == "graph") {
      auto* graph = static_cast<Graph*>(node);
      if (const std::vector<double>* values = arrayProp(desired, "values")) {
        graph->setValues(toFloatSeries(*values));
      }
      if (const std::vector<double>* values2 = arrayProp(desired, "values2")) {
        graph->setValues2(toFloatSeries(*values2));
      }
      if (auto color = parseColor(desired, "color")) {
        graph->setColor(*color);
      }
      if (auto color2 = parseColor(desired, "color2")) {
        graph->setColor2(*color2);
      }
      if (const double* lineWidth = numProp(desired, "lineWidth")) {
        graph->setLineWidth(scaled(*lineWidth));
      }
      if (const double* fillOpacity = numProp(desired, "fillOpacity")) {
        graph->setFillOpacity(std::clamp(static_cast<float>(*fillOpacity), 0.0f, 1.0f));
      }
      graph->setSize(
          width != nullptr ? scaled(*width) : node->width(), height != nullptr ? scaled(*height) : node->height()
      );
      return;
    }

    // spacer (and any future no-prop control): common props only.
    if (width != nullptr || height != nullptr) {
      node->setSize(
          width != nullptr ? scaled(*width) : node->width(), height != nullptr ? scaled(*height) : node->height()
      );
    }
  }

} // namespace ui
