pragma ComponentBehavior

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../Helpers/sha256.js" as Checksum

Image {
  id: root

  property string imagePath: ""
  property string imageHash: ""
  property string cacheFolder: Settings.cacheDirImages
  property int maxCacheDimension: 512
  readonly property string cachePath: imageHash ? `${cacheFolder}${imageHash}@${maxCacheDimension}x${maxCacheDimension}.png` : ""

  asynchronous: true
  fillMode: Image.PreserveAspectCrop
  sourceSize.width: maxCacheDimension
  sourceSize.height: maxCacheDimension
  smooth: true
  onImagePathChanged: {
    if (imagePath) {
      imageHash = Checksum.sha256(imagePath)
      // Logger.log("NImageCached", imagePath, imageHash)
    } else {
      source = ""
      imageHash = ""
    }
  }
  onCachePathChanged: {
    if (imageHash && cachePath) {
      // Check if cache file exists before trying to load it
      cacheChecker.command = ["test", "-f", cachePath]
      cacheChecker.running = true
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

  // Check if cache file exists to avoid warnings
  Process {
    id: cacheChecker
    running: false
    onExited: function (exitCode) {
      if (exitCode === 0 && root.cachePath) {
        // Cache file exists, load it
        root.source = root.cachePath
      } else if (root.imagePath) {
        // Cache doesn't exist, load original directly
        root.source = root.imagePath
      }
    }
  }
}
