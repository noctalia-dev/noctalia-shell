#include "shell/setup_wizard/setup_wizard_panel.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/resource_paths.h"
#include "i18n/i18n.h"
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
#include <iterator>
#include <memory>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace {

  constexpr Logger kLog("setup-wizard");

  struct SelectOption {
    std::string_view labelKey;
    std::string_view value;
  };

  constexpr SelectOption kSetupThemeSources[] = {
      {"settings.opt.builtin", "builtin"},
      {"settings.opt.wallpaper", "wallpaper"},
  };

  constexpr SelectOption kWallpaperSchemes[] = {
      {"theme.scheme.m3-content", "m3-content"},
      {"theme.scheme.m3-tonal-spot", "m3-tonal-spot"},
      {"theme.scheme.m3-fruit-salad", "m3-fruit-salad"},
      {"theme.scheme.m3-rainbow", "m3-rainbow"},
      {"theme.scheme.m3-monochrome", "m3-monochrome"},
      {"theme.scheme.vibrant", "vibrant"},
      {"theme.scheme.faithful", "faithful"},
      {"theme.scheme.dysfunctional", "dysfunctional"},
      {"theme.scheme.muted", "muted"},
  };

  constexpr std::string_view kDefaultThemeSource = "builtin";
  constexpr std::string_view kDefaultBuiltinPalette = "Noctalia";

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

  std::vector<std::string> labelsFromOptions(std::span<const SelectOption> options) {
    std::vector<std::string> labels;
    labels.reserve(options.size());
    for (const auto& option : options) {
      labels.emplace_back(i18n::tr(option.labelKey));
    }
    return labels;
  }

  std::size_t selectedOptionIndex(std::span<const SelectOption> options, std::string_view value) {
    for (std::size_t i = 0; i < options.size(); ++i) {
      if (options[i].value == value) {
        return i;
      }
    }
    return 0;
  }

  std::vector<std::string> builtinPaletteNames() {
    std::vector<std::string> paletteNames;
    paletteNames.reserve(noctalia::theme::builtinPalettes().size());
    for (const auto& entry : noctalia::theme::builtinPalettes()) {
      paletteNames.emplace_back(entry.name);
    }
    return paletteNames;
  }

  std::size_t selectedBuiltinPaletteIndex(std::string_view name) {
    std::size_t index = 0;
    for (const auto& entry : noctalia::theme::builtinPalettes()) {
      if (entry.name == name) {
        return index;
      }
      ++index;
    }
    return 0;
  }

  std::unique_ptr<Flex> makeCard(float scale) {
    auto card = std::make_unique<Flex>();
    card->setDirection(FlexDirection::Vertical);
    card->setAlign(FlexAlign::Stretch);
    card->setGap(Style::spaceMd * scale);
    card->setPadding(Style::spaceMd * scale, Style::spaceLg * scale);
    card->setCardStyle(scale);
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
    copy->addChild(makeLabel(i18n::tr("setup-wizard.title"), 18.0f * scale, roleColor(ColorRole::OnSurface), true));
    copy->addChild(makeLabel(i18n::tr("setup-wizard.subtitle"), Style::fontSizeBody * scale,
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
      col->addChild(makeLabel(i18n::tr("settings.telemetry"), Style::fontSizeBody * scale,
                              roleColor(ColorRole::OnSurface), true));
      auto description = makeLabel(i18n::tr("settings.telemetry-desc"), Style::fontSizeCaption * scale,
                                   roleColor(ColorRole::OnSurfaceVariant));
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

  // Wallpaper
  {
    auto card = makeCard(scale);

    auto row = makeRow(scale);
    {
      auto col = makeTextColumn();
      col->addChild(makeLabel(i18n::tr("setup-wizard.wallpaper"), Style::fontSizeBody * scale,
                              roleColor(ColorRole::OnSurface), true));
      const std::string currentPath = m_config->getDefaultWallpaperPath();
      auto pathLabel = makeLabel(currentPath.empty() ? i18n::tr("setup-wizard.no-wallpaper-selected") : currentPath,
                                 Style::fontSizeCaption * scale, roleColor(ColorRole::OnSurfaceVariant));
      pathLabel->setMaxWidth(330.0f * scale);
      pathLabel->setMaxLines(1);
      m_wallpaperLabel = pathLabel.get();
      col->addChild(std::move(pathLabel));
      row->addChild(std::move(col));
    }
    {
      auto button = std::make_unique<Button>();
      button->setText(i18n::tr("setup-wizard.browse"));
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
        options.title = i18n::tr("setup-wizard.select-wallpaper");
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

  // Theme
  {
    auto card = makeCard(scale);

    // Mode row
    {
      auto row = makeRow(scale);
      auto label =
          makeLabel(i18n::tr("setup-wizard.mode"), Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface));
      label->setFlexGrow(1.0f);
      row->addChild(std::move(label));

      auto select = std::make_unique<Select>();
      select->setOptions({i18n::tr("settings.opt.dark"), i18n::tr("settings.opt.light"), i18n::tr("common.auto")});
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

    // Theme source row
    {
      auto row = makeRow(scale);
      auto label =
          makeLabel(i18n::tr("settings.theme-source"), Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface));
      label->setFlexGrow(1.0f);
      row->addChild(std::move(label));

      auto select = std::make_unique<Select>();
      select->setOptions(labelsFromOptions(kSetupThemeSources));
      m_themeSource = ThemeSource::Builtin;
      m_builtinPalette = std::string(kDefaultBuiltinPalette);
      m_config->setOverride({"theme", "source"}, std::string(kDefaultThemeSource));
      m_config->setOverride({"theme", "builtin"}, m_builtinPalette);
      select->setSelectedIndex(selectedOptionIndex(kSetupThemeSources, kDefaultThemeSource));
      select->setFontSize(Style::fontSizeBody * scale);
      select->setControlHeight(Style::controlHeight * scale);
      select->setHorizontalPadding(Style::spaceMd * scale);
      select->setMinWidth(220.0f * scale);
      select->setOnSelectionChanged([this](std::size_t index, std::string_view /*label*/) {
        if (index >= std::size(kSetupThemeSources)) {
          return;
        }
        const std::string source(kSetupThemeSources[index].value);
        m_themeSource = source == "wallpaper" ? ThemeSource::Wallpaper : ThemeSource::Builtin;
        m_config->setOverride({"theme", "source"}, source);
        configureThemeOptionSelect();
      });
      m_themeSourceSelect = select.get();
      row->addChild(std::move(select));
      card->addChild(std::move(row));
    }

    // Theme option row
    {
      auto row = makeRow(scale);
      auto label = makeLabel("", Style::fontSizeBody * scale, roleColor(ColorRole::OnSurface));
      label->setFlexGrow(1.0f);
      m_themeOptionLabel = label.get();
      row->addChild(std::move(label));

      auto select = std::make_unique<Select>();
      select->setFontSize(Style::fontSizeBody * scale);
      select->setControlHeight(Style::controlHeight * scale);
      select->setHorizontalPadding(Style::spaceMd * scale);
      select->setMinWidth(220.0f * scale);
      m_themeOptionSelect = select.get();
      row->addChild(std::move(select));
      card->addChild(std::move(row));
      configureThemeOptionSelect();
    }

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

    footer->addChild(makeLabel(i18n::tr("setup-wizard.footer-note"), Style::fontSizeCaption * scale,
                               roleColor(ColorRole::OnSurfaceVariant)));

    auto button = std::make_unique<Button>();
    button->setText(i18n::tr("setup-wizard.get-started"));
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

void SetupWizardPanel::configureThemeOptionSelect() {
  if (m_themeOptionLabel == nullptr || m_themeOptionSelect == nullptr || m_config == nullptr) {
    return;
  }

  m_configuringThemeOptionSelect = true;
  m_themeOptionSelect->setOnSelectionChanged(nullptr);

  const auto& cfg = m_config->config();
  if (m_themeSource == ThemeSource::Wallpaper) {
    m_themeOptionLabel->setText(i18n::tr("setup-wizard.wallpaper-scheme"));
    m_themeOptionSelect->setOptions(labelsFromOptions(kWallpaperSchemes));
    m_themeOptionSelect->setSelectedIndex(selectedOptionIndex(kWallpaperSchemes, cfg.theme.wallpaperScheme));
    m_themeOptionSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*label*/) {
      if (m_configuringThemeOptionSelect || index >= std::size(kWallpaperSchemes)) {
        return;
      }
      m_config->setOverride({"theme", "source"}, std::string("wallpaper"));
      m_config->setOverride({"theme", "wallpaper_scheme"}, std::string(kWallpaperSchemes[index].value));
    });
  } else {
    m_themeOptionLabel->setText(i18n::tr("setup-wizard.premade-scheme"));
    m_builtinPalette = std::string(kDefaultBuiltinPalette);
    m_themeOptionSelect->setOptions(builtinPaletteNames());
    m_themeOptionSelect->setSelectedIndex(selectedBuiltinPaletteIndex(kDefaultBuiltinPalette));
    m_themeOptionSelect->setOnSelectionChanged([this](std::size_t /*index*/, std::string_view name) {
      if (m_configuringThemeOptionSelect) {
        return;
      }
      m_builtinPalette = std::string(name);
      m_config->setOverride({"theme", "source"}, std::string("builtin"));
      m_config->setOverride({"theme", "builtin"}, std::string(name));
    });
  }

  m_configuringThemeOptionSelect = false;
}

void SetupWizardPanel::commit() {
  if (m_telemetryToggle != nullptr) {
    m_config->setOverride({"shell", "telemetry_enabled"}, m_telemetryToggle->checked());
  }
  if (m_themeSource == ThemeSource::Builtin) {
    m_config->setOverride({"theme", "source"}, std::string(kDefaultThemeSource));
    m_config->setOverride({"theme", "builtin"},
                          m_builtinPalette.empty() ? std::string(kDefaultBuiltinPalette) : m_builtinPalette);
  }
  writeMarker();
  kLog.info("setup complete");
  PanelManager::instance().close();
}

void SetupWizardPanel::onClose() { writeMarker(); }
