pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor

Singleton {
  id: root
  property string currentLayout: I18n.tr("system.unknown-layout")
  property int updateInterval: 1000 // Update every second

  // Timer to periodically update the layout
  Timer {
    id: updateTimer
    interval: updateInterval
    running: true
    repeat: true
    onTriggered: {
      updateLayout()
    }
  }

  // Process to get current keyboard layout using niri msg (Wayland native)
  Process {
    id: niriLayoutProcess
    running: false
    command: ["niri", "msg", "-j", "keyboard-layouts"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          const layoutName = data.names[data.current_idx]
          root.currentLayout = extractLayoutCode(layoutName)
        } catch (e) {
          root.currentLayout = "Unknown"
        }
      }
    }
  }

  // Process to get current keyboard layout using hyprctl (Hyprland)
  Process {
    id: hyprlandLayoutProcess
    running: false
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          // Find the main keyboard and get its active keymap
          const mainKeyboard = data.keyboards.find(kb => kb.main === true)
          if (mainKeyboard && mainKeyboard.active_keymap) {
            root.currentLayout = extractLayoutCode(mainKeyboard.active_keymap)
          } else {
            root.currentLayout = "Unknown"
          }
        } catch (e) {
          root.currentLayout = "Unknown"
        }
      }
    }
  }

  // Process for X11 systems using setxkbmap
  Process {
    id: x11LayoutProcess
    running: false
    command: ["setxkbmap", "-query"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const lines = text.split('\n')
          for (const line of lines) {
            if (line.startsWith('layout:')) {
              const layout = line.split(':')[1].trim()
              root.currentLayout = layout
              return
            }
          }
          root.currentLayout = "Unknown"
        } catch (e) {
          root.currentLayout = "Unknown"
        }
      }
    }
  }

  // Process for general Wayland using localectl (systemd)
  Process {
    id: localectlProcess
    running: false
    command: ["localectl", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const lines = text.split('\n')
          for (const line of lines) {
            if (line.includes("X11 Layout:")) {
              const layout = line.split(':')[1].trim()
              if (layout && layout !== "n/a") {
                root.currentLayout = layout
                return
              }
            }
            if (line.includes("VC Keymap:")) {
              const keymap = line.split(':')[1].trim()
              if (keymap && keymap !== "n/a") {
                root.currentLayout = extractLayoutCode(keymap)
                return
              }
            }
          }
          root.currentLayout = "Unknown"
        } catch (e) {
          root.currentLayout = "Unknown"
        }
      }
    }
  }

  // Process for generic keyboard layout detection using gsettings (GNOME-based)
  Process {
    id: gsettingsProcess
    running: false
    command: ["gsettings", "get", "org.gnome.desktop.input-sources", "current"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const currentIndex = parseInt(text.trim())
          gsettingsSourcesProcess.running = true
        } catch (e) {
          fallbackToLocalectl()
        }
      }
    }
  }

  Process {
    id: gsettingsSourcesProcess
    running: false
    command: ["gsettings", "get", "org.gnome.desktop.input-sources", "sources"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          // Parse the sources array and extract layout codes
          const sourcesText = text.trim()
          const matches = sourcesText.match(/\('xkb', '([^']+)'\)/g)
          if (matches && matches.length > 0) {
            // Get the first layout as default
            const layoutMatch = matches[0].match(/\('xkb', '([^']+)'\)/)
            if (layoutMatch) {
              root.currentLayout = layoutMatch[1].split('+')[0] // Take first part before any variants
            }
          } else {
            fallbackToLocalectl()
          }
        } catch (e) {
          fallbackToLocalectl()
        }
      }
    }
  }

  function fallbackToLocalectl() {
    localectlProcess.running = true
  }

  // Extract layout code from various format strings using Commons data
  function extractLayoutCode(layoutString) {
    if (!layoutString)
      return "Unknown"

    const str = layoutString.toLowerCase()

    // If it's already a short code (2-3 chars), return as-is
    if (/^[a-z]{2,3}(\+.*)?$/.test(str)) {
      return str.split('+')[0]
    }

    // Extract from parentheses like "English (US)"
    const parenMatch = str.match(/\(([a-z]{2,3})\)/)
    if (parenMatch) {
      return parenMatch[1]
    }

    // Check for exact matches or partial matches in language map from Commons
    const entries = Object.entries(languageMap)
    for (var i = 0; i < entries.length; i++) {
      const lang = entries[i][0]
      const code = entries[i][1]
      if (str.includes(lang)) {
        return code
      }
    }

    // If nothing matches, try first 2-3 characters if they look like a code
    const codeMatch = str.match(/^([a-z]{2,3})/)
    return codeMatch ? codeMatch[1] : "unknown"
  }

  Component.onCompleted: {
    Logger.i("KeyboardLayout", "Service started")
    updateLayout()
  }

  function updateLayout() {
    // Try compositor-specific methods first
    if (CompositorService.isHyprland) {
      hyprlandLayoutProcess.running = true
    } else if (CompositorService.isNiri) {
      niriLayoutProcess.running = true
    } else {
      // Try detection methods in order of preference
      if (Qt.platform.os === "linux") {
        // Check if we're in X11 or Wayland
        const sessionType = Qt.application.arguments.find(arg => arg.includes("QT_QPA_PLATFORM")) || process.env.XDG_SESSION_TYPE

        if (sessionType && sessionType.includes("xcb") || process.env.DISPLAY) {
          // X11 system
          x11LayoutProcess.running = true
        } else {
          // Wayland or unknown - try gsettings first, then localectl
          gsettingsProcess.running = true
        }
      } else {
        currentLayout = "Unknown"
      }
    }
  }

  // Comprehensive language name to ISO code mapping
  property var languageMap: {
    "english"// English variants
    : "us",
    "american": "us",
    "united states": "us",
    "us english": "us",
    "british": "gb",
    "uk": "ua",
    "united kingdom"// FIXED: Ukrainian language code should map to Ukraine
    : "gb",
    "english (uk)": "gb",
    "canadian": "ca",
    "canada": "ca",
    "canadian english": "ca",
    "australian": "au",
    "australia": "au",
    "swedish"// Nordic countries
    : "se",
    "svenska": "se",
    "sweden": "se",
    "norwegian": "no",
    "norsk": "no",
    "norway": "no",
    "danish": "dk",
    "dansk": "dk",
    "denmark": "dk",
    "finnish": "fi",
    "suomi": "fi",
    "finland": "fi",
    "icelandic": "is",
    "íslenska": "is",
    "iceland": "is",
    "german"// Western/Central European Germanic
    : "de",
    "deutsch": "de",
    "germany": "de",
    "austrian": "at",
    "austria": "at",
    "österreich": "at",
    "swiss": "ch",
    "switzerland": "ch",
    "schweiz": "ch",
    "suisse": "ch",
    "dutch": "nl",
    "nederlands": "nl",
    "netherlands": "nl",
    "holland": "nl",
    "belgian": "be",
    "belgium": "be",
    "belgië": "be",
    "belgique": "be",
    "french"// Romance languages (Western/Southern Europe)
    : "fr",
    "français": "fr",
    "france": "fr",
    "canadian french": "ca",
    "spanish": "es",
    "español": "es",
    "spain": "es",
    "castilian": "es",
    "italian": "it",
    "italiano": "it",
    "italy": "it",
    "portuguese": "pt",
    "português": "pt",
    "portugal": "pt",
    "catalan": "ad",
    "català": "ad",
    "andorra": "ad",
    "romanian"// Eastern European Romance
    : "ro",
    "română": "ro",
    "romania": "ro",
    "russian"// Slavic languages (Eastern Europe)
    : "ru",
    "русский": "ru",
    "russia": "ru",
    "polish": "pl",
    "polski": "pl",
    "poland": "pl",
    "czech": "cz",
    "čeština": "cz",
    "czech republic": "cz",
    "slovak": "sk",
    "slovenčina": "sk",
    "slovakia": "sk",
    "uk": "ua",
    "ukrainian"// Ukrainian language code
    : "ua",
    "українська": "ua",
    "ukraine": "ua",
    "bulgarian": "bg",
    "български": "bg",
    "bulgaria": "bg",
    "serbian": "rs",
    "srpski": "rs",
    "serbia": "rs",
    "croatian": "hr",
    "hrvatski": "hr",
    "croatia": "hr",
    "slovenian": "si",
    "slovenščina": "si",
    "slovenia": "si",
    "bosnian": "ba",
    "bosanski": "ba",
    "bosnia": "ba",
    "macedonian": "mk",
    "македонски": "mk",
    "macedonia": "mk",
    "irish"// Celtic languages (Western Europe)
    : "ie",
    "gaeilge": "ie",
    "ireland": "ie",
    "welsh": "gb",
    "cymraeg": "gb",
    "wales": "gb",
    "scottish": "gb",
    "gàidhlig": "gb",
    "scotland": "gb",
    "estonian"// Baltic languages (Northern Europe)
    : "ee",
    "eesti": "ee",
    "estonia": "ee",
    "latvian": "lv",
    "latviešu": "lv",
    "latvia": "lv",
    "lithuanian": "lt",
    "lietuvių": "lt",
    "lithuania": "lt",
    "hungarian"// Other European languages
    : "hu",
    "magyar": "hu",
    "hungary": "hu",
    "greek": "gr",
    "ελληνικά": "gr",
    "greece": "gr",
    "albanian": "al",
    "shqip": "al",
    "albania": "al",
    "maltese": "mt",
    "malti": "mt",
    "malta": "mt",
    "turkish"// West/Southwest Asian languages
    : "tr",
    "türkçe": "tr",
    "turkey": "tr",
    "arabic": "ar",
    "العربية": "ar",
    "arab": "ar",
    "hebrew": "il",
    "עברית": "il",
    "israel": "il",
    "brazilian"// South American languages
    : "br",
    "brazilian portuguese": "br",
    "brasil": "br",
    "brazil": "br",
    "japanese"// East Asian languages
    : "jp",
    "日本語": "jp",
    "japan": "jp",
    "korean": "kr",
    "한국어": "kr",
    "korea": "kr",
    "south korea": "kr",
    "chinese": "cn",
    "中文": "cn",
    "china": "cn",
    "simplified chinese": "cn",
    "traditional chinese": "tw",
    "taiwan": "tw",
    "繁體中文": "tw",
    "thai"// Southeast Asian languages
    : "th",
    "ไทย": "th",
    "thailand": "th",
    "vietnamese": "vn",
    "tiếng việt": "vn",
    "vietnam": "vn",
    "hindi"// South Asian languages
    : "in",
    "हिन्दी": "in",
    "india": "in",
    "afrikaans"// African languages
    : "za",
    "south africa": "za",
    "south african": "za",
    "qwerty"// Layout variants
    : "us",
    "dvorak": "us",
    "colemak": "us",
    "workman": "us",
    "azerty": "fr",
    "norman": "fr",
    "qwertz": "de"
  }
}
