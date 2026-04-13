#include "core/ui_phase.h"
#include "render/scene/node.h"

#include "render/animation/animation_manager.h"
#include "render/core/mat3.h"

#include <algorithm>
#include <cmath>

namespace {

Mat3 localTransform(const Node* node) {
  const float cx = node->width() * 0.5f;
  const float cy = node->height() * 0.5f;
  return Mat3::translation(node->x(), node->y()) * Mat3::translation(cx, cy) * Mat3::rotation(node->rotation()) *
         Mat3::scale(node->scale(), node->scale()) * Mat3::translation(-cx, -cy);
}

Mat3 computeWorldTransform(const Node* node) {
  Mat3 world = Mat3::identity();
  for (const Node* current = node; current != nullptr; current = current->parent()) {
    world = localTransform(current) * world;
  }
  return world;
}

bool pointInsideNode(const Node* node, float sceneX, float sceneY, float& localX, float& localY) {
  if (node == nullptr) {
    return false;
  }

  const Mat3 inverse = computeWorldTransform(node).inverse();
  const Vec2 local = inverse.transformPoint(sceneX, sceneY);
  localX = local.x;
  localY = local.y;
  return localX >= 0.0f && localX < node->width() && localY >= 0.0f && localY < node->height();
}

} // namespace

Node::Node(NodeType type) : m_type(type) {}

Node::~Node() {
  // Ensure any animation still targeting this node is cancelled before the node goes away.
  // Call sites that pass `this` as the animation owner get lifetime safety for free.
  if (m_animationManager != nullptr) {
    m_animationManager->cancelForOwner(this);
  }
}

void Node::layout(Renderer& renderer) {
  uiAssertNotRendering("Node::layout");
  doLayout(renderer);
}

void Node::doLayout(Renderer& /*renderer*/) {}

void Node::setPosition(float x, float y) {
  if (m_x == x && m_y == y) {
    return;
  }
  m_x = x;
  m_y = y;
  markPaintDirty();
}

void Node::setSize(float width, float height) {
  if (m_width == width && m_height == height) {
    return;
  }
  m_width = width;
  m_height = height;
  markLayoutDirty();
}

void Node::setFrameSize(float width, float height) {
  if (m_width == width && m_height == height) {
    return;
  }
  m_width = width;
  m_height = height;
  markPaintDirty();
}

void Node::setRotation(float radians) {
  if (m_rotation == radians) {
    return;
  }
  m_rotation = radians;
  markPaintDirty();
}

void Node::setScale(float scale) {
  if (m_scale == scale) {
    return;
  }
  m_scale = scale;
  markPaintDirty();
}

void Node::setOpacity(float opacity) {
  if (m_opacity == opacity) {
    return;
  }
  m_opacity = opacity;
  markPaintDirty();
}

void Node::setFlexGrow(float grow) {
  if (m_flexGrow == grow) {
    return;
  }
  m_flexGrow = grow;
  markLayoutDirty();
}

void Node::setVisible(bool visible) {
  if (m_visible == visible) {
    return;
  }
  m_visible = visible;
  markLayoutDirty();
}

void Node::setParticipatesInLayout(bool participatesInLayout) {
  if (m_participatesInLayout == participatesInLayout) {
    return;
  }
  uiAssertSceneMutationAllowed("Node::setParticipatesInLayout");
  m_participatesInLayout = participatesInLayout;
  markLayoutDirty();
}

void Node::setClipChildren(bool clipChildren) {
  if (m_clipChildren == clipChildren) {
    return;
  }
  m_clipChildren = clipChildren;
  markPaintDirty();
}

void Node::setZIndex(std::int32_t zIndex) {
  if (m_zIndex == zIndex) {
    return;
  }
  m_zIndex = zIndex;
  markPaintDirty();
}

void Node::setAnimationManager(AnimationManager* mgr) {
  m_animationManager = mgr;
  for (auto& child : m_children) {
    child->setAnimationManager(mgr);
  }
}

Node* Node::addChild(std::unique_ptr<Node> child) {
  uiAssertSceneMutationAllowed("Node::addChild");
  child->m_parent = this;
  if (m_animationManager != nullptr && child->m_animationManager == nullptr) {
    child->setAnimationManager(m_animationManager);
  }
  auto* raw = child.get();
  m_children.push_back(std::move(child));
  markLayoutDirty();
  return raw;
}

Node* Node::insertChildAt(std::size_t index, std::unique_ptr<Node> child) {
  uiAssertSceneMutationAllowed("Node::insertChildAt");
  child->m_parent = this;
  if (m_animationManager != nullptr && child->m_animationManager == nullptr) {
    child->setAnimationManager(m_animationManager);
  }
  auto* raw = child.get();
  if (index >= m_children.size()) {
    m_children.push_back(std::move(child));
  } else {
    m_children.insert(m_children.begin() + static_cast<std::ptrdiff_t>(index), std::move(child));
  }
  markLayoutDirty();
  return raw;
}

std::unique_ptr<Node> Node::removeChild(Node* child) {
  uiAssertSceneMutationAllowed("Node::removeChild");
  auto it = std::find_if(m_children.begin(), m_children.end(), [child](const auto& ptr) { return ptr.get() == child; });

  if (it == m_children.end()) {
    return nullptr;
  }

  auto removed = std::move(*it);
  m_children.erase(it);
  removed->m_parent = nullptr;
  markLayoutDirty();
  return removed;
}

void Node::markPaintDirty() { propagatePaintDirty(); }

void Node::markLayoutDirty() {
  propagateLayoutDirty();
  propagatePaintDirty();
}

void Node::propagatePaintDirty() {
  if (m_paintDirty) {
    return;
  }
  m_paintDirty = true;
  if (m_parent != nullptr) {
    m_parent->propagatePaintDirty();
  }
}

void Node::propagateLayoutDirty() {
  if (m_layoutDirty) {
    return;
  }
  m_layoutDirty = true;
  if (m_parent != nullptr) {
    m_parent->propagateLayoutDirty();
  }
}

void Node::clearDirty() {
  m_paintDirty = false;
  m_layoutDirty = false;
  for (auto& child : m_children) {
    if (child->paintDirty() || child->layoutDirty()) {
      child->clearDirty();
    }
  }
}

Node* Node::hitTest(Node* root, float x, float y) { return hitTestImpl(root, x, y); }

Node* Node::hitTestImpl(Node* node, float px, float py) {
  if (node == nullptr || !node->m_visible) {
    return nullptr;
  }

  float localX = 0.0f;
  float localY = 0.0f;
  const bool inside = pointInsideNode(node, px, py, localX, localY);

  if (node->m_clipChildren && !inside) {
    return nullptr;
  }

  std::vector<Node*> orderedChildren;
  orderedChildren.reserve(node->m_children.size());
  for (auto& child : node->m_children) {
    orderedChildren.push_back(child.get());
  }

  std::stable_sort(orderedChildren.begin(), orderedChildren.end(),
                   [](const Node* a, const Node* b) { return a->zIndex() < b->zIndex(); });

  // Traverse children in reverse (topmost first).
  // Children are allowed to overflow parent bounds (needed for menus/popovers).
  for (auto it = orderedChildren.rbegin(); it != orderedChildren.rend(); ++it) {
    auto* hit = hitTestImpl(*it, px, py);
    if (hit != nullptr) {
      return hit;
    }
  }

  return inside ? node : nullptr;
}

void Node::absolutePosition(const Node* node, float& outX, float& outY) {
  const Vec2 topLeft = computeWorldTransform(node).transformPoint(0.0f, 0.0f);
  outX = topLeft.x;
  outY = topLeft.y;
}

bool Node::mapFromScene(const Node* node, float sceneX, float sceneY, float& outLocalX, float& outLocalY) {
  if (node == nullptr) {
    outLocalX = 0.0f;
    outLocalY = 0.0f;
    return false;
  }

  return pointInsideNode(node, sceneX, sceneY, outLocalX, outLocalY);
}

void Node::transformedBounds(const Node* node, const Mat3& world, float& outLeft, float& outTop, float& outRight,
                              float& outBottom) {
  const Vec2 corners[] = {
      world.transformPoint(0.0f, 0.0f),
      world.transformPoint(node->width(), 0.0f),
      world.transformPoint(node->width(), node->height()),
      world.transformPoint(0.0f, node->height()),
  };

  outLeft = corners[0].x;
  outTop = corners[0].y;
  outRight = outLeft;
  outBottom = outTop;

  for (const Vec2 corner : corners) {
    outLeft = std::min(outLeft, corner.x);
    outTop = std::min(outTop, corner.y);
    outRight = std::max(outRight, corner.x);
    outBottom = std::max(outBottom, corner.y);
  }
}

void Node::transformedBounds(const Node* node, float& outLeft, float& outTop, float& outRight, float& outBottom) {
  transformedBounds(node, computeWorldTransform(node), outLeft, outTop, outRight, outBottom);
}
