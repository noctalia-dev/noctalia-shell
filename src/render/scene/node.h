#pragma once

#include <cstdint>
#include <memory>
#include <vector>

struct Mat3;

class AnimationManager;
class Renderer;

enum class NodeType : std::uint8_t {
  Base,
  Rect,
  Text,
  Image,
  Glyph,
  Spinner,
  Effect,
};

class Node {
public:
  explicit Node(NodeType type = NodeType::Base);
  virtual ~Node();

  Node(const Node&) = delete;
  Node& operator=(const Node&) = delete;

  [[nodiscard]] NodeType type() const noexcept { return m_type; }

  [[nodiscard]] float x() const noexcept { return m_x; }
  [[nodiscard]] float y() const noexcept { return m_y; }
  [[nodiscard]] float width() const noexcept { return m_width; }
  [[nodiscard]] float height() const noexcept { return m_height; }
  [[nodiscard]] float rotation() const noexcept { return m_rotation; }
  [[nodiscard]] float scale() const noexcept { return m_scale; }
  [[nodiscard]] float opacity() const noexcept { return m_opacity; }
  [[nodiscard]] float flexGrow() const noexcept { return m_flexGrow; }
  [[nodiscard]] bool visible() const noexcept { return m_visible; }
  [[nodiscard]] bool participatesInLayout() const noexcept { return m_participatesInLayout; }
  [[nodiscard]] bool paintDirty() const noexcept { return m_paintDirty; }
  [[nodiscard]] bool layoutDirty() const noexcept { return m_layoutDirty; }
  [[nodiscard]] bool clipChildren() const noexcept { return m_clipChildren; }
  [[nodiscard]] std::int32_t zIndex() const noexcept { return m_zIndex; }
  [[nodiscard]] Node* parent() const noexcept { return m_parent; }
  [[nodiscard]] const std::vector<std::unique_ptr<Node>>& children() const noexcept { return m_children; }

  void setPosition(float x, float y);
  virtual void setSize(float width, float height);
  void setFrameSize(float width, float height);
  void setRotation(float radians);
  void setScale(float scale);
  void setOpacity(float opacity);
  void setFlexGrow(float grow);
  void setVisible(bool visible);
  void setParticipatesInLayout(bool participatesInLayout);
  void setClipChildren(bool clipChildren);
  void setZIndex(std::int32_t zIndex);

  Node* addChild(std::unique_ptr<Node> child);
  // Insert at a specific vector position to control Flex layout order (not rendering order — use zIndex for that).
  Node* insertChildAt(std::size_t index, std::unique_ptr<Node> child);
  std::unique_ptr<Node> removeChild(Node* child);

  void setAnimationManager(AnimationManager* mgr);
  [[nodiscard]] AnimationManager* animationManager() const noexcept { return m_animationManager; }
  void layout(Renderer& renderer);

  void setUserData(void* data) noexcept { m_userData = data; }
  [[nodiscard]] void* userData() const noexcept { return m_userData; }

  static Node* hitTest(Node* root, float x, float y);
  static void absolutePosition(const Node* node, float& outX, float& outY);
  static bool mapFromScene(const Node* node, float sceneX, float sceneY, float& outLocalX, float& outLocalY);
  static void transformedBounds(const Node* node, float& outLeft, float& outTop, float& outRight, float& outBottom);
  static void transformedBounds(const Node* node, const Mat3& world, float& outLeft, float& outTop, float& outRight,
                                float& outBottom);

  void markPaintDirty();
  void markLayoutDirty();
  void clearDirty();

protected:
  virtual void doLayout(Renderer& renderer);

private:
  static Node* hitTestImpl(Node* node, float px, float py);
  NodeType m_type;
  float m_x = 0.0f;
  float m_y = 0.0f;
  float m_width = 0.0f;
  float m_height = 0.0f;
  float m_rotation = 0.0f;
  float m_scale = 1.0f;
  float m_opacity = 1.0f;
  float m_flexGrow = 0.0f;
  bool m_visible = true;
  bool m_participatesInLayout = true;
  bool m_paintDirty = true;
  bool m_layoutDirty = true;
  bool m_clipChildren = false;
  std::int32_t m_zIndex = 0;
  void* m_userData = nullptr;
  AnimationManager* m_animationManager = nullptr;
  Node* m_parent = nullptr;
  std::vector<std::unique_ptr<Node>> m_children;

  void propagatePaintDirty();
  void propagateLayoutDirty();
};
