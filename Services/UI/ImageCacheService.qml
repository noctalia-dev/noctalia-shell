pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../Helpers/sha256.js" as Checksum
import qs.Commons

Singleton {
  id: root

  // -------------------------------------------------
  // Public Properties
  // -------------------------------------------------
  property bool imageMagickAvailable: false
  property bool initialized: false

  // Cache directories
  readonly property string baseDir: Settings.cacheDir + "images/"
  readonly property string wpThumbDir: baseDir + "wallpapers/thumbnails/"
  readonly property string wpLargeDir: baseDir + "wallpapers/large/"
  readonly property string notificationsDir: baseDir + "notifications/"
  readonly property string contributorsDir: baseDir + "contributors/"

  // Supported image formats - extended list when ImageMagick is available
  readonly property var basicImageFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp"]
  readonly property var extendedImageFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.webp", "*.avif", "*.heic", "*.heif", "*.tiff", "*.tif", "*.pnm", "*.pgm", "*.ppm", "*.pbm", "*.svg", "*.svgz", "*.ico", "*.icns", "*.jxl", "*.jp2", "*.j2k", "*.exr", "*.hdr", "*.dds", "*.tga"]
  readonly property var imageFilters: imageMagickAvailable ? extendedImageFilters : basicImageFilters

  // Check if a file format needs conversion (not natively supported by Qt)
  function needsConversion(filePath) {
    const ext = "*." + filePath.toLowerCase().split('.').pop();
    return !basicImageFilters.includes(ext);
  }

  // -------------------------------------------------
  // Internal State
  // -------------------------------------------------
  property var pendingRequests: ({})
  property var fallbackQueue: []
  property bool fallbackProcessing: false

  // -------------------------------------------------
  // Signals
  // -------------------------------------------------
  signal cacheHit(string cacheKey, string cachedPath)
  signal cacheMiss(string cacheKey)
  signal processingComplete(string cacheKey, string cachedPath)
  signal processingFailed(string cacheKey, string error)

  // -------------------------------------------------
  // Initialization
  // -------------------------------------------------
  function init() {
    Logger.i("ImageCache", "Service started");
    createDirectories();
    cleanupOldCache();
    checkMagickProcess.running = true;
  }

  function createDirectories() {
    Quickshell.execDetached(["mkdir", "-p", wpThumbDir]);
    Quickshell.execDetached(["mkdir", "-p", wpLargeDir]);
    Quickshell.execDetached(["mkdir", "-p", notificationsDir]);
    Quickshell.execDetached(["mkdir", "-p", contributorsDir]);
  }

  function cleanupOldCache() {
    const dirs = [wpThumbDir, wpLargeDir, notificationsDir, contributorsDir];
    dirs.forEach(function (dir) {
      Quickshell.execDetached(["find", dir, "-type", "f", "-mtime", "+30", "-delete"]);
    });
    Logger.d("ImageCache", "Cleanup triggered for files older than 30 days");
  }

  // -------------------------------------------------
  // Public API: Get Thumbnail (384x384)
  // -------------------------------------------------
  function getThumbnail(sourcePath, callback) {
    if (!sourcePath || sourcePath === "") {
      callback("", false);
      return;
    }

    getMtime(sourcePath, function (mtime) {
      const cacheKey = generateThumbnailKey(sourcePath, mtime);
      const cachedPath = wpThumbDir + cacheKey + ".jpg";

      processRequest(cacheKey, cachedPath, sourcePath, callback, function () {
        if (imageMagickAvailable) {
          startThumbnailProcessing(sourcePath, cachedPath, cacheKey);
        } else {
          queueFallbackProcessing(sourcePath, cachedPath, cacheKey, 384);
        }
      });
    });
  }

  // -------------------------------------------------
  // Public API: Get Fullscreen Wallpaper
  // -------------------------------------------------
  function getFullscreen(sourcePath, screenName, width, height, callback) {
    if (!sourcePath || sourcePath === "") {
      callback("", false);
      return;
    }

    if (!imageMagickAvailable) {
      Logger.d("ImageCache", "ImageMagick not available, using original:", sourcePath);
      callback(sourcePath, false);
      return;
    }

    // Fast dimension check - skip processing if image fits screen AND format is Qt-native
    getImageDimensions(sourcePath, function (imgWidth, imgHeight) {
      const fitsScreen = imgWidth > 0 && imgHeight > 0 && imgWidth <= width && imgHeight <= height;

      if (fitsScreen) {
        // Only skip if format is natively supported by Qt
        if (!needsConversion(sourcePath)) {
          Logger.d("ImageCache", `Image ${imgWidth}x${imgHeight} fits screen ${width}x${height}, using original`);
          callback(sourcePath, false);
          return;
        }
        Logger.d("ImageCache", `Image needs conversion despite fitting screen`);
      }

      // Use actual image dimensions if it fits (convert without upscaling), otherwise use screen dimensions
      const targetWidth = fitsScreen ? imgWidth : width;
      const targetHeight = fitsScreen ? imgHeight : height;

      getMtime(sourcePath, function (mtime) {
        const cacheKey = generateLargeKey(sourcePath, screenName, width, height, mtime);
        const cachedPath = wpLargeDir + cacheKey + ".jpg";

        processRequest(cacheKey, cachedPath, sourcePath, callback, function () {
          startLargeProcessing(sourcePath, cachedPath, targetWidth, targetHeight, cacheKey);
        });
      });
    });
  }

  // -------------------------------------------------
  // Public API: Get Notification Icon (64x64)
  // -------------------------------------------------
  function getNotificationIcon(imageUri, appName, summary, callback) {
    if (!imageUri || imageUri === "") {
      callback("", false);
      return;
    }

    // File paths are used directly, not cached
    if (imageUri.startsWith("/") || imageUri.startsWith("file://")) {
      callback(imageUri, false);
      return;
    }

    const cacheKey = generateNotificationKey(imageUri, appName, summary);
    const cachedPath = notificationsDir + cacheKey + ".png";

    processRequest(cacheKey, cachedPath, imageUri, callback, function () {
      // Notifications always use Qt fallback (image:// URIs can't be read by ImageMagick)
      queueFallbackProcessing(imageUri, cachedPath, cacheKey, 64);
    });
  }

  // -------------------------------------------------
  // Public API: Get Circular Avatar (256x256)
  // -------------------------------------------------
  function getCircularAvatar(url, username, callback) {
    if (!url || !username) {
      callback("", false);
      return;
    }

    const cacheKey = username;
    const cachedPath = contributorsDir + username + "_circular.png";

    processRequest(cacheKey, cachedPath, url, callback, function () {
      if (imageMagickAvailable) {
        downloadAndProcessAvatar(url, username, cachedPath, cacheKey);
      } else {
        // No fallback for circular avatars without ImageMagick
        Logger.w("ImageCache", "Circular avatars require ImageMagick");
        notifyCallbacks(cacheKey, "", false);
      }
    });
  }

  // -------------------------------------------------
  // Cache Key Generation
  // -------------------------------------------------
  function generateThumbnailKey(sourcePath, mtime) {
    const keyString = sourcePath + "@384x384@" + (mtime || "unknown");
    return Checksum.sha256(keyString);
  }

  function generateLargeKey(sourcePath, screenName, width, height, mtime) {
    const keyString = sourcePath + "@" + screenName + "@" + width + "x" + height + "@" + (mtime || "unknown");
    return Checksum.sha256(keyString);
  }

  function generateNotificationKey(imageUri, appName, summary) {
    if (imageUri.startsWith("image://qsimage/")) {
      return Checksum.sha256(appName + "|" + summary);
    }
    return Checksum.sha256(imageUri);
  }

  // -------------------------------------------------
  // Request Processing (with coalescing)
  // -------------------------------------------------
  function processRequest(cacheKey, cachedPath, sourcePath, callback, processFn) {
    // Check if already processing this request
    if (pendingRequests[cacheKey]) {
      pendingRequests[cacheKey].callbacks.push(callback);
      Logger.d("ImageCache", "Coalescing request for:", cacheKey);
      return;
    }

    // Check cache first
    checkFileExists(cachedPath, function (exists) {
      if (exists) {
        Logger.d("ImageCache", "Cache hit:", cachedPath);
        callback(cachedPath, true);
        cacheHit(cacheKey, cachedPath);
        return;
      }

      // Re-check pendingRequests (race condition fix)
      if (pendingRequests[cacheKey]) {
        pendingRequests[cacheKey].callbacks.push(callback);
        return;
      }

      // Start new processing
      Logger.d("ImageCache", "Cache miss, processing:", sourcePath);
      cacheMiss(cacheKey);
      pendingRequests[cacheKey] = {
        callbacks: [callback],
        sourcePath: sourcePath
      };

      processFn();
    });
  }

  function notifyCallbacks(cacheKey, path, success) {
    const request = pendingRequests[cacheKey];
    if (request) {
      request.callbacks.forEach(function (cb) {
        cb(path, success);
      });
      delete pendingRequests[cacheKey];
    }

    if (success) {
      processingComplete(cacheKey, path);
    } else {
      processingFailed(cacheKey, "Processing failed");
    }
  }

  // -------------------------------------------------
  // ImageMagick Processing: Thumbnail
  // -------------------------------------------------
  function startThumbnailProcessing(sourcePath, outputPath, cacheKey) {
    const srcEsc = sourcePath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");

    const command = `magick -define jpeg:size=768x768 '${srcEsc}' -auto-orient -thumbnail '384x384^' -gravity center -extent 384x384 -quality 85 '${dstEsc}'`;

    runProcess(command, cacheKey, outputPath, sourcePath);
  }

  // -------------------------------------------------
  // ImageMagick Processing: Large
  // -------------------------------------------------
  function startLargeProcessing(sourcePath, outputPath, width, height, cacheKey) {
    const srcEsc = sourcePath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");
    const doubleWidth = width * 2;
    const doubleHeight = height * 2;

    const command = `magick -define jpeg:size=${doubleWidth}x${doubleHeight} '${srcEsc}' -auto-orient -thumbnail '${width}x${height}^' -quality 95 '${dstEsc}'`;

    runProcess(command, cacheKey, outputPath, sourcePath);
  }

  // -------------------------------------------------
  // ImageMagick Processing: Circular Avatar
  // -------------------------------------------------
  function downloadAndProcessAvatar(url, username, outputPath, cacheKey) {
    const tempPath = contributorsDir + username + "_temp.png";
    const tempEsc = tempPath.replace(/'/g, "'\\''");
    const urlEsc = url.replace(/'/g, "'\\''");

    // Download first
    const downloadCmd = `curl -L -s -o '${tempEsc}' '${urlEsc}' || wget -q -O '${tempEsc}' '${urlEsc}'`;

    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["bash", "-c", ""]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const downloadProcess = Qt.createQmlObject(processString, root, "DownloadProcess_" + cacheKey);
      downloadProcess.command = ["bash", "-c", downloadCmd];

      downloadProcess.exited.connect(function (exitCode) {
        downloadProcess.destroy();

        if (exitCode !== 0) {
          Logger.e("ImageCache", "Failed to download avatar for", username);
          notifyCallbacks(cacheKey, "", false);
          return;
        }

        // Now process with ImageMagick
        processCircularAvatar(tempPath, outputPath, cacheKey);
      });

      downloadProcess.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to create download process:", e);
      notifyCallbacks(cacheKey, "", false);
    }
  }

  function processCircularAvatar(inputPath, outputPath, cacheKey) {
    const srcEsc = inputPath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");

    // ImageMagick command for circular crop with alpha
    const command = `magick '${srcEsc}' -resize 256x256^ -gravity center -extent 256x256 -alpha set \\( +clone -channel A -evaluate set 0 +channel -fill white -draw 'circle 128,128 128,0' \\) -compose DstIn -composite '${dstEsc}'`;

    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["bash", "-c", ""]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "CircularProcess_" + cacheKey);
      processObj.command = ["bash", "-c", command];

      processObj.exited.connect(function (exitCode) {
        // Clean up temp file
        Quickshell.execDetached(["rm", "-f", inputPath]);

        if (exitCode !== 0) {
          Logger.e("ImageCache", "Failed to create circular avatar");
          notifyCallbacks(cacheKey, "", false);
        } else {
          Logger.d("ImageCache", "Circular avatar created:", outputPath);
          notifyCallbacks(cacheKey, outputPath, true);
        }

        processObj.destroy();
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to create circular process:", e);
      Quickshell.execDetached(["rm", "-f", inputPath]);
      notifyCallbacks(cacheKey, "", false);
    }
  }

  // -------------------------------------------------
  // Generic Process Runner
  // -------------------------------------------------
  function runProcess(command, cacheKey, outputPath, sourcePath) {
    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        property string cacheKey: ""
        property string cachedPath: ""
        command: ["bash", "-c", ""]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "ImageProcess_" + cacheKey);
      processObj.cacheKey = cacheKey;
      processObj.cachedPath = outputPath;
      processObj.command = ["bash", "-c", command];

      processObj.exited.connect(function (exitCode) {
        if (exitCode !== 0) {
          const stderrText = processObj.stderr.text || "";
          Logger.e("ImageCache", "Processing failed:", stderrText);
          notifyCallbacks(cacheKey, sourcePath, false);
        } else {
          Logger.d("ImageCache", "Processing complete:", outputPath);
          notifyCallbacks(cacheKey, outputPath, true);
        }

        processObj.destroy();
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to create process:", e);
      notifyCallbacks(cacheKey, sourcePath, false);
    }
  }

  // -------------------------------------------------
  // Qt Fallback Renderer
  // -------------------------------------------------
  PanelWindow {
    id: fallbackRenderer
    implicitWidth: 0
    implicitHeight: 0
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "noctalia-image-cache-renderer"
    color: Color.transparent
    mask: Region {}

    Image {
      id: fallbackImage
      property string cacheKey: ""
      property string destPath: ""
      property int targetSize: 256

      width: targetSize
      height: targetSize
      visible: true
      cache: false
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      mipmap: true
      antialiasing: true

      onStatusChanged: {
        if (!cacheKey)
        return;

        if (status === Image.Ready) {
          grabToImage(function (result) {
            if (result.saveToFile(destPath)) {
              Logger.d("ImageCache", "Fallback cache created:", destPath);
              root.notifyCallbacks(cacheKey, destPath, true);
            } else {
              Logger.e("ImageCache", "Failed to save fallback cache");
              root.notifyCallbacks(cacheKey, "", false);
            }
            processNextFallback();
          });
        } else if (status === Image.Error) {
          Logger.e("ImageCache", "Fallback image load failed");
          root.notifyCallbacks(cacheKey, "", false);
          processNextFallback();
        }
      }

      function processNextFallback() {
        cacheKey = "";
        destPath = "";
        source = "";

        if (fallbackQueue.length > 0) {
          const next = fallbackQueue.shift();
          cacheKey = next.cacheKey;
          destPath = next.destPath;
          targetSize = next.size;
          source = next.sourcePath;
        } else {
          fallbackProcessing = false;
        }
      }
    }
  }

  function queueFallbackProcessing(sourcePath, destPath, cacheKey, size) {
    fallbackQueue.push({
                         sourcePath: sourcePath,
                         destPath: destPath,
                         cacheKey: cacheKey,
                         size: size
                       });

    if (!fallbackProcessing) {
      fallbackProcessing = true;
      const item = fallbackQueue.shift();
      fallbackImage.cacheKey = item.cacheKey;
      fallbackImage.destPath = item.destPath;
      fallbackImage.targetSize = item.size;
      fallbackImage.source = item.sourcePath;
    }
  }

  // -------------------------------------------------
  // Utility Functions
  // -------------------------------------------------
  function getMtime(filePath, callback) {
    const pathEsc = filePath.replace(/'/g, "'\\''");
    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["stat", "-c", "%Y", "${pathEsc}"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "MtimeProcess");

      processObj.exited.connect(function (exitCode) {
        const mtime = exitCode === 0 ? processObj.stdout.text.trim() : "";
        processObj.destroy();
        callback(mtime);
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to get mtime:", e);
      callback("");
    }
  }

  function checkFileExists(filePath, callback) {
    const pathEsc = filePath.replace(/'/g, "'\\''");
    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["test", "-f", "${pathEsc}"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "FileExistsProcess");

      processObj.exited.connect(function (exitCode) {
        processObj.destroy();
        callback(exitCode === 0);
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to check file:", e);
      callback(false);
    }
  }

  function getImageDimensions(filePath, callback) {
    const pathEsc = filePath.replace(/'/g, "'\\''");
    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["identify", "-ping", "-format", "%w %h", "${pathEsc}[0]"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "IdentifyProcess");

      processObj.exited.connect(function (exitCode) {
        let width = 0, height = 0;
        if (exitCode === 0) {
          const parts = processObj.stdout.text.trim().split(" ");
          if (parts.length >= 2) {
            width = parseInt(parts[0], 10) || 0;
            height = parseInt(parts[1], 10) || 0;
          }
        }
        processObj.destroy();
        callback(width, height);
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to get image dimensions:", e);
      callback(0, 0);
    }
  }

  // -------------------------------------------------
  // Cache Invalidation
  // -------------------------------------------------
  function invalidateThumbnail(sourcePath) {
    Logger.i("ImageCache", "Invalidating thumbnail for:", sourcePath);
    // Since cache keys include hash, we'd need to track mappings
    // For simplicity, clear all thumbnails
    clearThumbnails();
  }

  function invalidateLarge(sourcePath, screenName) {
    Logger.i("ImageCache", "Invalidating large for:", sourcePath);
    clearLarge();
  }

  function invalidateNotification(imageId) {
    const path = notificationsDir + imageId + ".png";
    Quickshell.execDetached(["rm", "-f", path]);
  }

  function invalidateAvatar(username) {
    const path = contributorsDir + username + "_circular.png";
    Quickshell.execDetached(["rm", "-f", path]);
  }

  // -------------------------------------------------
  // Clear Cache Functions
  // -------------------------------------------------
  function clearAll() {
    Logger.i("ImageCache", "Clearing all cache");
    clearThumbnails();
    clearLarge();
    clearNotifications();
    clearContributors();
  }

  function clearThumbnails() {
    Logger.i("ImageCache", "Clearing thumbnails cache");
    Quickshell.execDetached(["rm", "-rf", wpThumbDir]);
    Quickshell.execDetached(["mkdir", "-p", wpThumbDir]);
  }

  function clearLarge() {
    Logger.i("ImageCache", "Clearing large cache");
    Quickshell.execDetached(["rm", "-rf", wpLargeDir]);
    Quickshell.execDetached(["mkdir", "-p", wpLargeDir]);
  }

  function clearNotifications() {
    Logger.i("ImageCache", "Clearing notifications cache");
    Quickshell.execDetached(["rm", "-rf", notificationsDir]);
    Quickshell.execDetached(["mkdir", "-p", notificationsDir]);
  }

  function clearContributors() {
    Logger.i("ImageCache", "Clearing contributors cache");
    Quickshell.execDetached(["rm", "-rf", contributorsDir]);
    Quickshell.execDetached(["mkdir", "-p", contributorsDir]);
  }

  // -------------------------------------------------
  // ImageMagick Detection
  // -------------------------------------------------
  Process {
    id: checkMagickProcess
    command: ["sh", "-c", "command -v magick"]
    running: false

    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      root.imageMagickAvailable = (exitCode === 0);
      root.initialized = true;
      if (root.imageMagickAvailable) {
        Logger.i("ImageCache", "ImageMagick available");
      } else {
        Logger.w("ImageCache", "ImageMagick not found, using Qt fallback");
      }
    }
  }
}
