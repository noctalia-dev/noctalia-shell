import QtQuick
import qs.Commons

Rectangle {
  anchors.fill: parent
  gradient: Gradient {
    GradientStop {
      position: 0.0
      color: Qt.alpha(Color.mShadow, 0.8)
    }
    GradientStop {
      position: 0.3
      color: Qt.alpha(Color.mShadow, 0.4)
    }
    GradientStop {
      position: 0.7
      color: Qt.alpha(Color.mShadow, 0.5)
    }
    GradientStop {
      position: 1.0
      color: Qt.alpha(Color.mShadow, 0.9)
    }
  }
}
