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
  property var availableLanguages: []
  property var translations: ({})
  property var fallbackTranslations: ({})

  // Signals for reactive updates
  signal languageChanged(string newLanguage)
  signal translationsLoaded

  // Process to list directory contents
  property Process directoryScanner: Process {
    id: directoryProcess
    command: ["ls", `${Quickshell.shellDir}/Assets/Translations/`]
    running: false

    stdout: StdioCollector {
      id: stdoutCollector
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        var output = stdoutCollector.text || "";
        parseDirectoryListing(output);
      } else {
        Logger.e("I18n", `Failed to scan translation directory`);
        // Fallback to default languages
        availableLanguages = ["en"];
        detectLanguage();
      }
    }
  }

  // FileView to load translation files
  property FileView translationFile: FileView {
    id: fileView
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text());
        root.translations = data;
        Logger.i("I18n", `Loaded translations for "${root.langCode}"`);
        Logger.d("I18n", `Available root keys: ${Object.keys(data).join(", ")}`);

        root.isLoaded = true;
        root.translationsLoaded();
      } catch (e) {
        Logger.e("I18n", `Failed to parse translation file: ${e}`);
        setLanguage("en");
      }
    }
    onLoadFailed: function (error) {
      setLanguage("en");
      Logger.e("I18n", `Failed to load translation file: ${error}`);
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

  Component.onCompleted: {
    Logger.i("I18n", "Service started");
    scanAvailableLanguages();
  }

  // -------------------------------------------
  function scanAvailableLanguages() {
    Logger.d("I18n", "Scanning for available translation files...");
    directoryScanner.running = true;
  }

  // -------------------------------------------
  function parseDirectoryListing(output) {
    var languages = [];

    try {
      if (!output || output.trim() === "") {
        Logger.w("I18n", "Empty directory listing output");
        availableLanguages = ["en"];
        detectLanguage();
        return;
      }

      const entries = output.trim().split('\n');

      for (var i = 0; i < entries.length; i++) {
        const entry = entries[i].trim();
        if (entry && entry.endsWith('.json')) {
          // Extract language code from filename (e.g., "en.json" -> "en")
          const langCode = entry.substring(0, entry.lastIndexOf('.json'));
          if (langCode.length >= 2 && langCode.length <= 5) {
            // Basic validation for language codes
            languages.push(langCode);
          }
        }
      }

      // Sort languages alphabetically, but ensure "en" comes first if available
      languages.sort();
      const enIndex = languages.indexOf("en");
      if (enIndex > 0) {
        languages.splice(enIndex, 1);
        languages.unshift("en");
      }

      if (languages.length === 0) {
        Logger.w("I18n", "No translation files found, using fallback");
        languages = ["en"]; // Fallback
      }

      availableLanguages = languages;
      Logger.d("I18n", `Found ${languages.length} available languages: ${languages.join(', ')}`);

      // Detect language after scanning
      detectLanguage();
    } catch (e) {
      Logger.e("I18n", `Failed to parse directory listing: ${e}`);
      // Fallback to default languages
      availableLanguages = ["en"];
      detectLanguage();
    }
  }

  // -------------------------------------------
  function detectLanguage() {
    Logger.d("I18n", `detectLanguage() called. Available languages: [${availableLanguages.join(', ')}]`);

    if (availableLanguages.length === 0) {
      Logger.w("I18n", "No available languages found");
      return;
    }

    var detectedLang = "";
    var detectedFullLocale = "";

    // First, determine the system's preferred language
    for (var i = 0; i < Qt.locale().uiLanguages.length; i++) {
      const fullUserLang = Qt.locale().uiLanguages[i];

      if (availableLanguages.includes(fullUserLang)) {
        detectedLang = fullUserLang;
        detectedFullLocale = fullUserLang;
        break;
      }

      const shortUserLang = fullUserLang.substring(0, 2);
      if (availableLanguages.includes(shortUserLang)) {
        detectedLang = shortUserLang;
        detectedFullLocale = fullUserLang;
        break;
      }
    }

    // If no system language is found among available languages, fallback
    if (detectedLang === "") {
      detectedLang = availableLanguages.includes("en") ? "en" : availableLanguages[0];
      detectedFullLocale = detectedLang;
    }

    root.systemDetectedLangCode = detectedLang;
    root.fullLocaleCode = detectedFullLocale;
    Logger.d("I18n", `System detected language: "${root.systemDetectedLangCode}" (full locale: "${root.fullLocaleCode}")`);

    // Now, apply the language: user-defined, then system-detected
    if (Settings.data.general.language !== "" && availableLanguages.includes(Settings.data.general.language)) {
      Logger.d("I18n", `User-defined language found: "${Settings.data.general.language}"`);
      setLanguage(Settings.data.general.language);
    } else {
      Logger.d("I18n", `No user-defined language, using system detected: "${root.systemDetectedLangCode}"`);
      setLanguage(root.systemDetectedLangCode, root.fullLocaleCode);
    }
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
    Logger.d("I18n", `Loading translations: ${langCode}`);

    // Only load fallback translations if we are not using english and english is available
    if (langCode !== "en" && availableLanguages.includes("en")) {
      fallbackFileView.path = `file://${Quickshell.shellDir}/Assets/Translations/en.json`;
    }
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
  function trp(key, count, defaultSingular, defaultPlural, interpolations) {
    if (typeof defaultSingular === "undefined")
      defaultSingular = "";
    if (typeof defaultPlural === "undefined")
      defaultPlural = "";
    if (typeof interpolations === "undefined")
      interpolations = {};

    const pluralKey = count === 1 ? key : `${key}-plural`;
    const defaultValue = count === 1 ? defaultSingular : defaultPlural;

    // Merge interpolations with count (QML doesn't support spread operator)
    var finalInterpolations = {
      "count": count
    };
    for (var prop in interpolations) {
      finalInterpolations[prop] = interpolations[prop];
    }

    return tr(pluralKey, finalInterpolations);
  }
}
