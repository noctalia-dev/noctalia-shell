#pragma once

#include "ui/ui_tree.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

class Flex;
class Node;
class Renderer;

namespace ui {

  // Maps a declarative UiTreeNode tree onto a retained tree of src/ui/controls/.
  // The single place plugin UI intent becomes controls: plugin code never sees a
  // Node. Diffs against the previous tree — children matched by `key` when set,
  // else by position+type; a matched control is updated in place, a mismatch
  // replaces the subtree. Mutates the scene graph, so callers must run it in the
  // Layout phase (e.g. from a doLayout hook).
  class UiTreeReconciler {
  public:
    // Invoked with the plugin-global function name from a control callback prop
    // (e.g. button onClick = "openDetails").
    using CallbackSink = std::function<void(const std::string& functionName)>;
    // Resolves a tree-supplied path (e.g. image source) to an absolute path.
    using PathResolver = std::function<std::string(const std::string& path)>;

    UiTreeReconciler();
    ~UiTreeReconciler();

    UiTreeReconciler(const UiTreeReconciler&) = delete;
    UiTreeReconciler& operator=(const UiTreeReconciler&) = delete;

    void setCallbackSink(CallbackSink sink) { m_sink = std::move(sink); }
    void setPathResolver(PathResolver resolver) { m_resolver = std::move(resolver); }
    // Content scale multiplied into size-like props (fonts, gaps, sizes, radii).
    void setScale(float scale) { m_scale = scale; }

    // Reconciles `tree` as the single child of `host`. Props are (re)applied on
    // every call — setters are change-checked, and the scale may differ between
    // passes. Returns true when the retained structure changed.
    bool reconcile(Flex& host, const UiTreeNode& tree, Renderer& renderer);

  private:
    struct Slot;

    bool
    syncChildren(Node& parent, std::vector<Slot>& slots, const std::vector<UiTreeNode>& desired, Renderer& renderer);
    void applyProps(Slot& slot, const UiTreeNode& desired, Renderer& renderer);
    [[nodiscard]] std::unique_ptr<Node> createControl(const UiTreeNode& desired);

    CallbackSink m_sink;
    PathResolver m_resolver;
    float m_scale = 1.0f;
    std::vector<Slot> m_rootSlots;
  };

} // namespace ui
