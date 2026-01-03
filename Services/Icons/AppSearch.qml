pragma Singleton
// Icon name guessing and resolution - Based on End4's AppSearch

import QtQuick
import Quickshell
import qs.Commons
import "../../Helpers/FuzzySort.js" as FuzzySort

Singleton {
    id: root
    property real scoreThreshold: 0.2
    
    Component.onCompleted: {
        Logger.i("AppSearch", "Singleton created/loaded")
    }
    
    // Normalization cache - stores recently normalized strings (LRU-style, max 50 entries)
    property var normalizeCache: ({})
    property int normalizeCacheMaxSize: 50
    property var normalizeCacheKeys: []  // Track insertion order for LRU eviction
    
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /minecraft.*/i,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Lazy-loaded list (computed on first access)
    function getList() {
        if (typeof DesktopEntries === 'undefined' || !DesktopEntries.applications) {
            return [];
        }
        var values = Array.from(DesktopEntries.applications.values);
        return values.filter(function(app, index, self) {
            return index === self.findIndex(function(t) {
                return t.id === app.id;
            });
        });
    }

    // Lazy-loaded prepped names
    function getPreppedNames() {
        var list = getList();
        return list.map(function(a) {
            return {
                name: FuzzySort.prepare(a.name + " "),
                entry: a
            };
        });
    }

    // Lazy-loaded prepped icons  
    function getPreppedIcons() {
        var list = getList();
        return list.map(function(a) {
            return {
                name: FuzzySort.prepare(a.icon + " "),
                entry: a
            };
        });
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        // Apply scoreThreshold to filter low-quality matches
        // fuzzysort's threshold option expects normalized score (0-1), which scoreThreshold already is
        var results = FuzzySort.go(search, getPreppedNames(), {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        });
        return results.filter(function(r) {
            // Double-check score threshold (results have normalized scores)
            return r.score >= root.scoreThreshold;
        }).map(function(r) {
            return r.obj.entry;
        });
    }

    // Fuzzy search with highlighted results for UI display
    // Returns results with text, highlightedText, and score
    // Parameters: search (string), highlightOpen (string, optional), highlightClose (string, optional)
    // Returns: Array of {entry, text, highlightedText, score} objects
    function fuzzyQueryWithHighlight(search: string, highlightOpen, highlightClose): var {
        if (!search || search.length === 0) return []
        
        // Use fuzzysort for proper highlighting
        var results = FuzzySort.go(search, getPreppedNames(), {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        });
        results = results.filter(function(r) {
            return r.score >= root.scoreThreshold;
        });
        
        var openTag = highlightOpen !== undefined ? highlightOpen : '<b>';
        var closeTag = highlightClose !== undefined ? highlightClose : '</b>';
        
        return results.map(function(r) {
            return {
                entry: r.obj.entry,
                text: r.obj.entry.name,
                highlightedText: r.highlight ? r.highlight(openTag, closeTag) : r.target || "",
                score: r.score
            };
        });
    }

    // Cleans and formats display names for consistent UI presentation
    // Handles common edge cases: .desktop suffix, dashes/underscores, extra whitespace
    // Parameter: name (string) - Raw name (e.g., "app-name.desktop", "App Name", "app_name", etc.)
    // Returns: Cleaned display name ready for UI display
    function cleanDisplayName(name) {
        if (!name || name.length === 0) return ""
        
        // Remove .desktop suffix if present
        var cleaned = name.replace(/\.desktop$/i, "")
        
        // Replace dashes/underscores with spaces for readability
        cleaned = cleaned.replace(/[-_]/g, " ")
        
        // Trim extra whitespace and normalize multiple spaces to single space
        cleaned = cleaned.trim().replace(/\s+/g, " ")
        
        return cleaned
    }

    // Normalizes a string and returns all variant forms
    // Caches results for performance (50 most recent entries)
    // Parameter: str (string) - The string to normalize
    // Returns: Object with normalized variants:
    //   - lowercase: lowercase version
    //   - reverseDomain: last part of domain (e.g., "com.app.name" -> "name")
    //   - reverseDomainLower: reverseDomain.toLowerCase()
    //   - kebab: spaces to dashes, lowercase
    //   - underscoreToKebab: underscores to dashes, lowercase
    function normalize(str) {
        if (!str || str.length === 0) {
            return {
                lowercase: "",
                reverseDomain: "",
                reverseDomainLower: "",
                kebab: "",
                underscoreToKebab: ""
            }
        }
        
        // Check cache first
        if (root.normalizeCache.hasOwnProperty(str)) {
            // Move to end (most recently used)
            var index = root.normalizeCacheKeys.indexOf(str)
            if (index !== -1) {
                root.normalizeCacheKeys.splice(index, 1)
                root.normalizeCacheKeys.push(str)
            }
            return root.normalizeCache[str]
        }
        
        // Compute all variants
        var lowercase = str.toLowerCase()
        var domainParts = str.split('.')
        var reverseDomain = domainParts.length > 0 ? domainParts[domainParts.length - 1] : str
        var reverseDomainLower = reverseDomain.toLowerCase()
        var kebab = lowercase.replace(/\s+/g, "-")
        var underscoreToKebab = lowercase.replace(/_/g, "-")
        
        var result = {
            lowercase: lowercase,
            reverseDomain: reverseDomain,
            reverseDomainLower: reverseDomainLower,
            kebab: kebab,
            underscoreToKebab: underscoreToKebab
        }
        
        // Cache the result (LRU eviction)
        root.normalizeCache[str] = result
        root.normalizeCacheKeys.push(str)
        
        // Evict oldest if cache is full
        if (root.normalizeCacheKeys.length > root.normalizeCacheMaxSize) {
            var oldest = root.normalizeCacheKeys.shift()
            delete root.normalizeCache[oldest]
        }
        
        return result
    }

    // Legacy functions for backward compatibility (now use normalize cache)
    function getReverseDomainNameAppName(str) {
        return normalize(str).reverseDomain
    }

    function getKebabNormalizedAppName(str) {
        return normalize(str).kebab
    }

    function getUndescoreToKebabAppName(str) {
        return normalize(str).underscoreToKebab
    }

    // Cache for resolved icon paths (LRU cache, max 200 entries)
    property var iconPathCache: ({})
    property var iconPathCacheKeys: []  // Track insertion order for LRU eviction
    property int iconPathCacheMaxSize: 200

    // Resolves an icon name to a file path asynchronously using IconResolver
    // Parameters: iconName (string) - The icon name (e.g., "com.mitchellh.ghostty")
    //             callback (function) - Function called with the resolved path (or empty string if not found)
    function resolveIconAsync(iconName, callback) {
        if (!iconName || iconName.length === 0) {
            if (typeof callback === "function") {
                callback("")
            }
            return
        }

        // If it's already a file path, return immediately
        if (iconName.startsWith("/")) {
            if (typeof callback === "function") {
                callback(iconName)
            }
            return
        }

        // Use IconResolver to resolve
        IconResolver.resolveIcon(iconName, function(resolvedPath) {
            // Cache the result with LRU eviction
            if (resolvedPath && resolvedPath.length > 0) {
                if (root.iconPathCache.hasOwnProperty(iconName)) {
                    root.iconPathCache[iconName] = resolvedPath
                    var index = root.iconPathCacheKeys.indexOf(iconName)
                    if (index !== -1) {
                        root.iconPathCacheKeys.splice(index, 1)
                        root.iconPathCacheKeys.push(iconName)
                    }
                } else {
                    root.iconPathCache[iconName] = resolvedPath
                    root.iconPathCacheKeys.push(iconName)
                    if (root.iconPathCacheKeys.length > root.iconPathCacheMaxSize) {
                        var oldest = root.iconPathCacheKeys.shift()
                        delete root.iconPathCache[oldest]
                    }
                }
            }
            
            if (typeof callback === "function") {
                callback(resolvedPath)
            }
        })
    }

    // Clears the icon path cache (called when IconResolver restarts)
    function clearIconCache() {
        root.iconPathCache = {};
        root.iconPathCacheKeys = [];
        Logger.d("AppSearch", "Icon path cache cleared");
    }
    
    // Resolves icon with ThemeIcons fallback (caches fallback results for performance)
    // Parameters: iconName (string) - The icon name
    //             callback (function) - Function called with the resolved path (or ThemeIcons fallback if not found)
    function resolveIconWithFallback(iconName, callback) {
        if (!iconName || iconName.length === 0) {
            Logger.w("AppSearch", "resolveIconWithFallback: empty iconName")
            if (typeof callback === "function") {
                callback("")
            }
            return
        }

        // Check cache first
        var cacheHit = root.iconPathCache.hasOwnProperty(iconName)
        if (cacheHit) {
            var cached = root.iconPathCache[iconName]
            if (cached && cached.length > 0) {
                Logger.d("AppSearch", "resolveIconWithFallback:", iconName, "→ CACHE HIT →", cached)
                if (typeof callback === "function") {
                    callback(cached)
                }
                return
            }
        }

        // Try IconResolver first
        resolveIconAsync(iconName, function(resolvedPath) {
            if (resolvedPath && resolvedPath.length > 0) {
                // IconResolver found it
                Logger.d("AppSearch", "resolveIconWithFallback:", iconName, "→ IconResolver →", resolvedPath)
                if (typeof callback === "function") {
                    callback(resolvedPath)
                }
            } else {
                // IconResolver didn't find it - try ThemeIcons fallback
                var fallbackPath = ThemeIcons.iconFromName(iconName, "application-x-executable");
                var finalPath = fallbackPath || "";
                
                // Cache the fallback result
                if (finalPath && finalPath.length > 0) {
                    if (root.iconPathCache.hasOwnProperty(iconName)) {
                        root.iconPathCache[iconName] = finalPath
                        var index = root.iconPathCacheKeys.indexOf(iconName)
                        if (index !== -1) {
                            root.iconPathCacheKeys.splice(index, 1)
                            root.iconPathCacheKeys.push(iconName)
                        }
                    } else {
                        root.iconPathCache[iconName] = finalPath
                        root.iconPathCacheKeys.push(iconName)
                        if (root.iconPathCacheKeys.length > root.iconPathCacheMaxSize) {
                            var oldest = root.iconPathCacheKeys.shift()
                            delete root.iconPathCache[oldest]
                        }
                    }
                }
                
                Logger.d("AppSearch", "resolveIconWithFallback:", iconName, "→ ThemeIcons fallback →", finalPath || "(empty)")
                if (typeof callback === "function") {
                    callback(finalPath)
                }
            }
        })
    }

    // Gets the cached icon path for an icon name (synchronous)
    // Returns the cached path if available, otherwise returns the icon name
    // Parameter: iconName (string) - The icon name
    // Returns: The cached path or icon name
    function getIconPath(iconName) {
        if (!iconName || iconName.length === 0) return ""
        
        // If it's already a file path, return as-is
        if (iconName.startsWith("/")) {
            return iconName
        }

        // Check cache and update LRU order
        if (root.iconPathCache.hasOwnProperty(iconName)) {
            // Move to end (most recently used)
            var index = root.iconPathCacheKeys.indexOf(iconName)
            if (index !== -1) {
                root.iconPathCacheKeys.splice(index, 1)
                root.iconPathCacheKeys.push(iconName)
            }
            return root.iconPathCache[iconName]
        }

        // Not cached yet, return icon name for fallback
        return iconName
    }

    // Guesses the best icon name for a given window class or app identifier
    // Returns icon names only - does NOT check file existence
    // All actual path resolution should go through IconResolver.resolveIcon()
    // Parameters: str (string) - Window class or app identifier
    // Returns: Best guess icon name (e.g., "com.mitchellh.ghostty", "zen-browser")
    function guessIcon(str) {
        Logger.d("AppSearch", "guessIcon called with:", str)
        if (!str || str.length == 0) return "image-missing";

        // 1. Canonical substitutions (app-specific mappings)
        if (substitutions[str]) {
            Logger.d("AppSearch", "Using substitution:", str, "→", substitutions[str])
            return substitutions[str];
        }
        if (substitutions[str.toLowerCase()]) {
            Logger.d("AppSearch", "Using substitution:", str, "→", substitutions[str.toLowerCase()])
            return substitutions[str.toLowerCase()];
        }

        // 2. Regex substitutions (pattern-based mappings)
        for (var i = 0; i < regexSubstitutions.length; i++) {
            var substitution = regexSubstitutions[i];
            var replacedName = str.replace(
                substitution.regex,
                substitution.replace
            );
            if (replacedName != str) {
                var result = replacedName;
                Logger.d("AppSearch", "guessIcon result:", str, "→", result)
                return result;
            }
        }

        // 3. Desktop entry lookup (metadata fallback)
        var entry = DesktopEntries.byId(str);
        if (entry && entry.icon) {
            var result = entry.icon;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }

        // 4. Try normalized variants (return best guess, let Rust resolver check existence)
        var normalized = normalize(str);
        
        // Try variants in order of likelihood
        if (normalized.reverseDomain && normalized.reverseDomain !== str) {
            var result = normalized.reverseDomain;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }
        
        if (normalized.reverseDomainLower && normalized.reverseDomainLower !== str) {
            var result = normalized.reverseDomainLower;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }
        
        if (normalized.lowercase && normalized.lowercase !== str) {
            var result = normalized.lowercase;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }
        
        if (normalized.kebab && normalized.kebab !== str) {
            var result = normalized.kebab;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }
        
        if (normalized.underscoreToKebab && normalized.underscoreToKebab !== str) {
            var result = normalized.underscoreToKebab;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }

        // 5. Fuzzy search in desktop entries (for icon names)
        var iconSearchResults = FuzzySort.go(str, getPreppedIcons(), {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        });
        iconSearchResults = iconSearchResults.filter(function(r) {
            return r.score >= root.scoreThreshold;
        });
        iconSearchResults = iconSearchResults.map(function(r) {
            return r.obj.entry;
        });
        if (iconSearchResults.length > 0) {
            var result = iconSearchResults[0].icon;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }

        // 6. Fuzzy search in app names (fallback to their icon)
        var nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            var result = nameSearchResults[0].icon;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }

        // 7. Heuristic desktop entry lookup
        var heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) {
            var result = heuristicEntry.icon;
            Logger.d("AppSearch", "guessIcon result:", str, "→", result)
            return result;
        }

        // 8. Return original string as fallback (let Rust resolver try variations)
        var result = str;
        Logger.d("AppSearch", "guessIcon result:", str, "→", result)
        return result;
    }
}
