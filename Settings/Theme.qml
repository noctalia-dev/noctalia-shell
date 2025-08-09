// Theme.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Settings

Singleton {
    id: root

    // Design reference resolution (for scale = 1.0)
    readonly property int designScreenWidth: 2560
    readonly property int designScreenHeight: 1440
    
    // Automatic, orientation-agnostic scaling
    function scale(currentScreen) {
        // 1) Per-monitor override wins
        try {
            const overrides = Settings.settings.monitorScaleOverrides || {};
            if (currentScreen && currentScreen.name && overrides[currentScreen.name] !== undefined) {
                const overrideValue = overrides[currentScreen.name]
                if (isFinite(overrideValue)) return overrideValue
            }
        } catch (e) {
            // ignore
        }

        // 2) Fallback: scale by diagonal pixel count relative to design resolution
        try {
            const w = Math.max(1, currentScreen ? (currentScreen.width || 0) : 0)
            const h = Math.max(1, currentScreen ? (currentScreen.height || 0) : 0)
            if (w > 1 && h > 1) {
                const diag = Math.sqrt(w * w + h * h)
                const baseDiag = Math.sqrt(designScreenWidth * designScreenWidth + designScreenHeight * designScreenHeight)
                const ratio = diag / baseDiag
                // Clamp to a reasonable range for UI legibility
                return Math.max(0.9, Math.min(1.6, ratio))
            }
        } catch (e) {
            // ignore and fall through
        }

        // 3) Safe default
        return 1.0
    }

    function applyOpacity(color, opacity) {
        return color.replace("#", "#" + opacity);
    }
    
    // FileView to load theme data from JSON file
    FileView {
        id: themeFile
        path: Settings.themeFile
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: function(error) {
            if (error.toString().includes("No such file") || error === 2) {
                // File doesn't exist, create it with default values
                writeAdapter()
            }
        }
        JsonAdapter {
            id: themeData
            
            // Backgrounds
            property string backgroundPrimary: "#0C0D11"
            property string backgroundSecondary: "#151720"
            property string backgroundTertiary: "#1D202B"
            
            // Surfaces & Elevation
            property string surface: "#1A1C26"
            property string surfaceVariant: "#2A2D3A"
            
            // Text Colors
            property string textPrimary: "#CACEE2"
            property string textSecondary: "#B7BBD0"
            property string textDisabled: "#6B718A"
            
            // Accent Colors
            property string accentPrimary: "#A8AEFF"
            property string accentSecondary: "#9EA0FF"
            property string accentTertiary: "#8EABFF"
            
            // Error/Warning
            property string error: "#FF6B81"
            property string warning: "#FFBB66"
            
            // Highlights & Focus
            property string highlight: "#E3C2FF"
            property string rippleEffect: "#F3DEFF"
            
            // Additional Theme Properties
            property string onAccent: "#1A1A1A"
            property string outline: "#44485A"
            
            // Shadows & Overlays
            property string shadow: "#000000"
            property string overlay: "#11121A"
        }
    }
    
    // Backgrounds
    property color backgroundPrimary: themeData.backgroundPrimary
    property color backgroundSecondary: themeData.backgroundSecondary
    property color backgroundTertiary: themeData.backgroundTertiary

    // Surfaces & Elevation
    property color surface: themeData.surface
    property color surfaceVariant: themeData.surfaceVariant

    // Text Colors
    property color textPrimary: themeData.textPrimary
    property color textSecondary: themeData.textSecondary
    property color textDisabled: themeData.textDisabled

    // Accent Colors
    property color accentPrimary: themeData.accentPrimary
    property color accentSecondary: themeData.accentSecondary
    property color accentTertiary: themeData.accentTertiary

    // Error/Warning
    property color error: themeData.error
    property color warning: themeData.warning

    // Highlights & Focus
    property color highlight: themeData.highlight
    property color rippleEffect: themeData.rippleEffect

    // Additional Theme Properties
    property color onAccent: themeData.onAccent
    property color outline: themeData.outline

    // Shadows & Overlays
    property color shadow: applyOpacity(themeData.shadow, "B3")
    property color overlay: applyOpacity(themeData.overlay, "66")

    // Font Properties
    property string fontFamily: "Roboto"         // Family for all text
    
    // Font size multiplier - adjust this in Settings.json to scale all fonts
    property real fontSizeMultiplier: Settings.settings.fontSizeMultiplier || 1.0
    
    // Base font sizes (multiplied by fontSizeMultiplier)
    property int fontSizeHeader: Math.round(32 * fontSizeMultiplier)     // Headers and titles
    property int fontSizeBody: Math.round(16 * fontSizeMultiplier)       // Body text and general content
    property int fontSizeSmall: Math.round(14 * fontSizeMultiplier)      // Small text like clock, labels
    property int fontSizeCaption: Math.round(12 * fontSizeMultiplier)    // Captions and fine print
}
