pragma ComponentBehavior

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Image {
  id: root

  property string imagePath: ""
  property string imageHash: ""
  property int maxCacheDimension: 512
  readonly property string cachePath: imageHash ? `${Settings.cacheDirImages}${imageHash}@${maxCacheDimension}x${maxCacheDimension}.png` : ""

  asynchronous: true
  fillMode: Image.PreserveAspectCrop
  sourceSize.width: maxCacheDimension
  sourceSize.height: maxCacheDimension
  smooth: true
  onImagePathChanged: {
    if (imagePath) {
      hashProcess.command = ["sha256sum", imagePath]
      hashProcess.running = true
    } else {
      source = ""
      imageHash = ""
    }
  }
  onCachePathChanged: {
    if (imageHash && cachePath) {
      // Try to load the cached version, failure will be detected below in onStatusChanged
      source = cachePath
      //Logger.Log(imagePath, cachePath)
    }
  }
  onStatusChanged: {
    if (source == cachePath && status === Image.Error) {
      // Cached image was not available, show the original
      source = imagePath
    } else if (source == imagePath && status === Image.Ready && imageHash && cachePath) {
      // Original image is shown and fully loaded, time to cache it
      const grabPath = cachePath
      if (visible && width > 0 && height > 0 && Window.window && Window.window.visible)
      grabToImage(res => {
                    return res.saveToFile(grabPath)
                  })
    }
  }

  Process {
    id: hashProcess
    stdout: StdioCollector {
      onStreamFinished: {
        root.imageHash = text.split(" ")[0]
      }
    }
  }
}
