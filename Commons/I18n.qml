pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property bool isLoaded: false
  property string langCode: ""
  property var locale: Qt.locale()
  property string systemDetectedLangCode: ""
  property string fullLocaleCode: "" // Preserves regional locale variants
  // Static list of available translations — update when adding/removing translation files
  property var availableLanguages: ["en", "de", "es", "fr", "hu", "ja", "ko-KR", "ku", "nl", "nn-HN", "nn-NO", "pl", "pt", "ru", "sv", "tr", "uk-UA", "zh-CN", "zh-TW"]
  property var translations: ({})
  property var fallbackTranslations: ({})

  // Signals for reactive updates
  signal languageChanged(string newLanguage)
  signal translationsLoaded

  // FileView to load translation files
  property FileView translationFile: FileView {
    id: fileView
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text());
        root.translations = data;
        Logger.i("I18n", `Loaded translations for "${root.langCode}"`);

        root.isLoaded = true;
        root.translationsLoaded();

        // Load English fallback for non-English languages (only after main file succeeds)
        if (root.langCode !== "en") {
          fallbackFileView.path = `file://${Quickshell.shellDir}/Assets/Translations/en.json`;
        }
      } catch (e) {
        Logger.e("I18n", `Failed to parse translation file: ${e}`);
        setLanguage("en");
      }
    }
    onLoadFailed: function (error) {
      if (root.langCode === "en") {
        Logger.e("I18n", `Failed to load English translation file: ${error}`);
        // English also failed - still emit signal to unblock startup
        root.isLoaded = true;
        root.translationsLoaded();
        return;
      }

      // Qt.callLater is needed because FileView doesn't re-trigger when path
      // is changed inside its own onLoadFailed handler
      var strippedCode = stripScript(root.langCode);
      if (strippedCode !== root.langCode) {
        Logger.d("I18n", `Translation file for "${root.langCode}" not found, trying "${strippedCode}"`);
        root.langCode = strippedCode;
        Qt.callLater(loadTranslations);
      } else {
        // Try language-only code (e.g. "zh-CN" → "zh")
        var shortCode = root.langCode.substring(0, 2);
        if (shortCode !== root.langCode) {
          Logger.d("I18n", `Translation file for "${root.langCode}" not found, trying "${shortCode}"`);
          root.langCode = shortCode;
          Qt.callLater(loadTranslations);
        } else {
          Logger.w("I18n", `Translation file for "${root.langCode}" not found, falling back to English`);
          root.langCode = "en";
          root.fullLocaleCode = "en";
          root.locale = Qt.locale("en");
          Qt.callLater(loadTranslations);
        }
      }
    }
  }

  // FileView to load fallback translation files
  property FileView fallbackTranslationFile: FileView {
    id: fallbackFileView
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text());
        root.fallbackTranslations = data;
        Logger.d("I18n", `Loaded english fallback translations`);
      } catch (e) {
        Logger.e("I18n", `Failed to parse fallback translation file: ${e}`);
      }
    }
    onLoadFailed: function (error) {
      Logger.e("I18n", `Failed to load fallback translation file: ${error}`);
    }
  }

  // Correct language when settings finish loading from disk (or user changes it)
  Connections {
    target: Settings.data.general
    function onLanguageChanged() {
      var userLang = Settings.data.general.language;
      if (userLang !== "" && userLang !== root.langCode && availableLanguages.includes(userLang)) {
        Logger.i("I18n", `Applying user language preference: "${userLang}"`);
        setLanguage(userLang);
      } else if (userLang === "" && root.systemDetectedLangCode !== "" && root.systemDetectedLangCode !== root.langCode) {
        Logger.i("I18n", `Language reset to default, reverting to system language: "${root.systemDetectedLangCode}"`);
        setLanguage(root.systemDetectedLangCode);
      }
    }
  }

  Component.onCompleted: {
    Logger.i("I18n", "Service started");

    var lang = determineFastLanguage();
    langCode = lang.code;
    fullLocaleCode = lang.fullLocale;
    locale = Qt.locale(lang.fullLocale);
    systemDetectedLangCode = lang.code;
    Logger.i("I18n", `Loading "${lang.code}" (locale: "${lang.fullLocale}")`);
    loadTranslations();
  }

  // Strip 4-letter script subtag from a BCP 47 tag (e.g. "fr-Latn-FR" → "fr-FR")
  function stripScript(tag) {
    var parts = tag.split("-");
    var result = [];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].length === 4 && /^[A-Za-z]{4}$/.test(parts[i])) {
        continue;
      }
      result.push(parts[i]);
    }
    return result.join("-");
  }

  // Determine the best language match against availableLanguages
  function determineFastLanguage() {
    // User preference from Settings (defaults to "" if not yet loaded from disk)
    var userLang = Settings.data.general.language;
    if (userLang !== "" && availableLanguages.includes(userLang)) {
      return {
        code: userLang,
        fullLocale: userLang
      };
    }

    // Match system locale against available translations
    for (var i = 0; i < Qt.locale().uiLanguages.length; i++) {
      var fullLang = Qt.locale().uiLanguages[i];

      // Exact match (e.g. "zh-CN")
      if (availableLanguages.includes(fullLang)) {
        return {
          code: fullLang,
          fullLocale: fullLang
        };
      }

      // Script-stripped match (e.g. "zh-Hans-CN" → "zh-CN")
      var stripped = stripScript(fullLang);
      if (stripped !== fullLang && availableLanguages.includes(stripped)) {
        return {
          code: stripped,
          fullLocale: fullLang
        };
      }

      // Language-only match (e.g. "fr-FR" → "fr")
      var short_ = fullLang.substring(0, 2);
      if (availableLanguages.includes(short_)) {
        return {
          code: short_,
          fullLocale: fullLang
        };
      }
    }

    return {
      code: "en",
      fullLocale: "en"
    };
  }

  // -------------------------------------------
  function setLanguage(newLangCode, fullLocale) {
    if (typeof fullLocale === "undefined") {
      fullLocale = newLangCode;
    }

    if (newLangCode !== langCode && availableLanguages.includes(newLangCode)) {
      langCode = newLangCode;
      fullLocaleCode = fullLocale;
      locale = Qt.locale(fullLocale);
      Logger.i("I18n", `Language set to "${langCode}" with locale "${fullLocale}"`);
      languageChanged(langCode);
      loadTranslations();
    } else if (!availableLanguages.includes(newLangCode)) {
      Logger.w("I18n", `Language "${newLangCode}" is not available`);
    }
  }

  // -------------------------------------------
  function loadTranslations() {
    if (langCode === "")
      return;
    const filePath = `file://${Quickshell.shellDir}/Assets/Translations/${langCode}.json`;
    fileView.path = filePath;
    isLoaded = false;
  }

  // -------------------------------------------
  // Check if a translation exists
  function hasTranslation(key) {
    if (!isLoaded)
      return false;

    const keys = key.split(".");
    var value = translations;

    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]];
      } else {
        return false;
      }
    }

    return typeof value === "string";
  }

  // -------------------------------------------
  // Get all translation keys (useful for debugging)
  function getAllKeys(obj, prefix) {
    if (typeof obj === "undefined")
      obj = translations;
    if (typeof prefix === "undefined")
      prefix = "";

    var keys = [];
    for (var key in (obj || {})) {
      const value = obj[key];
      const fullKey = prefix ? `${prefix}.${key}` : key;
      if (typeof value === "object" && value !== null) {
        keys = keys.concat(getAllKeys(value, fullKey));
      } else if (typeof value === "string") {
        keys.push(fullKey);
      }
    }
    return keys;
  }

  // -------------------------------------------
  // Reload translations (useful for development)
  function reload() {
    Logger.d("I18n", "Reloading translations");
    loadTranslations();
  }

  // -------------------------------------------
  // Main translation function
  function tr(key, interpolations) {
    if (typeof interpolations === "undefined")
      interpolations = {};

    if (!isLoaded) {
      //Logger.d("I18n", "Translations not loaded yet")
      return key;
    }

    // Navigate nested keys (e.g., "menu.file.open")
    const keys = key.split(".");

    // Look-up translation in the active language
    var value = translations;
    var notFound = false;
    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]];
      } else {
        Logger.d("I18n", `Translation key "${key}" not found at part "${keys[i]}"`);
        Logger.d("I18n", `Available keys: ${Object.keys(value || {}).join(", ")}`);
        notFound = true;
        break;
      }
    }

    // Fallback to english if not found
    if (notFound && availableLanguages.includes("en") && langCode !== "en") {
      value = fallbackTranslations;
      for (var i = 0; i < keys.length; i++) {
        if (value && typeof value === "object" && keys[i] in value) {
          value = value[keys[i]];
        } else {
          // Indicate this key does not even exists in the english fallback
          return `!!${key}!!`;
        }
      }
    } else if (notFound) {
      // No fallback available
      return `!!${key}!!`;
    }

    if (typeof value !== "string") {
      Logger.d("I18n", `Translation key "${key}" is not a string`);
      return key;
    }

    // Handle interpolations (e.g., "Hello {name}!")
    var result = value;
    for (var placeholder in interpolations) {
      const regex = new RegExp(`\\{${placeholder}\\}`, 'g');
      result = result.replace(regex, interpolations[placeholder]);
    }

    return result;
  }

  // -------------------------------------------
  // Plural translation function
  function trp(key, count, interpolations) {
    if (typeof interpolations === "undefined") {
      interpolations = {};
    }

    // Use key for singular, key-plural for plural
    const realKey = count === 1 ? key : `${key}-plural`;

    // Merge interpolations with count
    var finalInterpolations = {
      "count": count
    };
    for (var prop in interpolations) {
      finalInterpolations[prop] = interpolations[prop];
    }

    return tr(realKey, finalInterpolations);
  }
}
