#include "render/scene/node.h"

#include <algorithm>
#include <vector>

Node::Node(NodeType type) : m_type(type) {}

Node::~Node() = default;

void Node::layout(Renderer& /*renderer*/) {}

void Node::setPosition(float x, float y) {
  if (m_x == x && m_y == y) {
    return;
  }
  m_x = x;
  m_y = y;
  markDirty();
}

void Node::setSize(float width, float height) {
  if (m_width == width && m_height == height) {
    return;
  }
  m_width = width;
  m_height = height;
  markDirty();
}

void Node::setRotation(float radians) {
  if (m_rotation == radians) {
    return;
  }
  m_rotation = radians;
  markDirty();
}

void Node::setScale(float scale) {
  if (m_scale == scale) {
    return;
  }
  m_scale = scale;
  markDirty();
}

void Node::setOpacity(float opacity) {
  if (m_opacity == opacity) {
    return;
  }
  m_opacity = opacity;
  markDirty();
}

void Node::setFlexGrow(float grow) {
  if (m_flexGrow == grow) {
    return;
  }
  m_flexGrow = grow;
  markDirty();
}

void Node::setVisible(bool visible) {
  if (m_visible == visible) {
    return;
  }
  m_visible = visible;
  markDirty();
}

void Node::setClipChildren(bool clipChildren) {
  if (m_clipChildren == clipChildren) {
    return;
  }
  m_clipChildren = clipChildren;
  markDirty();
}

void Node::setZIndex(std::int32_t zIndex) {
  if (m_zIndex == zIndex) {
    return;
  }
  m_zIndex = zIndex;
  markDirty();
}

void Node::setAnimationManager(AnimationManager* mgr) {
  m_animationManager = mgr;
  for (auto& child : m_children) {
    child->setAnimationManager(mgr);
  }
}

Node* Node::addChild(std::unique_ptr<Node> child) {
  child->m_parent = this;
  if (m_animationManager != nullptr && child->m_animationManager == nullptr) {
    child->setAnimationManager(m_animationManager);
  }
  auto* raw = child.get();
  m_children.push_back(std::move(child));
  markDirty();
  return raw;
}

Node* Node::insertChildAt(std::size_t index, std::unique_ptr<Node> child) {
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
  markDirty();
  return raw;
}

std::unique_ptr<Node> Node::removeChild(Node* child) {
  auto it = std::find_if(m_children.begin(), m_children.end(), [child](const auto& ptr) { return ptr.get() == child; });

  if (it == m_children.end()) {
    return nullptr;
  }

  auto removed = std::move(*it);
  m_children.erase(it);
  removed->m_parent = nullptr;
  markDirty();
  return removed;
}

void Node::markDirty() {
  m_dirty = true;
  if (m_parent != nullptr && !m_parent->m_dirty) {
    m_parent->markDirty();
  }
}

void Node::clearDirty() {
  m_dirty = false;
  for (auto& child : m_children) {
    if (child->m_dirty) {
      child->clearDirty();
    }
  }
}

Node* Node::hitTest(Node* root, float x, float y) { return hitTestImpl(root, x, y, 0.0f, 0.0f); }

Node* Node::hitTestImpl(Node* node, float px, float py, float offsetX, float offsetY) {
  if (node == nullptr || !node->m_visible) {
    return nullptr;
  }

  const float nodeX = offsetX + node->m_x;
  const float nodeY = offsetY + node->m_y;
  const bool inside = (px >= nodeX && px < nodeX + node->m_width && py >= nodeY && py < nodeY + node->m_height);

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
    auto* hit = hitTestImpl(*it, px, py, nodeX, nodeY);
    if (hit != nullptr) {
      return hit;
    }
  }

  return inside ? node : nullptr;
}

void Node::absolutePosition(const Node* node, float& outX, float& outY) {
  outX = 0.0f;
  outY = 0.0f;
  for (const Node* n = node; n != nullptr; n = n->m_parent) {
    outX += n->m_x;
    outY += n->m_y;
  }
}
