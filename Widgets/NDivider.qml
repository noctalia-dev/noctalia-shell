import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services

Rectangle {
  width: parent.width
  height: Math.max(1, Style.borderS * scaling)
  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop {
      position: 0.0
      color: Color.transparent
    }
    GradientStop {
      position: 0.1
      color: Color.mOutline
    }
    GradientStop {
      position: 0.9
      color: Color.mOutline
    }
    GradientStop {
      position: 1.0
      color: Color.transparent
    }
  }
}
