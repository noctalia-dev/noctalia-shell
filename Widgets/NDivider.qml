import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons

Rectangle {
  width: parent.width
  height: Style.borderS
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
