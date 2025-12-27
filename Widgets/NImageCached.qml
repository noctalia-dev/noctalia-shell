import QtQuick
import qs.Commons
import qs.Services.UI

Image {
  id: root

  property string imagePath: ""
  property int maxCacheDimension: 256

  asynchronous: true
  fillMode: Image.PreserveAspectCrop
  sourceSize.width: maxCacheDimension
  sourceSize.height: maxCacheDimension
  smooth: true

  onImagePathChanged: {
    if (!imagePath) {
      source = "";
      return;
    }

    if (!ImageCacheService.initialized) {
      // Service not ready yet, use original
      source = imagePath;
      return;
    }

    ImageCacheService.getThumbnail(imagePath, function (cachedPath, success) {
      if (!root)
        return; // Component was destroyed
      if (success) {
        root.source = cachedPath;
      } else {
        root.source = imagePath;
      }
    });
  }
}
