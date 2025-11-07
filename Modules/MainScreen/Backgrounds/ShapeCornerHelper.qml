pragma Singleton

import QtQuick
import QtQuick.Shapes
import Quickshell


/**
 * ShapeCornerHelper - Utility singleton for shape corner calculations
 *
 * Uses 4-state per-corner system for flexible corner rendering:
 * - State -1: No radius (flat/square corner)
 * - State 0: Normal (inner curve)
 * - State 1: Horizontal inversion (outer curve on X-axis)
 * - State 2: Vertical inversion (outer curve on Y-axis)
 *
 * The key technique: Using PathArc direction control (Clockwise vs Counterclockwise)
 * combined with multipliers to create both inner and outer corner curves.
 */
Singleton {
  id: root


  /**
   * Get X-axis multiplier for a corner state
   * State 1 (horizontal invert) returns -1, others return 1
   */
  function getMultX(cornerState) {
    return cornerState === 1 ? -1 : 1
  }


  /**
   * Get Y-axis multiplier for a corner state
   * State 2 (vertical invert) returns -1, others return 1
   */
  function getMultY(cornerState) {
    return cornerState === 2 ? -1 : 1
  }


  /**
   * Get PathArc direction for a corner based on its multipliers
   * Uses XOR logic: if X inverted differs from Y inverted, use Counterclockwise
   * This creates the outer curve effect for inverted corners
   */
  function getArcDirection(multX, multY) {
    return ((multX < 0) !== (multY < 0)) ? PathArc.Counterclockwise : PathArc.Clockwise
  }


  /**
   * Convenience function to get arc direction directly from corner state
   */
  function getArcDirectionFromState(cornerState) {
    const multX = getMultX(cornerState)
    const multY = getMultY(cornerState)
    return getArcDirection(multX, multY)
  }


  /**
   * Get the "flattening" radius when shape dimensions are too small
   * Prevents visual artifacts when radius exceeds dimensions
   */
  function getFlattenedRadius(dimension, requestedRadius) {
    if (dimension < requestedRadius * 2) {
      return dimension / 2
    }
    return requestedRadius
  }


  /**
   * Check if a shape should use flattened corners
   * Returns true if width or height is too small for the requested radius
   */
  function shouldFlatten(width, height, radius) {
    return width < radius * 2 || height < radius * 2
  }
}
