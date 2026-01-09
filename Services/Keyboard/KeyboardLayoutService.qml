pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Singleton {
  id: root
  property string currentLayout: I18n.tr("common.unknown")
  property string previousLayout: ""
  property bool isInitialized: false

  // Updates current layout from various format strings. Called by compositors
  function setCurrentLayout(layoutString) {
    root.currentLayout = extractLayoutCode(layoutString);
  }

  // Extract layout code from various format strings using Commons data
  function extractLayoutCode(layoutString) {
    if (!layoutString)
      return I18n.tr("common.unknown");

    const str = layoutString.toLowerCase();

    // If it's already a short code (2-3 chars), return as-is
    if (/^[a-z]{2,3}(\+.*)?$/.test(str)) {
      return str.split('+')[0];
    }

    // Extract from parentheses like "English (US)"
    const parenMatch = str.match(/\(([a-z]{2,3})\)/);
    if (parenMatch) {
      return parenMatch[1];
    }

    // Check for exact matches or partial matches in language map from Commons
    const entries = Object.entries(languageMap);
    for (var i = 0; i < entries.length; i++) {
      const lang = entries[i][0];
      const code = entries[i][1];
      if (str.includes(lang)) {
        return code;
      }
    }

    // If nothing matches, try first 2-3 characters if they look like a code
    const codeMatch = str.match(/^([a-z]{2,3})/);
    return codeMatch ? codeMatch[1] : I18n.tr("common.unknown");
  }

  // Watch for layout changes and show toast
  onCurrentLayoutChanged: {
    // Update previousLayout after checking for changes
    const layoutChanged = isInitialized && currentLayout !== previousLayout && currentLayout !== I18n.tr("common.unknown") && previousLayout !== "" && previousLayout !== I18n.tr("common.unknown");

    if (layoutChanged) {
      if (Settings.data.notifications.enableKeyboardLayoutToast) {
        const message = I18n.tr("toast.keyboard-layout.changed", {
                                  "layout": currentLayout.toUpperCase()
                                });
        ToastService.showNotice(I18n.tr("toast.keyboard-layout.title"), message, "", 2000);
      }
      Logger.d("KeyboardLayout", "Layout changed from", previousLayout, "to", currentLayout);
    }

    // Update previousLayout for next comparison
    previousLayout = currentLayout;
  }

  Component.onCompleted: {
    Logger.i("KeyboardLayout", "Service started");
    // Mark as initialized after a delay to allow first layout update to complete
    // This prevents showing a toast on the initial load
    initializationTimer.start();
  }

  Timer {
    id: initializationTimer
    interval: 2000 // Wait 2 seconds for first layout update to complete
    onTriggered: {
      isInitialized = true;
      // Set previousLayout to current value after initialization
      previousLayout = currentLayout;
      Logger.d("KeyboardLayout", "Service initialized, current layout:", currentLayout);
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
