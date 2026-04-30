#include "shell/control_center/audio_tab.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "dbus/mpris/mpris_service.h"
#include "i18n/i18n.h"
#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "system/desktop_entry.h"
#include "system/icon_resolver.h"
#include "ui/controls/button.h"
#include "ui/controls/context_menu.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/radio_button.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/slider.h"
#include "ui/palette.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

using namespace control_center;

namespace {

  constexpr float kDevicesColumnGrow = 3.0f;
  constexpr float kValueLabelWidth = Style::controlHeightLg + Style::spaceLg;
  constexpr float kVolumeSyncEpsilon = 0.005f; // 0.5%
  constexpr auto kVolumeCommitInterval = std::chrono::milliseconds(16);
  constexpr auto kVolumeStateHoldoff = std::chrono::milliseconds(180);

  // Used to resolve application icons in AudioTab.
  IconResolver g_iconResolver;

  bool isGenericAudioLabel(std::string_view value) {
    if (value.empty()) {
      return true;
    }
    std::string normalized;
    normalized.reserve(value.size());
    for (const char ch : value) {
      if (ch == ' ' || ch == '_' || ch == '.') {
        normalized.push_back('-');
      } else {
        normalized.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
      }
    }
    static constexpr std::string_view kBad[] = {"audio-src",   "audio-source", "audio-sink", "audio-output",
                                                "audio-input", "output",       "input",      "stream"};
    for (const auto token : kBad) {
      if (normalized == token) {
        return true;
      }
    }
    return false;
  }

  bool looksLikeRuntimeLauncher(std::string_view value) {
    std::string normalized(value);
    std::ranges::transform(normalized, normalized.begin(),
                           [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    if (normalized.empty()) {
      return false;
    }
    static constexpr std::string_view kRuntimeTokens[] = {
        "wine", "wine64", "wine64-preloader", "wineserver", "proton", "steam-runtime", "pressure-vessel",
    };
    for (const auto token : kRuntimeTokens) {
      if (normalized == token || normalized.find(token) != std::string::npos) {
        return true;
      }
    }
    return false;
  }

  bool isLikelyFallbackStreamLabel(std::string_view value) {
    std::string normalized(value);
    std::ranges::transform(normalized, normalized.begin(),
                           [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    for (char& ch : normalized) {
      if (std::isspace(static_cast<unsigned char>(ch)) != 0 || ch == '_') {
        ch = '-';
      }
    }
    while (normalized.find("--") != std::string::npos) {
      normalized.erase(normalized.find("--"), 1);
    }
    return normalized.starts_with("audio-stream-") || normalized.starts_with("stream-") ||
           normalized.find("audio-stream-#") != std::string::npos;
  }

  bool isLowConfidenceProgramAppName(const AudioNode& node) {
    auto normalizeId = [](std::string value) {
      if (value.ends_with(".desktop")) {
        value.erase(value.size() - std::string_view(".desktop").size());
      }
      const auto lastSlash = value.find_last_of('/');
      if (lastSlash != std::string::npos) {
        value = value.substr(lastSlash + 1);
      }
      std::ranges::transform(value, value.begin(),
                             [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
      return value;
    };

    if (node.applicationName.empty()) {
      return true;
    }
    if (isGenericAudioLabel(node.applicationName)) {
      return true;
    }

    const std::string appName = normalizeId(node.applicationName);
    const std::string appId = normalizeId(node.applicationId);
    const std::string appBinary = normalizeId(node.applicationBinary);
    const std::string nodeName = normalizeId(node.name);
    const std::string nodeDescription = normalizeId(node.description);
    if (appName.empty()) {
      return true;
    }
    if (!appId.empty() && appName == appId) {
      return false;
    }
    if (!appBinary.empty() && appName == appBinary) {
      return false;
    }
    if (!looksLikeRuntimeLauncher(appName) && (appName == nodeName || appName == nodeDescription)) {
      return false;
    }
    if (looksLikeRuntimeLauncher(appName)) {
      return true;
    }

    auto canonical = [](std::string value) {
      for (char& ch : value) {
        if (ch == '-' || ch == '_' || ch == '.' || std::isspace(static_cast<unsigned char>(ch)) != 0) {
          ch = ' ';
        }
      }
      // collapse spaces
      std::string out;
      out.reserve(value.size());
      bool prevSpace = true;
      for (const char ch : value) {
        const bool isSpace = std::isspace(static_cast<unsigned char>(ch)) != 0;
        if (isSpace) {
          if (!prevSpace) {
            out.push_back(' ');
          }
        } else {
          out.push_back(ch);
        }
        prevSpace = isSpace;
      }
      if (!out.empty() && out.back() == ' ') {
        out.pop_back();
      }
      return out;
    };

    const std::string canonicalName = canonical(appName);
    const std::string canonicalBinary = canonical(appBinary);
    const bool binaryMatchesName =
        !canonicalBinary.empty() &&
        (canonicalName == canonicalBinary || canonicalName.find(canonicalBinary) != std::string::npos ||
         canonicalBinary.find(canonicalName) != std::string::npos);
    // If we have no application.id and the binary disagrees with appName, appName is usually a runtime wrapper label.
    if (appId.empty() && !appBinary.empty() && !binaryMatchesName) {
      return true;
    }

    // Some stream clients expose a runtime/container name in application.name.
    // If application.id is more specific and does not match, prefer the id label.
    const bool idLooksSpecific = appId.find('.') != std::string::npos || appId.find('-') != std::string::npos ||
                                 appId.find('_') != std::string::npos;
    const bool nameLooksSimple = appName.find('.') == std::string::npos && appName.find('-') == std::string::npos &&
                                 appName.find('_') == std::string::npos && appName.find(' ') == std::string::npos;
    return !appId.empty() && appName != appId && idLooksSpecific && nameLooksSimple;
  }

  std::string prettifyIdentifier(std::string value) {
    if (value.empty()) {
      return value;
    }
    for (char& ch : value) {
      if (ch == '-' || ch == '_' || ch == '.') {
        ch = ' ';
      }
    }
    bool capitalize = true;
    for (char& ch : value) {
      if (std::isspace(static_cast<unsigned char>(ch)) != 0) {
        capitalize = true;
        continue;
      }
      if (capitalize) {
        ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
        capitalize = false;
      }
    }
    return value;
  }

  std::string lowerIdentifier(std::string value) {
    if (value.ends_with(".desktop")) {
      value.erase(value.size() - std::string_view(".desktop").size());
    }
    const auto lastSlash = value.find_last_of('/');
    if (lastSlash != std::string::npos) {
      value = value.substr(lastSlash + 1);
    }
    std::ranges::transform(value, value.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
  }

  void pushUnique(std::vector<std::string>& values, std::string value) {
    if (value.empty()) {
      return;
    }
    if (std::ranges::find(values, value) == values.end()) {
      values.push_back(std::move(value));
    }
  }

  void appendMatchToken(std::vector<std::string>& values, std::string value) {
    value = lowerIdentifier(std::move(value));
    for (char& ch : value) {
      if (ch == ' ' || ch == '_') {
        ch = '-';
      }
    }
    pushUnique(values, value);

    const auto lastDot = value.find_last_of('.');
    if (lastDot != std::string::npos && lastDot + 1 < value.size()) {
      pushUnique(values, value.substr(lastDot + 1));
    }

    static constexpr std::string_view kMprisPrefix = "org.mpris.mediaplayer2.";
    if (value.starts_with(kMprisPrefix)) {
      pushUnique(values, value.substr(kMprisPrefix.size()));
    }

    static constexpr std::string_view kClientSuffix = "-client";
    if (value.ends_with(kClientSuffix) && value.size() > kClientSuffix.size()) {
      pushUnique(values, value.substr(0, value.size() - kClientSuffix.size()));
    }
  }

  std::vector<std::string> streamMatchTokens(const AudioNode& node, std::string_view resolvedAppName) {
    std::vector<std::string> tokens;
    appendMatchToken(tokens, node.applicationId);
    appendMatchToken(tokens, node.applicationBinary);
    appendMatchToken(tokens, node.applicationName);
    appendMatchToken(tokens, node.iconName);
    appendMatchToken(tokens, std::string(resolvedAppName));
    return tokens;
  }

  std::vector<std::string> playerMatchTokens(const MprisPlayerInfo& player) {
    std::vector<std::string> tokens;
    appendMatchToken(tokens, player.desktopEntry);
    appendMatchToken(tokens, player.identity);
    appendMatchToken(tokens, player.busName);
    return tokens;
  }

  bool isValidDesktopMatch(std::string_view searchTerm, const DesktopEntry& entry) {
    if (searchTerm.empty()) {
      return false;
    }
    const std::string search = lowerIdentifier(std::string(searchTerm));
    const std::string id = lowerIdentifier(entry.id);
    const std::string name = lowerIdentifier(entry.name);
    const std::string icon = lowerIdentifier(entry.icon);
    return (!id.empty() && (id.find(search) != std::string::npos || search.find(id) != std::string::npos)) ||
           (!name.empty() && (name.find(search) != std::string::npos || search.find(name) != std::string::npos)) ||
           (!icon.empty() && (icon.find(search) != std::string::npos || search.find(icon) != std::string::npos));
  }

  const DesktopEntry* findDesktopEntryByTerm(std::string_view term) {
    if (term.empty()) {
      return nullptr;
    }
    const std::string key = lowerIdentifier(std::string(term));
    for (const auto& entry : desktopEntries()) {
      if (isValidDesktopMatch(key, entry)) {
        return &entry;
      }
    }
    return nullptr;
  }

  const DesktopEntry* findDesktopEntryForNode(const AudioNode& node, std::string_view resolvedAppName) {
    const std::string binary = lowerIdentifier(node.applicationBinary);
    if (!binary.empty()) {
      if (const DesktopEntry* entry = findDesktopEntryByTerm(binary)) {
        return entry;
      }
    }
    const std::string appId = lowerIdentifier(node.applicationId);
    if (!appId.empty()) {
      if (const DesktopEntry* entry = findDesktopEntryByTerm(appId)) {
        return entry;
      }
    }
    const std::string appName = lowerIdentifier(node.applicationName);
    if (!appName.empty() && !isGenericAudioLabel(appName) && !looksLikeRuntimeLauncher(appName)) {
      if (const DesktopEntry* entry = findDesktopEntryByTerm(appName)) {
        return entry;
      }
    }
    const std::string resolved = lowerIdentifier(std::string(resolvedAppName));
    if (!resolved.empty() && !isGenericAudioLabel(resolved) && !looksLikeRuntimeLauncher(resolved)) {
      if (const DesktopEntry* entry = findDesktopEntryByTerm(resolved)) {
        return entry;
      }
    }
    const std::string nodeName = lowerIdentifier(node.name);
    if (!nodeName.empty()) {
      if (const DesktopEntry* entry = findDesktopEntryByTerm(nodeName)) {
        return entry;
      }
    }
    return nullptr;
  }

  std::string resolveProgramAppName(const AudioNode& node, const MprisPlayerInfo* player) {
    std::string resolved = node.applicationName;
    const bool appNameIsGeneric = isLowConfidenceProgramAppName(node);

    if (appNameIsGeneric) {
      // Force fallback chain when app name is considered low-confidence.
      resolved.clear();
    }
    if (resolved.empty()) {
      if (!node.applicationId.empty() && !isGenericAudioLabel(node.applicationId)) {
        resolved = prettifyIdentifier(node.applicationId);
      }
    }
    if (resolved.empty() || isGenericAudioLabel(resolved)) {
      if (!node.applicationBinary.empty() && !isGenericAudioLabel(node.applicationBinary)) {
        resolved = prettifyIdentifier(node.applicationBinary);
      }
    }
    if ((resolved.empty() || isGenericAudioLabel(resolved) || looksLikeRuntimeLauncher(resolved)) &&
        !node.streamTitle.empty() && !isGenericAudioLabel(node.streamTitle) &&
        !looksLikeRuntimeLauncher(node.streamTitle) && !isLikelyFallbackStreamLabel(node.streamTitle)) {
      resolved = node.streamTitle;
    }
    if ((resolved.empty() || isGenericAudioLabel(resolved) || looksLikeRuntimeLauncher(resolved) ||
         (lowerIdentifier(resolved) == lowerIdentifier(node.name) &&
          lowerIdentifier(resolved) == lowerIdentifier(node.description) && node.applicationId.empty() &&
          node.applicationBinary.empty())) &&
        player != nullptr && !player->identity.empty() && !isGenericAudioLabel(player->identity)) {
      resolved = player->identity;
    }
    if (const DesktopEntry* entry = findDesktopEntryForNode(node, resolved);
        entry != nullptr && !entry->name.empty() && !isGenericAudioLabel(entry->name)) {
      resolved = entry->name;
    }
    if (resolved.empty() || isGenericAudioLabel(resolved)) {
      resolved = !node.name.empty() ? node.name : node.description;
    }
    if (isGenericAudioLabel(resolved) && !node.iconName.empty()) {
      resolved = prettifyIdentifier(node.iconName);
    }
    if ((resolved.empty() || isGenericAudioLabel(resolved)) && player != nullptr && !player->identity.empty()) {
      resolved = player->identity;
    }
    if (resolved.empty()) {
      resolved = "Application";
    }
    return resolved;
  }

  bool tokenListsMatch(const std::vector<std::string>& left, const std::vector<std::string>& right) {
    for (const auto& a : left) {
      if (a.empty() || isGenericAudioLabel(a)) {
        continue;
      }
      for (const auto& b : right) {
        if (b.empty() || isGenericAudioLabel(b)) {
          continue;
        }
        if (a == b) {
          return true;
        }
      }
    }
    return false;
  }

  std::string nowPlayingLabel(const MprisPlayerInfo* player) {
    if (player == nullptr || player->title.empty()) {
      return {};
    }
    const std::string artists = joinedArtists(player->artists);
    return artists.empty() ? player->title : artists + " - " + player->title;
  }

  const MprisPlayerInfo* findMatchingPlayer(const std::vector<MprisPlayerInfo>& players, const AudioNode& node,
                                            std::string_view resolvedAppName) {
    const std::vector<std::string> streamTokens = streamMatchTokens(node, resolvedAppName);
    const MprisPlayerInfo* fallback = nullptr;
    for (const auto& player : players) {
      if (!tokenListsMatch(streamTokens, playerMatchTokens(player))) {
        continue;
      }
      if (player.playbackStatus == "Playing") {
        return &player;
      }
      if (fallback == nullptr) {
        fallback = &player;
      }
    }
    return fallback;
  }

  std::vector<MprisPlayerInfo> allMprisPlayers(const MprisService* mpris) {
    if (mpris == nullptr) {
      return {};
    }
    std::vector<MprisPlayerInfo> players;
    const auto& cachedPlayers = mpris->players();
    players.reserve(cachedPlayers.size());
    for (const auto& [_, player] : cachedPlayers) {
      players.push_back(player);
    }
    return players;
  }

  void appendDesktopIconCandidates(std::vector<std::string>& candidates, const AudioNode& node,
                                   std::string_view resolvedAppName) {
    if (const DesktopEntry* entry = findDesktopEntryForNode(node, resolvedAppName);
        entry != nullptr && !entry->icon.empty()) {
      pushUnique(candidates, entry->icon);
      pushUnique(candidates, entry->id);
    }
  }

  void appendFallbackIconCandidates(std::vector<std::string>& candidates, const AudioNode& node) {
    if (looksLikeRuntimeLauncher(node.applicationName) || looksLikeRuntimeLauncher(node.applicationBinary) ||
        looksLikeRuntimeLauncher(node.applicationId) || isLikelyFallbackStreamLabel(node.streamTitle)) {
      for (const std::string icon :
           {"wine", "steam", "applications-games", "application-x-executable", "application-default-icon"}) {
        pushUnique(candidates, icon);
      }
    }
  }

  class AudioDeviceRow : public Flex {
  public:
    explicit AudioDeviceRow(std::function<void()> onSelect) : m_onSelect(std::move(onSelect)) {
      setDirection(FlexDirection::Horizontal);
      setAlign(FlexAlign::Center);
      setGap(Style::spaceSm);
      setPadding(Style::spaceSm, Style::spaceMd);
      setMinHeight(Style::controlHeightLg);
      setRadius(Style::radiusMd);
      setFill(roleColor(ColorRole::Surface));
      clearBorder();

      auto radio = std::make_unique<RadioButton>();
      radio->setOnChange([this](bool) {
        if (m_onSelect) {
          m_onSelect();
        }
      });
      m_radio = static_cast<RadioButton*>(addChild(std::move(radio)));

      auto title = std::make_unique<Label>();
      title->setBold(true);
      title->setFontSize(Style::fontSizeBody);
      title->setColor(roleColor(ColorRole::OnSurface));
      title->setFlexGrow(1.0f);
      m_title = title.get();
      addChild(std::move(title));

      m_detail = nullptr;

      auto area = std::make_unique<InputArea>();
      area->setPropagateEvents(true);
      area->setOnEnter([this](const InputArea::PointerData&) { applyState(); });
      area->setOnLeave([this]() { applyState(); });
      area->setOnPress([this](const InputArea::PointerData&) { applyState(); });
      area->setOnClick([this](const InputArea::PointerData&) {
        if (m_onSelect) {
          m_onSelect();
        }
      });
      m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

      applyState();
      m_paletteConn = paletteChanged().connect([this] { applyState(); });
    }

    void setDevice(const AudioNode& node) {
      m_radio->setChecked(node.isDefault);
      const std::string title = !node.description.empty() ? node.description : node.name;

      if (m_title != nullptr) {
        m_title->setText(title);
      }
    }

    void doLayout(Renderer& renderer) override {
      if (m_radio == nullptr || m_title == nullptr || m_inputArea == nullptr) {
        return;
      }

      m_radio->layout(renderer);

      const float textMaxWidth = std::max(0.0f, width() - paddingLeft() - paddingRight() - gap() - m_radio->width());
      m_title->setMaxWidth(textMaxWidth);

      m_inputArea->setVisible(false);
      Flex::doLayout(renderer);
      m_inputArea->setVisible(true);
      m_inputArea->setPosition(0.0f, 0.0f);
      m_inputArea->setSize(width(), height());

      applyState();
    }

    LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override {
      return measureByLayout(renderer, constraints);
    }

    void doArrange(Renderer& renderer, const LayoutRect& rect) override { arrangeByLayout(renderer, rect); }

  private:
    void applyState() {
      if (pressed()) {
        setFill(roleColor(ColorRole::Primary));
        setBorder(roleColor(ColorRole::Primary), Style::borderWidth);
        if (m_title != nullptr) {
          m_title->setColor(roleColor(ColorRole::OnPrimary));
        }
        return;
      }

      setFill(roleColor(ColorRole::Surface));
      if (hovered()) {
        setBorder(roleColor(ColorRole::Primary), Style::borderWidth);
      } else {
        clearBorder();
      }
      if (m_title != nullptr) {
        m_title->setColor(roleColor(ColorRole::OnSurface));
      }
    }

    [[nodiscard]] bool hovered() const noexcept { return m_inputArea != nullptr && m_inputArea->hovered(); }
    [[nodiscard]] bool pressed() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

    std::function<void()> m_onSelect;
    RadioButton* m_radio = nullptr;
    Label* m_title = nullptr;
    Label* m_detail = nullptr;
    InputArea* m_inputArea = nullptr;
    Signal<>::ScopedConnection m_paletteConn;
  };

  class ProgramVolumeRow : public Flex {
  public:
    ProgramVolumeRow(PipeWireService* audio, std::uint32_t id, float sliderMax, float scale,
                     std::function<void(float)> onQueueVolume, std::function<void()> onCommitVolume)
        : m_audio(audio), m_id(id), m_sliderMax(sliderMax), m_onQueueVolume(std::move(onQueueVolume)),
          m_onCommitVolume(std::move(onCommitVolume)) {
      setDirection(FlexDirection::Vertical);
      setAlign(FlexAlign::Stretch);
      setGap(Style::spaceXs * scale);
      setPadding(Style::spaceXs * scale, Style::spaceMd * scale);
      setMinHeight((Style::controlHeightLg + Style::spaceXs) * scale);
      setRadius(Style::radiusMd * scale);
      setFill(roleColor(ColorRole::Surface));
      clearBorder();

      constexpr float kIconSizeSm = 28.0f;
      m_iconSize = kIconSizeSm * scale;

      auto headerRow = std::make_unique<Flex>();
      headerRow->setDirection(FlexDirection::Horizontal);
      headerRow->setAlign(FlexAlign::Center);
      headerRow->setGap(Style::spaceSm * scale);
      headerRow->setFlexGrow(0.0f);
      m_headerRow = headerRow.get();

      auto icon = std::make_unique<Image>();
      icon->setFit(ImageFit::Contain);
      icon->setRadius(Style::radiusMd * scale);
      icon->setSize(m_iconSize, m_iconSize);
      icon->setVisible(false);
      m_icon = icon.get();
      headerRow->addChild(std::move(icon));

      auto textCol = std::make_unique<Flex>();
      textCol->setDirection(FlexDirection::Vertical);
      textCol->setAlign(FlexAlign::Start);
      textCol->setJustify(FlexJustify::Center);
      textCol->setGap(0.0f);
      textCol->setFlexGrow(1.0f);

      auto appName = std::make_unique<Label>();
      appName->setBold(true);
      appName->setFontSize(Style::fontSizeBody * scale);
      appName->setColor(roleColor(ColorRole::OnSurface));
      m_appNameLabel = appName.get();
      textCol->addChild(std::move(appName));

      auto subtitle = std::make_unique<Label>();
      subtitle->setCaptionStyle();
      subtitle->setFontSize(Style::fontSizeCaption * scale);
      subtitle->setColor(roleColor(ColorRole::OnSurfaceVariant));
      subtitle->setVisible(false);
      m_subtitleLabel = subtitle.get();
      textCol->addChild(std::move(subtitle));

      m_textCol = textCol.get();
      headerRow->addChild(std::move(textCol));
      addChild(std::move(headerRow));

      auto controlsRow = std::make_unique<Flex>();
      controlsRow->setDirection(FlexDirection::Horizontal);
      controlsRow->setAlign(FlexAlign::Center);
      controlsRow->setGap(Style::spaceSm * scale);
      controlsRow->setFlexGrow(0.0f);
      m_controlsRow = controlsRow.get();

      auto slider = std::make_unique<Slider>();
      slider->setRange(0.0f, sliderMax);
      slider->setStep(0.01f);
      slider->setFlexGrow(1.0f);
      slider->setControlHeight(Style::controlHeight * scale);
      slider->setTrackHeight(Style::sliderTrackHeight * scale);
      slider->setThumbSize(Style::sliderThumbSize * scale);
      slider->setWheelAdjustEnabled(true);
      slider->setOnValueChanged([this](float value) {
        if (m_syncing || m_audio == nullptr) {
          return;
        }
        if (m_valueLabel != nullptr) {
          m_valueLabel->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
        }
        if (m_onQueueVolume) {
          m_onQueueVolume(value);
        }
      });
      slider->setOnDragEnd([this]() {
        if (m_audio == nullptr) {
          return;
        }
        if (m_onCommitVolume) {
          m_onCommitVolume();
        }
      });
      m_slider = static_cast<Slider*>(controlsRow->addChild(std::move(slider)));

      auto value = std::make_unique<Label>();
      value->setText("0%");
      value->setBold(true);
      value->setFontSize(Style::fontSizeBody * scale);
      value->setMinWidth(kValueLabelWidth * scale);
      m_valueLabel = value.get();
      controlsRow->addChild(std::move(value));

      auto mute = std::make_unique<Button>();
      mute->setGlyph("volume-high");
      mute->setVariant(ButtonVariant::Default);
      mute->setGlyphSize(Style::fontSizeBody * scale);
      mute->setMinWidth(Style::controlHeightSm * scale);
      mute->setMinHeight(Style::controlHeightSm * scale);
      mute->setPadding(Style::spaceXs * scale);
      mute->setRadius(Style::radiusMd * scale);
      mute->setOnClick([this]() {
        if (m_audio == nullptr) {
          return;
        }
        const bool nextMuted = !m_muted;
        m_audio->setProgramOutputMuted(m_id, nextMuted);
        PanelManager::instance().refresh();
      });
      m_muteButton = mute.get();
      controlsRow->addChild(std::move(mute));
      addChild(std::move(controlsRow));
    }

    void doLayout(Renderer& renderer) override {
      if (m_icon != nullptr) {
        // Load icons lazily during layout.
        const bool iconKeyChanged = m_lastIconKey != m_iconKey;
        if (iconKeyChanged && !m_iconKey.empty()) {
          bool loaded = false;
          for (const std::string& candidate : m_iconCandidates) {
            const auto& resolved = g_iconResolver.resolve(candidate);
            if (!resolved.empty()) {
              if (!m_lastIconPath.empty() && resolved == m_lastIconPath) {
                loaded = true;
                break;
              }
              const int targetPx = static_cast<int>(std::round(m_iconSize));
              loaded = m_icon->setSourceFile(renderer, resolved, targetPx, true);
              if (loaded) {
                m_lastIconPath = resolved;
                m_icon->setVisible(true);
              }
              break;
            }
          }
          if (!loaded) {
            m_icon->setVisible(false);
            m_lastIconPath.clear();
          }
          m_lastIconKey = m_iconKey;
        }
      }

      // Bound labels to protect row layout.
      if (m_appNameLabel != nullptr) {
        const float textMax = std::max(80.0f, width() - m_iconSize - gap() - paddingLeft() - paddingRight());
        m_appNameLabel->setMaxWidth(textMax);
        if (m_subtitleLabel != nullptr) {
          m_subtitleLabel->setMaxWidth(textMax);
        }
      }

      Flex::doLayout(renderer);
    }

    LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override {
      return measureByLayout(renderer, constraints);
    }

    void doArrange(Renderer& renderer, const LayoutRect& rect) override { arrangeByLayout(renderer, rect); }

    void syncFromNode(const AudioNode& node, const MprisPlayerInfo* player, bool isDefault, float sliderMax,
                      bool nodeEnabled) {
      std::string resolvedAppName = resolveProgramAppName(node, player);

      std::string title = node.streamTitle;
      if (title.empty() && !node.name.empty() && node.name != resolvedAppName) {
        title = node.name;
      }
      if (title == resolvedAppName || isGenericAudioLabel(title) || isLikelyFallbackStreamLabel(title)) {
        title.clear();
      }
      if (title.empty()) {
        title = nowPlayingLabel(player);
      }

      m_appNameLabel->setText((isDefault ? "• " : "") + resolvedAppName);
      if (!title.empty() && title != resolvedAppName) {
        m_subtitleLabel->setVisible(true);
        m_subtitleLabel->setText(title);
      } else {
        m_subtitleLabel->setVisible(false);
        m_subtitleLabel->setText("");
      }

      const float clampedVolume = std::clamp(node.volume, 0.0f, sliderMax);
      const bool shouldSetSlider = nodeEnabled && m_slider != nullptr && !m_slider->dragging() && !m_syncing;
      if (m_slider != nullptr) {
        if (std::abs(m_sliderMax - sliderMax) >= 0.0001f) {
          m_sliderMax = sliderMax;
          m_slider->setRange(0.0f, sliderMax);
        }
        m_slider->setEnabled(nodeEnabled);
      }

      m_muted = node.muted;
      if (m_muteButton != nullptr) {
        m_muteButton->setEnabled(nodeEnabled);
        m_muteButton->setGlyph(m_muted ? "volume-mute" : "volume-high");
      }

      if (shouldSetSlider) {
        m_syncing = true;
        if (m_slider != nullptr) {
          m_slider->setValue(clampedVolume);
        }
        m_syncing = false;
        if (m_valueLabel != nullptr) {
          m_valueLabel->setText(std::to_string(static_cast<int>(std::round(clampedVolume * 100.0f))) + "%");
        }
      }

      m_iconCandidates.clear();
      m_iconKey.clear();
      auto sanitize = [](std::string s) {
        const auto lastSlash = s.find_last_of('/');
        if (lastSlash != std::string::npos) {
          s = s.substr(lastSlash + 1);
        }
        if (s.ends_with(".desktop")) {
          s.erase(s.size() - std::string_view(".desktop").size());
        }

        for (std::string_view sep : {" - "}) {
          const auto pos = s.find(sep);
          if (pos != std::string::npos) {
            s = s.substr(0, pos);
            break;
          }
        }

        for (char& c : s) {
          if (c == ' ' || c == '_') {
            c = '-';
          } else {
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
          }
        }
        return s;
      };

      const std::string candidateIcon = sanitize(node.iconName);
      const std::string candidateId = sanitize(node.applicationId);
      const std::string candidateApp = sanitize(resolvedAppName);
      const std::string candidateFallback =
          sanitize(node.applicationBinary.empty() ? node.name : node.applicationBinary);
      if (!candidateApp.empty()) {
        pushUnique(m_iconCandidates, candidateApp);
        pushUnique(m_iconCandidates, candidateApp + ".desktop");
      }
      if (!candidateFallback.empty() && candidateFallback != candidateApp) {
        pushUnique(m_iconCandidates, candidateFallback);
        pushUnique(m_iconCandidates, candidateFallback + ".desktop");
      }
      if (!candidateId.empty() && candidateId != candidateApp && candidateId != candidateFallback) {
        pushUnique(m_iconCandidates, candidateId);
        pushUnique(m_iconCandidates, candidateId + ".desktop");
      }
      appendDesktopIconCandidates(m_iconCandidates, node, resolvedAppName);
      appendFallbackIconCandidates(m_iconCandidates, node);
      // Keep raw node icon as final fallback (Electron streams often report Chromium icon names).
      if (!candidateIcon.empty()) {
        pushUnique(m_iconCandidates, candidateIcon);
        pushUnique(m_iconCandidates, candidateIcon + ".desktop");
      }
      for (const auto& candidate : m_iconCandidates) {
        m_iconKey += candidate;
        m_iconKey.push_back('|');
      }
      m_iconKey += title;
    }

    [[nodiscard]] std::uint32_t id() const noexcept { return m_id; }
    [[nodiscard]] bool dragging() const noexcept { return m_slider != nullptr && m_slider->dragging(); }

  private:
    PipeWireService* m_audio = nullptr;
    std::uint32_t m_id = 0;

    Image* m_icon = nullptr;
    float m_iconSize = 0.0f;
    Flex* m_headerRow = nullptr;
    Flex* m_controlsRow = nullptr;
    Label* m_appNameLabel = nullptr;
    Label* m_subtitleLabel = nullptr;
    Flex* m_textCol = nullptr;

    std::string m_iconKey;
    std::string m_lastIconKey;
    std::string m_lastIconPath;
    std::vector<std::string> m_iconCandidates;

    Slider* m_slider = nullptr;
    Label* m_valueLabel = nullptr;
    Button* m_muteButton = nullptr;

    bool m_syncing = false;
    bool m_muted = false;
    float m_sliderMax = 1.0f;

    std::function<void(float)> m_onQueueVolume;
    std::function<void()> m_onCommitVolume;
  };

  std::vector<AudioNode> sortedDevices(const std::vector<AudioNode>& devices) {
    std::vector<AudioNode> sorted = devices;
    std::ranges::sort(sorted, [](const AudioNode& a, const AudioNode& b) {
      const std::string& left = !a.description.empty() ? a.description : a.name;
      const std::string& right = !b.description.empty() ? b.description : b.name;
      if (left != right) {
        return left < right;
      }
      return a.id < b.id;
    });
    return sorted;
  }

  void addEmptyState(Flex& parent, const std::string& title, const std::string& body, float scale) {
    auto card = std::make_unique<Flex>();
    card->setDirection(FlexDirection::Vertical);
    card->setAlign(FlexAlign::Start);
    card->setGap(Style::spaceXs * scale);
    card->setPadding(Style::spaceMd * scale);
    card->setRadius(Style::radiusMd * scale);
    card->setFill(roleColor(ColorRole::Surface));
    card->clearBorder();

    auto titleLabel = std::make_unique<Label>();
    titleLabel->setText(title);
    titleLabel->setBold(true);
    titleLabel->setFontSize(Style::fontSizeBody * scale);
    titleLabel->setColor(roleColor(ColorRole::OnSurface));
    card->addChild(std::move(titleLabel));

    auto bodyLabel = std::make_unique<Label>();
    bodyLabel->setText(body);
    bodyLabel->setCaptionStyle();
    bodyLabel->setFontSize(Style::fontSizeCaption * scale);
    bodyLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
    card->addChild(std::move(bodyLabel));

    parent.addChild(std::move(card));
  }

  std::string deviceListKey(const std::vector<AudioNode>& devices) {
    std::string key;
    for (const auto& device : devices) {
      key += std::to_string(device.id);
      key.push_back(':');
      key += device.isDefault ? '1' : '0';
      key.push_back(':');
      key += device.name;
      key.push_back(':');
      key += device.description;
      key.push_back('\n');
    }
    return key;
  }

  std::string widestPercentLabel(float sliderMaxValue) {
    const std::size_t digits =
        std::to_string(static_cast<int>(std::round(std::max(0.0f, sliderMaxValue) * 100.0f))).size();
    return std::string(std::max<std::size_t>(1, digits), '8') + "%";
  }

} // namespace

AudioTab::AudioTab(PipeWireService* audio, MprisService* mpris, ConfigService* config)
    : m_audio(audio), m_mpris(mpris), m_config(config) {}

bool AudioTab::dragging() const noexcept {
  if ((m_outputSlider != nullptr && m_outputSlider->dragging()) ||
      (m_inputSlider != nullptr && m_inputSlider->dragging())) {
    return true;
  }
  for (Flex* row : m_programRows) {
    auto* programRow = static_cast<ProgramVolumeRow*>(row);
    if (programRow != nullptr && programRow->dragging()) {
      return true;
    }
  }
  return false;
}

bool AudioTab::dismissTransientUi() {
  if (!m_deviceMenuOpen) {
    return false;
  }
  m_deviceMenuOpen = false;
  return true;
}

std::unique_ptr<Flex> AudioTab::create() {
  const float scale = contentScale();
  const float sliderMax = sliderMaxPercent() / 100.0f;

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto volumeRow = std::make_unique<Flex>();
  volumeRow->setDirection(FlexDirection::Horizontal);
  volumeRow->setAlign(FlexAlign::Stretch);
  volumeRow->setGap(Style::spaceSm * scale);
  // Keep volume cards at natural content height.
  volumeRow->setFlexGrow(0.0f);
  m_volumeColumn = volumeRow.get();

  auto outputVolumeCard = std::make_unique<Flex>();
  applySectionCardStyle(*outputVolumeCard, scale);
  outputVolumeCard->setFlexGrow(1.0f);
  m_outputVolumeCard = outputVolumeCard.get();

  auto outputHeader = std::make_unique<Flex>();
  outputHeader->setDirection(FlexDirection::Horizontal);
  outputHeader->setAlign(FlexAlign::Center);
  outputHeader->setJustify(FlexJustify::SpaceBetween);
  outputHeader->setGap(Style::spaceXs * scale);
  addTitle(*outputHeader, i18n::tr("control-center.audio.output-volume"), scale);

  auto outputDeviceLabel = std::make_unique<Label>();
  outputDeviceLabel->setText(i18n::tr("control-center.audio.no-output-selected"));
  outputDeviceLabel->setCaptionStyle();
  outputDeviceLabel->setFontSize(Style::fontSizeCaption * scale);
  outputDeviceLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_outputDeviceLabel = outputDeviceLabel.get();

  auto outputMenuButton = std::make_unique<Button>();
  outputMenuButton->setGlyph("menu");
  outputMenuButton->setVariant(ButtonVariant::Ghost);
  outputMenuButton->setGlyphSize(Style::fontSizeCaption * scale);
  outputMenuButton->setPadding(Style::spaceXs * scale);
  outputMenuButton->setRadius(Style::radiusMd * scale);
  outputMenuButton->setEnabled(false);
  outputMenuButton->setOnClick([this]() {
    const bool wasOpenForOutput = m_deviceMenuOpen && m_deviceMenuIsOutput;
    m_deviceMenuIsOutput = true;
    m_deviceMenuOpen = !wasOpenForOutput;
    PanelManager::instance().refresh();
  });
  m_outputDeviceMenuButton = outputMenuButton.get();
  outputHeader->addChild(std::move(outputMenuButton));
  m_outputDeviceMenuAnchor = outputHeader.get();
  outputVolumeCard->addChild(std::move(outputHeader));
  outputVolumeCard->addChild(std::move(outputDeviceLabel));

  auto outputRow = std::make_unique<Flex>();
  outputRow->setDirection(FlexDirection::Horizontal);
  outputRow->setAlign(FlexAlign::Center);
  outputRow->setGap(Style::spaceSm * scale);

  auto outputSlider = std::make_unique<Slider>();
  outputSlider->setRange(0.0f, sliderMax);
  outputSlider->setStep(0.01f);
  outputSlider->setFlexGrow(1.0f);
  outputSlider->setControlHeight(Style::controlHeight * scale);
  outputSlider->setTrackHeight(Style::sliderTrackHeight * scale);
  outputSlider->setThumbSize(Style::sliderThumbSize * scale);
  outputSlider->setWheelAdjustEnabled(true);
  outputSlider->setOnValueChanged([this](float value) {
    if (m_syncingOutputSlider || m_audio == nullptr) {
      return;
    }
    m_sinkVolumeDebounceTimer.stop();
    queueSinkVolume(value);
    flushPendingVolumes();
    if (m_outputValue != nullptr) {
      m_outputValue->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
    }
  });
  outputSlider->setOnDragEnd([this]() {
    m_sinkVolumeDebounceTimer.stop();
    flushPendingVolumes();
  });
  m_outputSlider = outputSlider.get();
  outputRow->addChild(std::move(outputSlider));

  auto outputValue = std::make_unique<Label>();
  outputValue->setText("0%");
  outputValue->setBold(true);
  outputValue->setFontSize(Style::fontSizeBody * scale);
  outputValue->setMinWidth(kValueLabelWidth * scale);
  m_outputValue = outputValue.get();
  outputRow->addChild(std::move(outputValue));

  auto outputMuteButton = std::make_unique<Button>();
  outputMuteButton->setGlyph("volume-high");
  outputMuteButton->setVariant(ButtonVariant::Default);
  outputMuteButton->setGlyphSize(Style::fontSizeBody * scale);
  outputMuteButton->setMinWidth(Style::controlHeightSm * scale);
  outputMuteButton->setMinHeight(Style::controlHeightSm * scale);
  outputMuteButton->setPadding(Style::spaceXs * scale);
  outputMuteButton->setRadius(Style::radiusMd * scale);
  outputMuteButton->setOnClick([this]() {
    if (m_audio == nullptr) {
      return;
    }
    if (const AudioNode* sink = m_audio->defaultSink(); sink != nullptr) {
      m_audio->setSinkMuted(sink->id, !sink->muted);
      PanelManager::instance().refresh();
    }
  });
  m_outputMuteButton = outputMuteButton.get();
  outputRow->addChild(std::move(outputMuteButton));
  outputVolumeCard->addChild(std::move(outputRow));
  volumeRow->addChild(std::move(outputVolumeCard));

  auto inputVolumeCard = std::make_unique<Flex>();
  applySectionCardStyle(*inputVolumeCard, scale);
  inputVolumeCard->setFlexGrow(1.0f);
  m_inputVolumeCard = inputVolumeCard.get();

  auto inputHeader = std::make_unique<Flex>();
  inputHeader->setDirection(FlexDirection::Horizontal);
  inputHeader->setAlign(FlexAlign::Center);
  inputHeader->setJustify(FlexJustify::SpaceBetween);
  inputHeader->setGap(Style::spaceXs * scale);
  addTitle(*inputHeader, i18n::tr("control-center.audio.input-volume"), scale);

  auto inputDeviceLabel = std::make_unique<Label>();
  inputDeviceLabel->setText(i18n::tr("control-center.audio.no-input-selected"));
  inputDeviceLabel->setCaptionStyle();
  inputDeviceLabel->setFontSize(Style::fontSizeCaption * scale);
  inputDeviceLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_inputDeviceLabel = inputDeviceLabel.get();

  auto inputMenuButton = std::make_unique<Button>();
  inputMenuButton->setGlyph("menu");
  inputMenuButton->setVariant(ButtonVariant::Ghost);
  inputMenuButton->setGlyphSize(Style::fontSizeCaption * scale);
  inputMenuButton->setPadding(Style::spaceXs * scale);
  inputMenuButton->setRadius(Style::radiusMd * scale);
  inputMenuButton->setEnabled(false);
  inputMenuButton->setOnClick([this]() {
    const bool wasOpenForInput = m_deviceMenuOpen && !m_deviceMenuIsOutput;
    m_deviceMenuIsOutput = false;
    m_deviceMenuOpen = !wasOpenForInput;
    PanelManager::instance().refresh();
  });
  m_inputDeviceMenuButton = inputMenuButton.get();
  inputHeader->addChild(std::move(inputMenuButton));
  m_inputDeviceMenuAnchor = inputHeader.get();
  inputVolumeCard->addChild(std::move(inputHeader));
  inputVolumeCard->addChild(std::move(inputDeviceLabel));

  auto inputRow = std::make_unique<Flex>();
  inputRow->setDirection(FlexDirection::Horizontal);
  inputRow->setAlign(FlexAlign::Center);
  inputRow->setGap(Style::spaceSm * scale);

  auto inputSlider = std::make_unique<Slider>();
  inputSlider->setRange(0.0f, sliderMax);
  inputSlider->setStep(0.01f);
  inputSlider->setFlexGrow(1.0f);
  inputSlider->setControlHeight(Style::controlHeight * scale);
  inputSlider->setTrackHeight(Style::sliderTrackHeight * scale);
  inputSlider->setThumbSize(Style::sliderThumbSize * scale);
  inputSlider->setWheelAdjustEnabled(true);
  inputSlider->setOnValueChanged([this](float value) {
    if (m_syncingInputSlider || m_audio == nullptr) {
      return;
    }
    m_sourceVolumeDebounceTimer.stop();
    queueSourceVolume(value);
    flushPendingVolumes();
    if (m_inputValue != nullptr) {
      m_inputValue->setText(std::to_string(static_cast<int>(std::round(value * 100.0f))) + "%");
    }
  });
  inputSlider->setOnDragEnd([this]() {
    m_sourceVolumeDebounceTimer.stop();
    flushPendingVolumes();
  });
  m_inputSlider = inputSlider.get();
  inputRow->addChild(std::move(inputSlider));

  auto inputValue = std::make_unique<Label>();
  inputValue->setText("0%");
  inputValue->setBold(true);
  inputValue->setFontSize(Style::fontSizeBody * scale);
  inputValue->setMinWidth(kValueLabelWidth * scale);
  m_inputValue = inputValue.get();
  inputRow->addChild(std::move(inputValue));

  auto inputMuteButton = std::make_unique<Button>();
  inputMuteButton->setGlyph("microphone");
  inputMuteButton->setVariant(ButtonVariant::Default);
  inputMuteButton->setGlyphSize(Style::fontSizeBody * scale);
  inputMuteButton->setMinWidth(Style::controlHeightSm * scale);
  inputMuteButton->setMinHeight(Style::controlHeightSm * scale);
  inputMuteButton->setPadding(Style::spaceXs * scale);
  inputMuteButton->setRadius(Style::radiusMd * scale);
  inputMuteButton->setOnClick([this]() {
    if (m_audio == nullptr) {
      return;
    }
    if (const AudioNode* source = m_audio->defaultSource(); source != nullptr) {
      m_audio->setSourceMuted(source->id, !source->muted);
      PanelManager::instance().refresh();
    }
  });
  m_inputMuteButton = inputMuteButton.get();
  inputRow->addChild(std::move(inputMuteButton));
  inputVolumeCard->addChild(std::move(inputRow));
  volumeRow->addChild(std::move(inputVolumeCard));

  tab->addChild(std::move(volumeRow));

  auto programCard = std::make_unique<Flex>();
  applySectionCardStyle(*programCard, scale);
  programCard->setFlexGrow(1.0f);
  m_programCard = programCard.get();

  addTitle(*programCard, i18n::tr("control-center.audio.application-volumes"), scale);

  auto programScroll = std::make_unique<ScrollView>();
  programScroll->setFlexGrow(1.0f);
  programScroll->setScrollbarVisible(true);
  programScroll->setViewportPaddingH(0.0f);
  programScroll->setViewportPaddingV(0.0f);
  programScroll->clearFill();
  programScroll->clearBorder();
  m_programScroll = programScroll.get();

  m_programList = programScroll->content();
  m_programList->setDirection(FlexDirection::Vertical);
  m_programList->setAlign(FlexAlign::Stretch);
  m_programList->setGap(Style::spaceSm * scale);

  programCard->addChild(std::move(programScroll));
  tab->addChild(std::move(programCard));

  auto dismissCatcher = std::make_unique<InputArea>();
  dismissCatcher->setParticipatesInLayout(false);
  dismissCatcher->setVisible(false);
  dismissCatcher->setZIndex(19);
  dismissCatcher->setOnPress([this](const InputArea::PointerData&) {
    if (!m_deviceMenuOpen) {
      return;
    }
    m_deviceMenuOpen = false;
    PanelManager::instance().refresh();
  });
  m_deviceMenuDismissCatcher = static_cast<InputArea*>(tab->addChild(std::move(dismissCatcher)));

  auto deviceMenu = std::make_unique<ContextMenuControl>();
  deviceMenu->setParticipatesInLayout(false);
  deviceMenu->setVisible(false);
  deviceMenu->setMaxVisible(10);
  deviceMenu->setMenuWidth(280.0f * scale);
  deviceMenu->setOnActivate([this](const ContextMenuControlEntry& entry) {
    if (m_audio == nullptr) {
      return;
    }
    const auto id = static_cast<std::uint32_t>(std::max<std::int32_t>(0, entry.id));
    if (m_deviceMenuIsOutput) {
      m_audio->setDefaultSink(id);
    } else {
      m_audio->setDefaultSource(id);
    }
    m_deviceMenuOpen = false;
    PanelManager::instance().refresh();
  });
  deviceMenu->setRedrawCallback([]() { PanelManager::instance().requestRedraw(); });
  deviceMenu->setZIndex(20);
  m_deviceMenu = static_cast<ContextMenuControl*>(tab->addChild(std::move(deviceMenu)));

  return tab;
}

void AudioTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }

  syncValueLabelWidths(renderer);
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  if (m_outputDeviceLabel != nullptr && m_outputVolumeCard != nullptr) {
    m_outputDeviceLabel->setMaxWidth(std::max(0.0f, m_outputVolumeCard->width() - m_outputVolumeCard->paddingLeft() -
                                                        m_outputVolumeCard->paddingRight()));
  }
  if (m_inputDeviceLabel != nullptr && m_inputVolumeCard != nullptr) {
    m_inputDeviceLabel->setMaxWidth(std::max(0.0f, m_inputVolumeCard->width() - m_inputVolumeCard->paddingLeft() -
                                                       m_inputVolumeCard->paddingRight()));
  }
  m_rootLayout->layout(renderer);

  rebuildProgramVolumes(renderer);

  if (m_deviceMenuDismissCatcher != nullptr) {
    m_deviceMenuDismissCatcher->setVisible(m_deviceMenuOpen);
    if (m_deviceMenuOpen && m_rootLayout != nullptr) {
      m_deviceMenuDismissCatcher->setPosition(0.0f, 0.0f);
      m_deviceMenuDismissCatcher->setFrameSize(m_rootLayout->width(), m_rootLayout->height());
    }
  }

  if (m_deviceMenu != nullptr && m_rootLayout != nullptr) {
    if (m_deviceMenuOpen) {
      const float scale = contentScale();
      Flex* anchor = m_deviceMenuIsOutput ? m_outputDeviceMenuAnchor : m_inputDeviceMenuAnchor;
      if (anchor != nullptr) {
        const float menuWidth = std::min(280.0f * scale, m_rootLayout->width());
        m_deviceMenu->setMenuWidth(menuWidth);
        m_deviceMenu->setVisible(true);
        m_deviceMenu->setSize(menuWidth, m_deviceMenu->preferredHeight());

        float anchorAbsX = 0.0f;
        float anchorAbsY = 0.0f;
        float rootAbsX = 0.0f;
        float rootAbsY = 0.0f;
        Node::absolutePosition(anchor, anchorAbsX, anchorAbsY);
        Node::absolutePosition(m_rootLayout, rootAbsX, rootAbsY);
        const float localAnchorX = anchorAbsX - rootAbsX;
        const float localAnchorY = anchorAbsY - rootAbsY;
        const float x = localAnchorX + std::max(0.0f, anchor->width() - menuWidth);
        const float y = localAnchorY + anchor->height() + Style::spaceXs * scale;
        m_deviceMenu->setPosition(x, y);
        m_deviceMenu->layout(renderer);
      }
    } else {
      m_deviceMenu->setVisible(false);
    }
  }
}

void AudioTab::doUpdate(Renderer& renderer) {
  rebuildProgramVolumes(renderer);
  syncValueLabelWidths(renderer);

  if (m_deviceMenu != nullptr && m_audio != nullptr) {
    const AudioState& state = m_audio->state();
    const auto buildEntries = [&](bool isOutput) {
      std::vector<ContextMenuControlEntry> entries;
      const std::vector<AudioNode>& devices = isOutput ? state.sinks : state.sources;
      entries.reserve(devices.size());
      if (isOutput) {
        for (const auto& node : devices) {
          const bool selected = node.id == state.defaultSinkId;
          const std::string label = (selected ? "• " : "") + (!node.description.empty() ? node.description : node.name);
          entries.push_back(ContextMenuControlEntry{.id = static_cast<std::int32_t>(node.id),
                                                    .label = label,
                                                    .enabled = true,
                                                    .separator = false,
                                                    .hasSubmenu = false});
        }
      } else {
        for (const auto& node : devices) {
          const bool selected = node.id == state.defaultSourceId;
          const std::string label = (selected ? "• " : "") + (!node.description.empty() ? node.description : node.name);
          entries.push_back(ContextMenuControlEntry{.id = static_cast<std::int32_t>(node.id),
                                                    .label = label,
                                                    .enabled = true,
                                                    .separator = false,
                                                    .hasSubmenu = false});
        }
      }
      return entries;
    };

    m_deviceMenu->setEntries(buildEntries(m_deviceMenuIsOutput));

    if (m_outputDeviceMenuButton != nullptr) {
      const bool hasOutputs = !state.sinks.empty();
      m_outputDeviceMenuButton->setEnabled(hasOutputs);
      m_outputDeviceMenuButton->setVariant(hasOutputs ? ButtonVariant::Ghost : ButtonVariant::Default);
    }
    if (m_inputDeviceMenuButton != nullptr) {
      const bool hasInputs = !state.sources.empty();
      m_inputDeviceMenuButton->setEnabled(hasInputs);
      m_inputDeviceMenuButton->setVariant(hasInputs ? ButtonVariant::Ghost : ButtonVariant::Default);
    }
  }

  syncProgramVolumeRows();

  const float sliderMax = sliderMaxPercent() / 100.0f;
  if (m_outputSlider != nullptr) {
    m_syncingOutputSlider = true;
    m_outputSlider->setRange(0.0f, sliderMax);
    m_syncingOutputSlider = false;
  }
  if (m_inputSlider != nullptr) {
    m_syncingInputSlider = true;
    m_inputSlider->setRange(0.0f, sliderMax);
    m_syncingInputSlider = false;
  }

  const AudioNode* sink = m_audio != nullptr ? m_audio->defaultSink() : nullptr;
  const AudioNode* source = m_audio != nullptr ? m_audio->defaultSource() : nullptr;
  const auto now = std::chrono::steady_clock::now();
  const bool outputDragging = m_outputSlider != nullptr && m_outputSlider->dragging();
  const bool inputDragging = m_inputSlider != nullptr && m_inputSlider->dragging();

  if (m_outputDeviceLabel != nullptr) {
    m_outputDeviceLabel->setText(sink != nullptr ? (!sink->description.empty() ? sink->description : sink->name)
                                                 : i18n::tr("control-center.audio.no-output-selected"));
  }
  if (m_inputDeviceLabel != nullptr) {
    m_inputDeviceLabel->setText(source != nullptr ? (!source->description.empty() ? source->description : source->name)
                                                  : i18n::tr("control-center.audio.no-input-selected"));
  }

  const float sinkVolume = sink != nullptr ? sink->volume : 0.0f;
  const float sourceVolume = source != nullptr ? source->volume : 0.0f;
  const bool showPendingSink = sink != nullptr && m_pendingSinkVolume >= 0.0f && m_pendingSinkId == sink->id;
  const bool showPendingSource = source != nullptr && m_pendingSourceVolume >= 0.0f && m_pendingSourceId == source->id;
  const bool holdSinkState = outputDragging && sink != nullptr && m_lastSentSinkVolume >= 0.0f &&
                             now < m_ignoreSinkStateUntil && std::abs(sink->volume - m_lastSentSinkVolume) > 0.02f;
  const bool holdSourceState = inputDragging && source != nullptr && m_lastSentSourceVolume >= 0.0f &&
                               now < m_ignoreSourceStateUntil &&
                               std::abs(source->volume - m_lastSentSourceVolume) > 0.02f;
  const float displayedSinkVolume = std::clamp(
      showPendingSink ? m_pendingSinkVolume : (holdSinkState ? m_lastSentSinkVolume : sinkVolume), 0.0f, sliderMax);
  const float displayedSourceVolume =
      std::clamp(showPendingSource ? m_pendingSourceVolume : (holdSourceState ? m_lastSentSourceVolume : sourceVolume),
                 0.0f, sliderMax);

  if (m_outputSlider != nullptr) {
    m_outputSlider->setEnabled(sink != nullptr);
    if (!m_outputSlider->dragging() && std::abs(displayedSinkVolume - m_lastSinkVolume) >= kVolumeSyncEpsilon) {
      m_syncingOutputSlider = true;
      m_outputSlider->setValue(displayedSinkVolume);
      m_syncingOutputSlider = false;
      if (m_outputValue != nullptr) {
        m_outputValue->setText(std::to_string(static_cast<int>(std::round(displayedSinkVolume * 100.0f))) + "%");
      }
      m_lastSinkVolume = displayedSinkVolume;
    }
  }
  if (m_outputMuteButton != nullptr) {
    m_outputMuteButton->setEnabled(sink != nullptr);
    m_outputMuteButton->setGlyph((sink != nullptr && sink->muted) ? "volume-mute" : "volume-high");
  }

  if (m_inputSlider != nullptr) {
    m_inputSlider->setEnabled(source != nullptr);
    if (!m_inputSlider->dragging() && std::abs(displayedSourceVolume - m_lastSourceVolume) >= kVolumeSyncEpsilon) {
      m_syncingInputSlider = true;
      m_inputSlider->setValue(displayedSourceVolume);
      m_syncingInputSlider = false;
      if (m_inputValue != nullptr) {
        m_inputValue->setText(std::to_string(static_cast<int>(std::round(displayedSourceVolume * 100.0f))) + "%");
      }
      m_lastSourceVolume = displayedSourceVolume;
    }
  }
  if (m_inputMuteButton != nullptr) {
    m_inputMuteButton->setEnabled(source != nullptr);
    m_inputMuteButton->setGlyph((source != nullptr && source->muted) ? "microphone-mute" : "microphone");
  }
}

void AudioTab::onClose() {
  flushPendingVolumes(true);
  flushPendingProgramVolumes(true);
  m_sinkVolumeDebounceTimer.stop();
  m_sourceVolumeDebounceTimer.stop();
  m_programSinkDebounceTimer.stop();
  m_rootLayout = nullptr;
  m_deviceColumn = nullptr;
  m_outputCard = nullptr;
  m_inputCard = nullptr;
  m_outputScroll = nullptr;
  m_inputScroll = nullptr;
  m_outputList = nullptr;
  m_inputList = nullptr;
  m_volumeColumn = nullptr;
  m_outputVolumeCard = nullptr;
  m_inputVolumeCard = nullptr;
  m_outputDeviceLabel = nullptr;
  m_inputDeviceLabel = nullptr;
  m_outputSlider = nullptr;
  m_outputValue = nullptr;
  m_outputMuteButton = nullptr;
  m_inputSlider = nullptr;
  m_inputValue = nullptr;
  m_inputMuteButton = nullptr;
  m_lastOutputWidth = -1.0f;
  m_lastInputWidth = -1.0f;
  m_lastOutputListKey.clear();
  m_lastInputListKey.clear();
  m_programCard = nullptr;
  m_programScroll = nullptr;
  m_programList = nullptr;
  m_programRows.clear();
  m_lastProgramListKey.clear();
  m_lastProgramSliderMax = -1.0f;
  m_outputDeviceMenuAnchor = nullptr;
  m_inputDeviceMenuAnchor = nullptr;
  m_outputDeviceMenuButton = nullptr;
  m_inputDeviceMenuButton = nullptr;
  m_deviceMenu = nullptr;
  m_deviceMenuDismissCatcher = nullptr;
  m_deviceMenuOpen = false;
  m_pendingSinkId = 0;
  m_pendingSourceId = 0;
  m_lastSinkVolume = -1.0f;
  m_lastSourceVolume = -1.0f;
  m_pendingSinkVolume = -1.0f;
  m_pendingSourceVolume = -1.0f;
  m_pendingProgramSinkId = 0;
  m_pendingProgramSinkVolume = -1.0f;
  m_lastSentSinkVolume = -1.0f;
  m_lastSentSourceVolume = -1.0f;
  m_lastSinkCommitAt = {};
  m_lastSourceCommitAt = {};
  m_ignoreSinkStateUntil = {};
  m_ignoreSourceStateUntil = {};
}

void AudioTab::rebuildProgramVolumes(Renderer& renderer) {
  uiAssertNotRendering("AudioTab::rebuildProgramVolumes");
  if (m_programList == nullptr) {
    return;
  }

  const float scale = contentScale();
  const float sliderMax = sliderMaxPercent() / 100.0f;
  const float sliderMaxAbs = std::abs(sliderMax - m_lastProgramSliderMax);
  const std::vector<MprisPlayerInfo> players = allMprisPlayers(m_mpris);

  auto identityKey = [&players](const std::vector<AudioNode>& devices) -> std::string {
    std::string key;
    const auto sorted = sortedDevices(devices);
    for (const auto& node : sorted) {
      const MprisPlayerInfo* player = findMatchingPlayer(players, node, node.applicationName);
      std::string resolvedAppName = resolveProgramAppName(node, player);
      key += std::to_string(node.id);
      key.push_back(':');
      key += !node.description.empty() ? node.description : node.name;
      if (player != nullptr) {
        key.push_back(':');
        key += player->busName;
        key.push_back(':');
        key += player->title;
        key.push_back(':');
        key += joinedArtists(player->artists);
      }
      key.push_back('\n');
    }
    return key;
  };

  const std::string nextKey =
      (m_audio != nullptr ? identityKey(m_audio->state().programOutputs) : std::string{"unavailable_program_outputs"});

  if (m_audio != nullptr && nextKey == m_lastProgramListKey && sliderMaxAbs < 0.0001f) {
    return;
  }

  while (!m_programList->children().empty()) {
    m_programList->removeChild(m_programList->children().front().get());
  }
  m_programRows.clear();

  if (m_audio == nullptr) {
    addEmptyState(*m_programList, i18n::tr("control-center.audio.unavailable-title"),
                  i18n::tr("control-center.audio.unavailable-body"), scale);
    m_lastProgramListKey = nextKey;
    m_lastProgramSliderMax = sliderMax;
    return;
  }

  const AudioState& state = m_audio->state();

  if (state.programOutputs.empty()) {
    addEmptyState(*m_programList, i18n::tr("control-center.audio.no-application-audio"),
                  i18n::tr("control-center.audio.no-application-audio-body"), scale);
  } else {
    for (const auto& sink : sortedDevices(state.programOutputs)) {
      const MprisPlayerInfo* player = findMatchingPlayer(players, sink, sink.applicationName);
      auto row = std::make_unique<ProgramVolumeRow>(
          m_audio, sink.id, sliderMax, scale,
          [this, sinkId = sink.id](float value) { queueProgramSinkVolume(sinkId, value); },
          [this]() { flushPendingProgramVolumes(true); });
      row->syncFromNode(sink, player, false, sliderMax, true);
      m_programRows.push_back(row.get());
      m_programList->addChild(std::move(row));
    }
  }

  m_programList->layout(renderer);
  m_lastProgramListKey = nextKey;
  m_lastProgramSliderMax = sliderMax;
}

void AudioTab::syncProgramVolumeRows() {
  if (m_audio == nullptr || m_programRows.empty()) {
    return;
  }

  const AudioState& state = m_audio->state();
  const float sliderMax = sliderMaxPercent() / 100.0f;
  const std::vector<MprisPlayerInfo> players = allMprisPlayers(m_mpris);

  std::unordered_map<std::uint32_t, const AudioNode*> outputsById;
  outputsById.reserve(state.programOutputs.size());
  for (const auto& s : state.programOutputs) {
    outputsById.emplace(s.id, &s);
  }

  for (Flex* node : m_programRows) {
    auto* row = static_cast<ProgramVolumeRow*>(node);
    if (row == nullptr) {
      continue;
    }
    const auto it = outputsById.find(row->id());
    if (it == outputsById.end()) {
      continue;
    }
    const MprisPlayerInfo* player = findMatchingPlayer(players, *it->second, it->second->applicationName);
    row->syncFromNode(*it->second, player, false, sliderMax, true);
  }
}

void AudioTab::queueProgramSinkVolume(std::uint32_t id, float value) {
  if (m_audio == nullptr || id == 0) {
    return;
  }

  const float sliderMax = sliderMaxPercent() / 100.0f;
  m_pendingProgramSinkId = id;
  m_pendingProgramSinkVolume = std::clamp(value, 0.0f, sliderMax);

  m_programSinkDebounceTimer.stop();
  m_programSinkDebounceTimer.start(kVolumeCommitInterval, [this]() { flushPendingProgramVolumes(false); });
}

void AudioTab::flushPendingProgramVolumes(bool) {
  if (m_audio == nullptr) {
    m_programSinkDebounceTimer.stop();
    m_pendingProgramSinkId = 0;
    m_pendingProgramSinkVolume = -1.0f;
    return;
  }

  const float sliderMax = sliderMaxPercent() / 100.0f;

  if (m_pendingProgramSinkVolume >= 0.0f && m_pendingProgramSinkId != 0) {
    const auto sinkId = m_pendingProgramSinkId;
    const float volume = std::clamp(m_pendingProgramSinkVolume, 0.0f, sliderMax);
    m_audio->setProgramOutputVolume(sinkId, volume);
  }
  m_programSinkDebounceTimer.stop();
  m_pendingProgramSinkId = 0;
  m_pendingProgramSinkVolume = -1.0f;
}

void AudioTab::rebuildLists(Renderer& renderer) {
  uiAssertNotRendering("AudioTab::rebuildLists");
  if (m_outputList == nullptr || m_inputList == nullptr || m_outputScroll == nullptr || m_inputScroll == nullptr) {
    return;
  }

  const float outputWidth = m_outputScroll->contentViewportWidth();
  const float inputWidth = m_inputScroll->contentViewportWidth();

  if (outputWidth <= 0.0f || inputWidth <= 0.0f) {
    return;
  }

  const float scale = contentScale();
  if (m_audio == nullptr) {
    if (outputWidth == m_lastOutputWidth && inputWidth == m_lastInputWidth && m_lastOutputListKey == "unavailable" &&
        m_lastInputListKey == "unavailable") {
      return;
    }
    while (!m_outputList->children().empty()) {
      m_outputList->removeChild(m_outputList->children().front().get());
    }
    while (!m_inputList->children().empty()) {
      m_inputList->removeChild(m_inputList->children().front().get());
    }
    addEmptyState(*m_outputList, i18n::tr("control-center.audio.unavailable-title"),
                  i18n::tr("control-center.audio.unavailable-body"), scale);
    addEmptyState(*m_inputList, i18n::tr("control-center.audio.unavailable-title"),
                  i18n::tr("control-center.audio.unavailable-body"), scale);
    m_lastOutputWidth = outputWidth;
    m_lastInputWidth = inputWidth;
    m_lastOutputListKey = "unavailable";
    m_lastInputListKey = "unavailable";
    return;
  }

  const AudioState& state = m_audio->state();
  const std::string nextOutputListKey = state.sinks.empty() ? "empty" : deviceListKey(state.sinks);
  const std::string nextInputListKey = state.sources.empty() ? "empty" : deviceListKey(state.sources);

  if (outputWidth == m_lastOutputWidth && inputWidth == m_lastInputWidth && nextOutputListKey == m_lastOutputListKey &&
      nextInputListKey == m_lastInputListKey) {
    return;
  }

  while (!m_outputList->children().empty()) {
    m_outputList->removeChild(m_outputList->children().front().get());
  }
  while (!m_inputList->children().empty()) {
    m_inputList->removeChild(m_inputList->children().front().get());
  }

  if (state.sinks.empty()) {
    addEmptyState(*m_outputList, i18n::tr("control-center.audio.no-output-devices"),
                  i18n::tr("control-center.audio.no-output-devices-body"), scale);
  } else {
    for (const auto& sink : sortedDevices(state.sinks)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = sink.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSink(id);
        }
        PanelManager::instance().refresh();
      });
      row->setDevice(sink);
      m_outputList->addChild(std::move(row));
    }
  }

  if (state.sources.empty()) {
    addEmptyState(*m_inputList, i18n::tr("control-center.audio.no-input-devices"),
                  i18n::tr("control-center.audio.no-input-devices-body"), scale);
  } else {
    for (const auto& source : sortedDevices(state.sources)) {
      auto row = std::make_unique<AudioDeviceRow>([this, id = source.id]() {
        if (m_audio != nullptr) {
          m_audio->setDefaultSource(id);
        }
        PanelManager::instance().refresh();
      });
      row->setDevice(source);
      m_inputList->addChild(std::move(row));
    }
  }

  m_outputList->layout(renderer);
  m_inputList->layout(renderer);

  m_lastOutputWidth = outputWidth;
  m_lastInputWidth = inputWidth;
  m_lastOutputListKey = nextOutputListKey;
  m_lastInputListKey = nextInputListKey;
}

void AudioTab::syncValueLabelWidths(Renderer& renderer) {
  const std::string sampleLabel = widestPercentLabel(sliderMaxPercent());
  const TextMetrics metrics = renderer.measureText(sampleLabel, Style::fontSizeBody * contentScale(), true);
  const float minWidth = std::round(metrics.width);
  if (m_outputValue != nullptr) {
    m_outputValue->setMinWidth(minWidth);
  }
  if (m_inputValue != nullptr) {
    m_inputValue->setMinWidth(minWidth);
  }
}

float AudioTab::sliderMaxPercent() const {
  return (m_config != nullptr && m_config->config().audio.enableOverdrive) ? 150.0f : 100.0f;
}

void AudioTab::queueSinkVolume(float value) {
  const AudioNode* sink = m_audio != nullptr ? m_audio->defaultSink() : nullptr;
  m_pendingSinkId = sink != nullptr ? sink->id : 0;
  m_pendingSinkVolume = std::clamp(value, 0.0f, sliderMaxPercent() / 100.0f);
}

void AudioTab::queueSourceVolume(float value) {
  const AudioNode* source = m_audio != nullptr ? m_audio->defaultSource() : nullptr;
  m_pendingSourceId = source != nullptr ? source->id : 0;
  m_pendingSourceVolume = std::clamp(value, 0.0f, sliderMaxPercent() / 100.0f);
}

void AudioTab::flushPendingVolumes(bool force) {
  if (m_audio == nullptr) {
    m_sinkVolumeDebounceTimer.stop();
    m_sourceVolumeDebounceTimer.stop();
    m_pendingSinkId = 0;
    m_pendingSourceId = 0;
    m_pendingSinkVolume = -1.0f;
    m_pendingSourceVolume = -1.0f;
    return;
  }

  const float sliderMax = sliderMaxPercent() / 100.0f;
  const bool outputDragging = m_outputSlider != nullptr && m_outputSlider->dragging();
  const bool inputDragging = m_inputSlider != nullptr && m_inputSlider->dragging();
  const auto now = std::chrono::steady_clock::now();

  if (m_pendingSinkVolume >= 0.0f) {
    m_pendingSinkVolume = std::clamp(m_pendingSinkVolume, 0.0f, sliderMax);
  }
  if (m_pendingSourceVolume >= 0.0f) {
    m_pendingSourceVolume = std::clamp(m_pendingSourceVolume, 0.0f, sliderMax);
  }

  if (m_pendingSinkVolume >= 0.0f) {
    const std::uint32_t sinkId = m_pendingSinkId;
    bool shouldSendSink = force;
    if (!shouldSendSink && sinkId != 0) {
      const float delta = std::abs(m_pendingSinkVolume - m_lastSentSinkVolume);
      shouldSendSink = delta >= 0.0001f;
    }
    if (shouldSendSink && !force && outputDragging) {
      const auto nextSendAt = m_lastSinkCommitAt + kVolumeCommitInterval;
      if (now < nextSendAt) {
        m_sinkVolumeDebounceTimer.start(std::chrono::duration_cast<std::chrono::milliseconds>(nextSendAt - now),
                                        [this]() { flushPendingVolumes(); });
        shouldSendSink = false;
      }
    }
    if (sinkId != 0 && shouldSendSink) {
      m_audio->setSinkVolume(sinkId, m_pendingSinkVolume);
      m_audio->emitVolumePreview(false, sinkId, m_pendingSinkVolume);
      m_lastSentSinkVolume = m_pendingSinkVolume;
      m_lastSinkCommitAt = std::chrono::steady_clock::now();
      m_ignoreSinkStateUntil = m_lastSinkCommitAt + kVolumeStateHoldoff;
    }
    if (force || !outputDragging) {
      m_pendingSinkId = 0;
      m_pendingSinkVolume = -1.0f;
      m_sinkVolumeDebounceTimer.stop();
    }
  }

  if (m_pendingSourceVolume >= 0.0f) {
    const std::uint32_t sourceId = m_pendingSourceId;
    bool shouldSendSource = force;
    if (!shouldSendSource && sourceId != 0) {
      const float delta = std::abs(m_pendingSourceVolume - m_lastSentSourceVolume);
      shouldSendSource = delta >= 0.0001f;
    }
    if (shouldSendSource && !force && inputDragging) {
      const auto nextSendAt = m_lastSourceCommitAt + kVolumeCommitInterval;
      if (now < nextSendAt) {
        m_sourceVolumeDebounceTimer.start(std::chrono::duration_cast<std::chrono::milliseconds>(nextSendAt - now),
                                          [this]() { flushPendingVolumes(); });
        shouldSendSource = false;
      }
    }
    if (sourceId != 0 && shouldSendSource) {
      m_audio->setSourceVolume(sourceId, m_pendingSourceVolume);
      m_audio->emitVolumePreview(true, sourceId, m_pendingSourceVolume);
      m_lastSentSourceVolume = m_pendingSourceVolume;
      m_lastSourceCommitAt = std::chrono::steady_clock::now();
      m_ignoreSourceStateUntil = m_lastSourceCommitAt + kVolumeStateHoldoff;
    }
    if (force || !inputDragging) {
      m_pendingSourceId = 0;
      m_pendingSourceVolume = -1.0f;
      m_sourceVolumeDebounceTimer.stop();
    }
  }
}
