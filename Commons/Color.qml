pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

/*
Noctalia is not strictly a Material Design project, it supports both some predefined
color schemes and dynamic color generation from the wallpaper.

We ultimately decided to use a restricted set of colors that follows the
Material Design 3 naming convention.

NOTE: All color names are prefixed with 'm' (e.g., mPrimary) to prevent QML from
misinterpreting them as signals (e.g., the 'onPrimary' property name).
*/
Singleton {
  id: root

  property bool reloadColors: false

  // Flag indicating theme colors are currently transitioning (for widgets to disable their own animations)
  property bool isTransitioning: false

  // Timer to reset isTransitioning after animation completes
  Timer {
    id: transitionTimer
    interval: Style.animationSlowest + 50 // Small buffer after animation
    onTriggered: root.isTransitioning = false
  }

  // --- Key Colors: These are the main accent colors that define your app's style
  property color mPrimary: defaultColors.mPrimary
  property color mOnPrimary: defaultColors.mOnPrimary
  property color mSecondary: defaultColors.mSecondary
  property color mOnSecondary: defaultColors.mOnSecondary
  property color mTertiary: defaultColors.mTertiary
  property color mOnTertiary: defaultColors.mOnTertiary

  // --- Utility Colors: These colors serve specific, universal purposes like indicating errors
  property color mError: defaultColors.mError
  property color mOnError: defaultColors.mOnError

  // --- Surface and Variant Colors: These provide additional options for surfaces and their contents, creating visual hierarchy
  property color mSurface: defaultColors.mSurface
  property color mOnSurface: defaultColors.mOnSurface

  property color mSurfaceVariant: defaultColors.mSurfaceVariant
  property color mOnSurfaceVariant: defaultColors.mOnSurfaceVariant

  property color mOutline: defaultColors.mOutline
  property color mShadow: defaultColors.mShadow

  property color mHover: defaultColors.mHover
  property color mOnHover: defaultColors.mOnHover

  // --- Color transition animations ---
  Behavior on mPrimary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnPrimary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mSecondary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnSecondary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mTertiary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnTertiary {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mError {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnError {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mSurface {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnSurface {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mSurfaceVariant {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnSurfaceVariant {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOutline {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mShadow {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mHover {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }
  Behavior on mOnHover {
    ColorAnimation {
      duration: Style.animationSlowest
      easing.type: Style.easingTypeSlow
    }
  }

  // Helper to start transition and update a color
  function startTransition() {
    root.isTransitioning = true;
    transitionTimer.restart();
  }

  // Update colors when customColorsData changes (imperative assignment enables Behavior animations)
  Connections {
    target: customColorsData
    function onMPrimaryChanged() {
      startTransition();
      root.mPrimary = customColorsData.mPrimary;
    }
    function onMOnPrimaryChanged() {
      startTransition();
      root.mOnPrimary = customColorsData.mOnPrimary;
    }
    function onMSecondaryChanged() {
      startTransition();
      root.mSecondary = customColorsData.mSecondary;
    }
    function onMOnSecondaryChanged() {
      startTransition();
      root.mOnSecondary = customColorsData.mOnSecondary;
    }
    function onMTertiaryChanged() {
      startTransition();
      root.mTertiary = customColorsData.mTertiary;
    }
    function onMOnTertiaryChanged() {
      startTransition();
      root.mOnTertiary = customColorsData.mOnTertiary;
    }
    function onMErrorChanged() {
      startTransition();
      root.mError = customColorsData.mError;
    }
    function onMOnErrorChanged() {
      startTransition();
      root.mOnError = customColorsData.mOnError;
    }
    function onMSurfaceChanged() {
      startTransition();
      root.mSurface = customColorsData.mSurface;
    }
    function onMOnSurfaceChanged() {
      startTransition();
      root.mOnSurface = customColorsData.mOnSurface;
    }
    function onMSurfaceVariantChanged() {
      startTransition();
      root.mSurfaceVariant = customColorsData.mSurfaceVariant;
    }
    function onMOnSurfaceVariantChanged() {
      startTransition();
      root.mOnSurfaceVariant = customColorsData.mOnSurfaceVariant;
    }
    function onMOutlineChanged() {
      startTransition();
      root.mOutline = customColorsData.mOutline;
    }
    function onMShadowChanged() {
      startTransition();
      root.mShadow = customColorsData.mShadow;
    }
    function onMHoverChanged() {
      startTransition();
      root.mHover = customColorsData.mHover;
    }
    function onMOnHoverChanged() {
      startTransition();
      root.mOnHover = customColorsData.mOnHover;
    }
  }

  function resolveColorKey(key) {
    switch (key) {
    case "primary":
      return root.mPrimary;
    case "secondary":
      return root.mSecondary;
    case "tertiary":
      return root.mTertiary;
    case "error":
      return root.mError;
    default:
      return root.mOnSurface;
    }
  }

  function resolveColorKeyOptional(key) {
    switch (key) {
    case "primary":
      return root.mPrimary;
    case "secondary":
      return root.mSecondary;
    case "tertiary":
      return root.mTertiary;
    case "error":
      return root.mError;
    default:
      return "transparent";
    }
  }

  readonly property var colorKeyModel: [
    {
      "key": "none",
      "name": I18n.tr("common.none")
    },
    {
      "key": "primary",
      "name": I18n.tr("common.primary")
    },
    {
      "key": "secondary",
      "name": I18n.tr("common.secondary")
    },
    {
      "key": "tertiary",
      "name": I18n.tr("common.tertiary")
    },
    {
      "key": "error",
      "name": I18n.tr("common.error")
    }
  ]

  // --------------------------------
  // Default colors: Rose Pine
  QtObject {
    id: defaultColors

    readonly property color mPrimary: "#c7a1d8"
    readonly property color mOnPrimary: "#1a151f"

    readonly property color mSecondary: "#a984c4"
    readonly property color mOnSecondary: "#f3edf7"

    readonly property color mTertiary: "#e0b7c9"
    readonly property color mOnTertiary: "#20161f"

    readonly property color mError: "#e9899d"
    readonly property color mOnError: "#1e1418"

    readonly property color mSurface: "#1c1822"
    readonly property color mOnSurface: "#e9e4f0"

    readonly property color mSurfaceVariant: "#262130"
    readonly property color mOnSurfaceVariant: "#a79ab0"

    readonly property color mOutline: "#342c42"
    readonly property color mShadow: "#120f18"

    readonly property color mHover: "#e0b7c9"
    readonly property color mOnHover: "#20161f"
  }

  // ----------------------------------------------------------------
  // FileView to load custom colors data from colors.json
  FileView {
    id: customColorsFile
    path: Settings.directoriesCreated ? (Settings.configDir + "colors.json") : undefined
    printErrors: false
    watchChanges: true
    onFileChanged: {
      Logger.d("Color", "Reloading colors from disk");
      reloadColors = true;
      reload();
    }
    onAdapterUpdated: {
      Logger.d("Color", "Writing colors to disk");
      writeAdapter();
    }

    // Trigger initial load when path changes from empty to actual path
    onPathChanged: {
      if (path !== undefined) {
        reload();
      }
    }
    onLoadFailed: function (error) {
      if (reloadColors) {
        reloadColors = false;
        return;
      }

      // Error code 2 = ENOENT (No such file or directory)
      if (error === 2 || error.toString().includes("No such file")) {
        // File doesn't exist, create it with default values
        writeAdapter();
      }
    }
    JsonAdapter {
      id: customColorsData

      property color mPrimary: defaultColors.mPrimary
      property color mOnPrimary: defaultColors.mOnPrimary

      property color mSecondary: defaultColors.mSecondary
      property color mOnSecondary: defaultColors.mOnSecondary

      property color mTertiary: defaultColors.mTertiary
      property color mOnTertiary: defaultColors.mOnTertiary

      property color mError: defaultColors.mError
      property color mOnError: defaultColors.mOnError

      property color mSurface: defaultColors.mSurface
      property color mOnSurface: defaultColors.mOnSurface

      property color mSurfaceVariant: defaultColors.mSurfaceVariant
      property color mOnSurfaceVariant: defaultColors.mOnSurfaceVariant

      property color mOutline: defaultColors.mOutline
      property color mShadow: defaultColors.mShadow

      property color mHover: defaultColors.mHover
      property color mOnHover: defaultColors.mOnHover
    }
  }
}
