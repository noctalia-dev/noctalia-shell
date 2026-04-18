#include "shell/widgets/scripted_widget.h"

#include "core/log.h"
#include "render/scene/node.h"
#include "scripting/luau_host.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cstdlib>
#include <fstream>
#include <sstream>

namespace {
  constexpr Logger kLog("scripted-widget");

  std::string expandPath(const std::string& path) {
    if (path.empty() || path[0] != '~')
      return path;
    const char* home = std::getenv("HOME");
    if (!home)
      return path;
    return std::string(home) + path.substr(1);
  }

  std::string readFile(const std::string& path) {
    std::ifstream f(expandPath(path));
    if (!f)
      return {};
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
  }
} // namespace

ScriptedWidget::ScriptedWidget(std::string scriptPath) : m_scriptPath(std::move(scriptPath)) {}
ScriptedWidget::~ScriptedWidget() = default;

void ScriptedWidget::create() {
  m_host = std::make_unique<LuauHost>();

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setStableBaseline(true);
  m_label = label.get();
  setRoot(std::move(label));

  if (m_scriptPath.empty()) {
    kLog.warn("scripted widget: no script path");
    return;
  }
  std::string source = readFile(m_scriptPath);
  if (source.empty()) {
    kLog.warn("scripted widget: failed to read '{}'", m_scriptPath);
    return;
  }
  m_host->exec(m_scriptPath, source);
}

void ScriptedWidget::onFrameTick(float deltaMs) {
  m_accumMs += deltaMs;
  if (m_accumMs >= 250.0f) {
    m_accumMs = 0.0f;
    requestRedraw();
  }
}

void ScriptedWidget::doLayout(Renderer& renderer, float, float) {
  auto* rootNode = root();
  if (m_label == nullptr || rootNode == nullptr)
    return;
  doUpdate(renderer);
  m_label->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_label->measure(renderer);
  m_label->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_label->width(), m_label->height());
}

void ScriptedWidget::doUpdate(Renderer& renderer) {
  if (!m_host || !m_label)
    return;
  auto text = m_host->callGlobalReturningString("update");
  if (!text)
    return;
  if (*text != m_lastText) {
    m_lastText = std::move(*text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
  }
}
