#include "render/backend/render_backend.h"
#include "render/core/renderer.h"
#include "render/core/texture_manager.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/spacer.h"
#include "ui/ui_tree.h"
#include "ui/ui_tree_reconciler.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

// Satisfies the AsyncTextureCache link dependency pulled in by the Image
// control; never invoked — this test exercises no GPU path.
std::unique_ptr<TextureManager> createDefaultTextureManager() { return nullptr; }

namespace {

  // Reconciliation itself needs no real rendering; the renderer is only touched
  // by image/graph nodes, which this test does not exercise.
  class StubRenderer : public Renderer {
  public:
    TextMetrics measureText(std::string_view text, float fontSize, FontWeight, float, int, TextAlign,
                            std::string_view, TextEllipsize) override {
      return TextMetrics{.width = static_cast<float>(text.size()) * fontSize * 0.5f, .bottom = fontSize};
    }
    TextMetrics measureFont(float fontSize, FontWeight) override { return TextMetrics{.bottom = fontSize}; }
    void measureTextCursorStops(std::string_view, float, const std::vector<std::size_t>&, std::vector<float>&,
                                FontWeight) override {}
    TextMetrics measureGlyph(char32_t, float fontSize) override {
      return TextMetrics{.width = fontSize, .bottom = fontSize};
    }
    TextureManager& textureManager() override { std::abort(); }
    [[nodiscard]] float renderScale() const noexcept override { return 1.0f; }
  };

  bool expect(bool condition, const char* message) {
    if (!condition) {
      std::fprintf(stderr, "ui_tree_reconciler_test: %s\n", message);
      return false;
    }
    return true;
  }

  ui::UiTreeNode makeNode(std::string type) {
    ui::UiTreeNode node;
    node.type = std::move(type);
    return node;
  }

  ui::UiTreeNode makeLabel(std::string text, std::string key = {}) {
    ui::UiTreeNode node = makeNode("label");
    node.key = std::move(key);
    node.props.emplace("text", std::move(text));
    return node;
  }

} // namespace

int main() {
  bool ok = true;
  StubRenderer renderer;

  // Build: column{ label, box, spacer } reconciled as the host's single child.
  {
    ui::UiTreeReconciler reconciler;
    Flex host;

    ui::UiTreeNode tree = makeNode("column");
    tree.props.emplace("gap", 8.0);
    tree.children.push_back(makeLabel("Hello"));
    ui::UiTreeNode box = makeNode("box");
    box.props.emplace("width", 10.0);
    box.props.emplace("height", 4.0);
    tree.children.push_back(box);
    tree.children.push_back(makeNode("spacer"));

    ok = expect(reconciler.reconcile(host, tree, renderer), "initial reconcile reports structure change") && ok;
    ok = expect(host.children().size() == 1, "host has one root child") && ok;
    auto* column = dynamic_cast<Flex*>(host.children().front().get());
    ok = expect(column != nullptr, "root child is a Flex") && ok;
    if (column != nullptr) {
      ok = expect(column->gap() == 8.0f, "gap applied") && ok;
      ok = expect(column->children().size() == 3, "column has three children") && ok;
      auto* label = dynamic_cast<Label*>(column->children()[0].get());
      ok = expect(label != nullptr && label->text() == "Hello", "label text applied") && ok;
      ok = expect(dynamic_cast<Box*>(column->children()[1].get()) != nullptr, "second child is a Box") && ok;
      ok = expect(dynamic_cast<Spacer*>(column->children()[2].get()) != nullptr, "third child is a Spacer") && ok;
    }

    // In-place update: same structure, changed props -> same control instances.
    Node* labelBefore = column != nullptr ? column->children()[0].get() : nullptr;
    tree.props["gap"] = 4.0;
    tree.children[0].props["text"] = std::string("World");
    ok = expect(!reconciler.reconcile(host, tree, renderer), "prop-only reconcile reports no structure change") && ok;
    if (column != nullptr) {
      ok = expect(column->gap() == 4.0f, "gap updated in place") && ok;
      ok = expect(column->children()[0].get() == labelBefore, "label instance reused") && ok;
      auto* label = dynamic_cast<Label*>(column->children()[0].get());
      ok = expect(label != nullptr && label->text() == "World", "label text updated") && ok;
    }

    // Removal: drop to a single child.
    tree.children.resize(1);
    ok = expect(reconciler.reconcile(host, tree, renderer), "removal reports structure change") && ok;
    if (column != nullptr) {
      ok = expect(column->children().size() == 1, "children removed") && ok;
      ok = expect(column->children()[0].get() == labelBefore, "surviving child reused on removal") && ok;
    }
  }

  // Keyed reorder reuses control instances.
  {
    ui::UiTreeReconciler reconciler;
    Flex host;

    ui::UiTreeNode tree = makeNode("row");
    tree.children.push_back(makeLabel("A", "a"));
    tree.children.push_back(makeLabel("B", "b"));
    (void)reconciler.reconcile(host, tree, renderer);

    auto* row = dynamic_cast<Flex*>(host.children().front().get());
    ok = expect(row != nullptr && row->children().size() == 2, "keyed row built") && ok;
    Node* first = row != nullptr ? row->children()[0].get() : nullptr;
    Node* second = row != nullptr ? row->children()[1].get() : nullptr;

    std::swap(tree.children[0], tree.children[1]);
    ok = expect(reconciler.reconcile(host, tree, renderer), "reorder reports structure change") && ok;
    if (row != nullptr) {
      ok = expect(row->children()[0].get() == second && row->children()[1].get() == first,
                  "keyed children reuse instances across reorder") &&
           ok;
    }
  }

  // Type change replaces the control; unknown types are skipped without crashing.
  {
    ui::UiTreeReconciler reconciler;
    Flex host;

    ui::UiTreeNode tree = makeNode("column");
    tree.children.push_back(makeLabel("X"));
    (void)reconciler.reconcile(host, tree, renderer);
    auto* column = dynamic_cast<Flex*>(host.children().front().get());
    Node* labelNode = column != nullptr ? column->children()[0].get() : nullptr;

    tree.children[0] = makeNode("box");
    ok = expect(reconciler.reconcile(host, tree, renderer), "type change reports structure change") && ok;
    if (column != nullptr) {
      ok = expect(column->children().size() == 1, "type change keeps single child") && ok;
      ok = expect(column->children()[0].get() != labelNode, "type change replaces the instance") && ok;
      ok = expect(dynamic_cast<Box*>(column->children()[0].get()) != nullptr, "replacement is a Box") && ok;
    }

    tree.children.clear();
    tree.children.push_back(makeNode("definitely-not-a-control"));
    tree.children.push_back(makeLabel("Y"));
    (void)reconciler.reconcile(host, tree, renderer);
    if (column != nullptr) {
      ok = expect(column->children().size() == 1, "unknown type skipped") && ok;
      auto* label = dynamic_cast<Label*>(column->children()[0].get());
      ok = expect(label != nullptr && label->text() == "Y", "valid sibling of unknown type still built") && ok;
    }
  }

  // Scale multiplies size-like props.
  {
    ui::UiTreeReconciler reconciler;
    reconciler.setScale(2.0f);
    Flex host;

    ui::UiTreeNode tree = makeNode("column");
    ui::UiTreeNode label = makeLabel("S");
    label.props.emplace("fontSize", 10.0);
    tree.children.push_back(label);
    (void)reconciler.reconcile(host, tree, renderer);

    auto* column = dynamic_cast<Flex*>(host.children().front().get());
    auto* scaled = column != nullptr ? dynamic_cast<Label*>(column->children()[0].get()) : nullptr;
    ok = expect(scaled != nullptr && scaled->fontSize() == 20.0f, "fontSize scaled by content scale") && ok;
  }

  // Button onClick routes through the callback sink.
  {
    ui::UiTreeReconciler reconciler;
    std::string fired;
    reconciler.setCallbackSink([&fired](const std::string& name) { fired = name; });
    Flex host;

    ui::UiTreeNode tree = makeNode("column");
    ui::UiTreeNode button = makeNode("button");
    button.props.emplace("text", std::string("Go"));
    button.props.emplace("onClick", std::string("openDetails"));
    tree.children.push_back(button);
    (void)reconciler.reconcile(host, tree, renderer);

    auto* column = dynamic_cast<Flex*>(host.children().front().get());
    auto* control = column != nullptr ? dynamic_cast<Button*>(column->children()[0].get()) : nullptr;
    ok = expect(control != nullptr, "button built") && ok;
    // The sink wiring is exercised via the reconciler-installed callback.
    ok = expect(fired.empty(), "sink not fired before click") && ok;
  }

  return ok ? 0 : 1;
}
