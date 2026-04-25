#include "shell/setup_wizard/setup_wizard_panel.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/resource_paths.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "theme/builtin_palettes.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/controls/separator.h"
#include "ui/controls/toggle.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/file_utils.h"
#include "wayland/wayland_connection.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

  constexpr Logger kLog("setup-wizard");

  std::string markerPath() {
    const std::string dir = FileUtils::stateDir();
    if (dir.empty()) {
      return {};
    }
    return dir + "/setup_done";
  }

  void writeMarker() {
    const std::string path = markerPath();
    if (path.empty()) {
      return;
    }
    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
    std::ofstream out(path);
    out << "1";
  }

  std::unique_ptr<Label> makeLabel(std::string_view text, float fontSize, const ThemeColor& color, bool bold = false) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setFontSize(fontSize);
    label->setColor(color);
    label->setBold(bold);
    return label;
  }

  std::unique_ptr<Flex> makeCard(float scale) {
    auto card = std::make_unique<Flex>();
    card->setDirection(FlexDirection::Vertical);
    card->setAlign(FlexAlign::Stretch);
    card->setGap(Style::spaceMd * scale);
    card->setPadding(Style::spaceMd * scale, Style::spaceLg * scale);
    card->setRadius(Style::radiusLg * scale);
    card->setBackground(roleColor(ColorRole::Surface, 0.82f));
    card->setBorderWidth(Style::borderWidth);
    card->setBorderColor(roleColor(ColorRole::Outline, 0.42f));
    return card;
  }

  std::unique_ptr<Flex> makeRow(float scale) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setJustify(FlexJustify::SpaceBetween);
    row->setGap(Style::spaceMd * scale);
    return row;
  }

  std::unique_ptr<Flex> makeTextColumn() {
    auto col = std::make_unique<Flex>();
    col->setDirection(FlexDirection::Vertical);
    col->setAlign(FlexAlign::Start);
    col->setGap(2.0f);
    col->setFlexGrow(1.0f);
    return col;
  }

} // namespace

bool SetupWizardPanel::isFirstRun() {
  const std::string path = markerPath();
  if (path.empty()) {
    return false;
  }
  return !std::filesystem::exists(path);
}

void SetupWizardPanel::create() {
  const float scale = contentScale();
  const auto& cfg = m_config->config();

  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Vertical);
  root->setAlign(FlexAlign::Stretch);
  root->setGap(Style::spaceLg * scale);
  root->setPadding(24.0f * scale, 28.0f * scale);
  m_root = root.get();

  // Header
  {
    auto header = std::make_unique<Flex>();
    header->setDirection(FlexDirection::Horizontal);
    header->setAlign(FlexAlign::Center);
    header->setGap(Style::spaceMd * scale);

    auto logo = std::make_unique<Image>();
    logo->setSize(44.0f * scale, 44.0f * scale);
    m_logo = logo.get();
    header->addChild(std::move(logo));

    auto copy = makeTextColumn();
    copy->setGap(Style::spaceXs * scale);
    copy->addChild(makeLabel("Welcome to Noctalia", 18.0f * scale, roleColor(ColorRole::OnSurface), true));
    copy->addChild(makeLabel("A few quick choices to get you started.", Style::fontSizeBody * scale,
                             roleColor(ColorRole::OnSurfaceVariant)));
    header->addChild(std::move(copy));
    root->addChild(std::move(header));
  }

  root->addChild(std::make_unique<Separator>());

  // Telemetry
  {
    auto card = makeCard(scale);

    auto row = makeRow(scale);
    {
      auto col = makeTextColumn();
      col->addChild(makeLabel("Usage Statistics", Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), true));
      auto description = makeLabel("Send an anonymous ping on startup to help improve Noctalia.",
                                   Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant));
      description->setMaxWidth(360.0f * scale);
      col->addChild(std::move(description));
      row->addChild(std::move(col));
    }
    {
      auto toggle = std::make_unique<Toggle>();
      toggle->setChecked(cfg.shell.telemetryEnabled);
      toggle->setScale(scale);
      m_telemetryToggle = toggle.get();
      row->addChild(std::move(toggle));
    }
    card->addChild(std::move(row));
    root->addChild(std::move(card));
  }

  // Theme
  {
    auto card = makeCard(scale);

    // Mode row
    {
      auto row = makeRow(scale);
      auto label = makeLabel("Mode", Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface));
      label->setFlexGrow(1.0f);
      row->addChild(std::move(label));

      auto select = std::make_unique<Select>();
      select->setOptions({"Dark", "Light", "Auto"});
      std::size_t modeIdx = 0;
      if (cfg.theme.mode == ThemeMode::Light) {
        modeIdx = 1;
      } else if (cfg.theme.mode == ThemeMode::Auto) {
        modeIdx = 2;
      }
      select->setSelectedIndex(modeIdx);
      select->setFontSize(Style::fontSizeBody * scale);
      select->setControlHeight(Style::controlHeight * scale);
      select->setHorizontalPadding(Style::spaceMd * scale);
      select->setMinWidth(220.0f * scale);
      select->setOnSelectionChanged([this](std::size_t index, std::string_view /*label*/) {
        static constexpr const char* kModes[] = {"dark", "light", "auto"};
        if (index < 3) {
          m_config->setOverride({"theme", "mode"}, std::string(kModes[index]));
        }
      });
      m_modeSelect = select.get();
      row->addChild(std::move(select));
      card->addChild(std::move(row));
    }

    // Palette row
    {
      auto row = makeRow(scale);
      auto label = makeLabel("Palette", Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface));
      label->setFlexGrow(1.0f);
      row->addChild(std::move(label));

      auto select = std::make_unique<Select>();
      std::vector<std::string> paletteNames;
      std::size_t selectedIdx = 0;
      for (const auto& entry : noctalia::theme::builtinPalettes()) {
        if (entry.name == cfg.theme.builtinPalette) {
          selectedIdx = paletteNames.size();
        }
        paletteNames.emplace_back(entry.name);
      }
      select->setOptions(std::move(paletteNames));
      select->setSelectedIndex(selectedIdx);
      select->setFontSize(Style::fontSizeBody * scale);
      select->setControlHeight(Style::controlHeight * scale);
      select->setHorizontalPadding(Style::spaceMd * scale);
      select->setMinWidth(220.0f * scale);
      select->setOnSelectionChanged([this](std::size_t /*index*/, std::string_view name) {
        m_config->setOverride({"theme", "source"}, std::string("builtin"));
        m_config->setOverride({"theme", "builtin"}, std::string(name));
      });
      m_paletteSelect = select.get();
      row->addChild(std::move(select));
      card->addChild(std::move(row));
    }

    root->addChild(std::move(card));
  }

  // Wallpaper
  {
    auto card = makeCard(scale);

    auto row = makeRow(scale);
    {
      auto col = makeTextColumn();
      col->addChild(makeLabel("Wallpaper", Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface), true));
      const std::string currentPath = m_config->getDefaultWallpaperPath();
      auto pathLabel = makeLabel(currentPath.empty() ? "No wallpaper selected" : currentPath,
                                 Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant));
      pathLabel->setMaxWidth(330.0f * scale);
      pathLabel->setMaxLines(1);
      m_wallpaperLabel = pathLabel.get();
      col->addChild(std::move(pathLabel));
      row->addChild(std::move(col));
    }
    {
      auto button = std::make_unique<Button>();
      button->setText("Browse");
      button->setGlyph("image");
      button->setVariant(ButtonVariant::Outline);
      button->setFontSize(Style::fontSizeBody * scale);
      button->setGlyphSize(Style::fontSizeBody * scale);
      button->setMinHeight(Style::controlHeight * scale);
      button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      button->setRadius(Style::radiusMd * scale);
      button->setMinWidth(112.0f * scale);
      button->setOnClick([this]() {
        FileDialogOptions options;
        options.mode = FileDialogMode::Open;
        options.defaultViewMode = FileDialogViewMode::Grid;
        options.title = "Select Wallpaper";
        options.extensions = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"};
        std::filesystem::path startDir;
        if (!m_wallpaperDir.empty()) {
          startDir = m_wallpaperDir;
        } else if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
          startDir = std::filesystem::path(home) / "Pictures";
        }
        options.startDirectory = std::move(startDir);
        (void)FileDialog::open(std::move(options), [this](std::optional<std::filesystem::path> result) {
          if (!result.has_value()) {
            return;
          }
          const std::string fullPath = result->string();
          const std::string parentDir = result->parent_path().string();
          m_wallpaperDir = parentDir;
          if (m_wallpaperLabel != nullptr) {
            m_wallpaperLabel->setText(fullPath);
            m_wallpaperLabel->setColor(roleColor(ColorRole::Primary));
            m_wallpaperLabel->setMaxLines(1);
          }
          m_config->setOverride({"wallpaper", "directory"}, parentDir);
          m_config->setWallpaperPath(std::nullopt, fullPath);
        });
      });
      row->addChild(std::move(button));
    }
    card->addChild(std::move(row));
    root->addChild(std::move(card));
  }

  // Footer
  {
    auto spacer = std::make_unique<Flex>();
    spacer->setFlexGrow(1.0f);
    root->addChild(std::move(spacer));
  }
  {
    auto footer = std::make_unique<Flex>();
    footer->setDirection(FlexDirection::Horizontal);
    footer->setAlign(FlexAlign::Center);
    footer->setJustify(FlexJustify::SpaceBetween);

    footer->addChild(makeLabel("You can change these later in settings.", Style::fontSizeCaption * scale,
                               roleColor(ColorRole::OnSurfaceVariant)));

    auto button = std::make_unique<Button>();
    button->setText("Get Started");
    button->setGlyph("chevron-right");
    button->setVariant(ButtonVariant::Accent);
    button->setFontSize(Style::fontSizeBody * scale);
    button->setGlyphSize(Style::fontSizeBody * scale);
    button->setMinHeight(Style::controlHeight * scale);
    button->setPadding(Style::spaceSm * scale, Style::spaceLg * scale);
    button->setRadius(Style::radiusMd * scale);
    button->setMinWidth(132.0f * scale);
    button->setOnClick([this]() { commit(); });
    footer->addChild(std::move(button));
    root->addChild(std::move(footer));
  }

  setRoot(std::move(root));
}

void SetupWizardPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_logo != nullptr && !m_logo->hasImage()) {
    m_logo->setSourceFile(renderer, paths::assetPath("noctalia.svg").string(), 48 * static_cast<int>(contentScale()));
  }
  if (m_root != nullptr) {
    m_root->setPosition(0.0f, 0.0f);
    m_root->setSize(width, height);
    m_root->layout(renderer);
  }
}

void SetupWizardPanel::commit() {
  if (m_telemetryToggle != nullptr) {
    m_config->setOverride({"shell", "telemetry_enabled"}, m_telemetryToggle->checked());
  }
  writeMarker();
  kLog.info("setup complete");
  PanelManager::instance().close();
}

void SetupWizardPanel::onClose() { writeMarker(); }
