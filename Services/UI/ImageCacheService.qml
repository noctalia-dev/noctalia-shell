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
  readonly property string wpOverviewDir: baseDir + "wallpapers/overview/"
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

  // Process queues to prevent "too many open files" errors
  property var utilityProcessQueue: []
  property int runningUtilityProcesses: 0
  readonly property int maxConcurrentUtilityProcesses: 16

  // Separate queue for heavy ImageMagick processing (lower concurrency)
  property var imageMagickQueue: []
  property int runningImageMagickProcesses: 0
  readonly property int maxConcurrentImageMagickProcesses: 4

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
    Quickshell.execDetached(["mkdir", "-p", wpOverviewDir]);
    Quickshell.execDetached(["mkdir", "-p", notificationsDir]);
    Quickshell.execDetached(["mkdir", "-p", contributorsDir]);
  }

  function cleanupOldCache() {
    const dirs = [wpThumbDir, wpLargeDir, wpOverviewDir, notificationsDir, contributorsDir];
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
      const cachedPath = wpThumbDir + cacheKey + ".png";

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
  // Public API: Get Large Image (scaled to specified dimensions)
  // -------------------------------------------------
  function getLarge(sourcePath, width, height, callback) {
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
        const cacheKey = generateLargeKey(sourcePath, width, height, mtime);
        const cachedPath = wpLargeDir + cacheKey + ".png";

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

    // Resolve bare file path for temp check
    const filePath = imageUri.startsWith("file://") ? imageUri.substring(7) : imageUri;

    // File paths in persistent locations are used directly, not cached
    if ((imageUri.startsWith("/") || imageUri.startsWith("file://")) && !isTemporaryPath(filePath)) {
      callback(imageUri, false);
      return;
    }

    const cacheKey = generateNotificationKey(imageUri, appName, summary);
    const cachedPath = notificationsDir + cacheKey + ".png";

    // Temporary file paths are copied to cache before the source is cleaned up
    if (imageUri.startsWith("/") || imageUri.startsWith("file://")) {
      processRequest(cacheKey, cachedPath, imageUri, callback, function () {
        copyTempFileToCache(filePath, cachedPath, cacheKey);
      });
      return;
    }

    processRequest(cacheKey, cachedPath, imageUri, callback, function () {
      // Notifications always use Qt fallback (image:// URIs can't be read by ImageMagick)
      queueFallbackProcessing(imageUri, cachedPath, cacheKey, 64);
    });
  }

  // Check if a path is in a temporary directory that may be cleaned up
  function isTemporaryPath(path) {
    return path.startsWith("/tmp/");
  }

  // Copy a temporary file to the cache directory
  function copyTempFileToCache(sourcePath, destPath, cacheKey) {
    const srcEsc = sourcePath.replace(/'/g, "'\\''");
    const dstEsc = destPath.replace(/'/g, "'\\''");

    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cp", "--", "${srcEsc}", "${dstEsc}"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    queueUtilityProcess({
      name: "CopyTempFile_" + cacheKey,
      processString: processString,
      onComplete: function (exitCode) {
        if (exitCode === 0) {
          Logger.d("ImageCache", "Temp file cached:", destPath);
          notifyCallbacks(cacheKey, destPath, true);
        } else {
          Logger.w("ImageCache", "Failed to cache temp file:", sourcePath);
          notifyCallbacks(cacheKey, "", false);
        }
      },
      onError: function () {
        Logger.e("ImageCache", "Error caching temp file:", sourcePath);
        notifyCallbacks(cacheKey, "", false);
      }
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
  // Public API: Get Blurred Overview (for Niri overview background)
  // -------------------------------------------------
  function getBlurredOverview(sourcePath, width, height, tintColor, isDarkMode, callback) {
    if (!sourcePath || sourcePath === "") {
      callback("", false);
      return;
    }

    if (!imageMagickAvailable) {
      Logger.d("ImageCache", "ImageMagick not available for overview blur, using original:", sourcePath);
      callback(sourcePath, false);
      return;
    }

    getMtime(sourcePath, function (mtime) {
      const cacheKey = generateOverviewKey(sourcePath, width, height, tintColor, isDarkMode, mtime);
      const cachedPath = wpOverviewDir + cacheKey + ".png";

      processRequest(cacheKey, cachedPath, sourcePath, callback, function () {
        startOverviewProcessing(sourcePath, cachedPath, width, height, tintColor, isDarkMode, cacheKey);
      });
    });
  }

  // -------------------------------------------------
  // Cache Key Generation
  // -------------------------------------------------
  function generateThumbnailKey(sourcePath, mtime) {
    const keyString = sourcePath + "@384x384@" + (mtime || "unknown");
    return Checksum.sha256(keyString);
  }

  function generateLargeKey(sourcePath, width, height, mtime) {
    const keyString = sourcePath + "@" + width + "x" + height + "@" + (mtime || "unknown");
    return Checksum.sha256(keyString);
  }

  function generateNotificationKey(imageUri, appName, summary) {
    if (imageUri.startsWith("image://qsimage/")) {
      return Checksum.sha256(appName + "|" + summary);
    }
    return Checksum.sha256(imageUri);
  }

  function generateOverviewKey(sourcePath, width, height, tintColor, isDarkMode, mtime) {
    const keyString = sourcePath + "@" + width + "x" + height + "@" + tintColor + "@" + (isDarkMode ? "dark" : "light") + "@" + (mtime || "unknown");
    return Checksum.sha256(keyString);
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

    // Use Lanczos filter for high-quality downscaling, subtle unsharp mask, and PNG for lossless output
    const command = `magick '${srcEsc}' -auto-orient -filter Lanczos -resize '384x384^' -gravity center -extent 384x384 -unsharp 0x0.5 '${dstEsc}'`;

    runProcess(command, cacheKey, outputPath, sourcePath);
  }

  // -------------------------------------------------
  // ImageMagick Processing: Large
  // -------------------------------------------------
  function startLargeProcessing(sourcePath, outputPath, width, height, cacheKey) {
    const srcEsc = sourcePath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");

    // Use Lanczos filter for high-quality downscaling, subtle unsharp mask, and PNG for lossless output
    const command = `magick '${srcEsc}' -auto-orient -filter Lanczos -resize '${width}x${height}^' -unsharp 0x0.5 '${dstEsc}'`;

    runProcess(command, cacheKey, outputPath, sourcePath);
  }

  // -------------------------------------------------
  // ImageMagick Processing: Blurred Overview
  // -------------------------------------------------
  function startOverviewProcessing(sourcePath, outputPath, width, height, tintColor, isDarkMode, cacheKey) {
    const srcEsc = sourcePath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");

    // Resize, blur, then tint overlay
    const command = `magick '${srcEsc}' -auto-orient -resize '${width}x${height}^' -gravity center -extent ${width}x${height} -gaussian-blur 0x5 \\( +clone -fill '${tintColor}' -colorize 100 -alpha set -channel A -evaluate set 50% +channel \\) -composite '${dstEsc}'`;

    runProcess(command, cacheKey, outputPath, sourcePath);
  }

  // -------------------------------------------------
  // ImageMagick Processing: Circular Avatar
  // -------------------------------------------------
  function downloadAndProcessAvatar(url, username, outputPath, cacheKey) {
    const tempPath = contributorsDir + username + "_temp.png";
    const tempEsc = tempPath.replace(/'/g, "'\\''");
    const urlEsc = url.replace(/'/g, "'\\''");

    // Download first (uses utility queue since curl/wget are lightweight)
    const downloadCmd = `curl -L -s -o '${tempEsc}' '${urlEsc}' || wget -q -O '${tempEsc}' '${urlEsc}'`;

    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${downloadCmd.replace(/"/g, '\\"')}"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    queueUtilityProcess({
                          name: "DownloadProcess_" + cacheKey,
                          processString: processString,
                          onComplete: function (exitCode) {
                            if (exitCode !== 0) {
                              Logger.e("ImageCache", "Failed to download avatar for", username);
                              notifyCallbacks(cacheKey, "", false);
                              return;
                            }
                            // Now process with ImageMagick
                            processCircularAvatar(tempPath, outputPath, cacheKey);
                          },
                          onError: function () {
                            notifyCallbacks(cacheKey, "", false);
                          }
                        });
  }

  function processCircularAvatar(inputPath, outputPath, cacheKey) {
    const srcEsc = inputPath.replace(/'/g, "'\\''");
    const dstEsc = outputPath.replace(/'/g, "'\\''");

    // ImageMagick command for circular crop with alpha
    const command = `magick '${srcEsc}' -resize 256x256^ -gravity center -extent 256x256 -alpha set \\( +clone -channel A -evaluate set 0 +channel -fill white -draw 'circle 128,128 128,0' \\) -compose DstIn -composite '${dstEsc}'`;

    queueImageMagickProcess({
                              command: command,
                              cacheKey: cacheKey,
                              onComplete: function (exitCode) {
                                // Clean up temp file
                                Quickshell.execDetached(["rm", "-f", inputPath]);

                                if (exitCode !== 0) {
                                  Logger.e("ImageCache", "Failed to create circular avatar");
                                  notifyCallbacks(cacheKey, "", false);
                                } else {
                                  Logger.d("ImageCache", "Circular avatar created:", outputPath);
                                  notifyCallbacks(cacheKey, outputPath, true);
                                }
                              },
                              onError: function () {
                                Quickshell.execDetached(["rm", "-f", inputPath]);
                                notifyCallbacks(cacheKey, "", false);
                              }
                            });
  }

  // -------------------------------------------------
  // Generic Process Runner (with queue for ImageMagick)
  // -------------------------------------------------

  // Queue an ImageMagick process and run it when a slot is available
  function queueImageMagickProcess(request) {
    imageMagickQueue.push(request);
    processImageMagickQueue();
  }

  // Process queued ImageMagick requests up to the concurrency limit
  function processImageMagickQueue() {
    while (runningImageMagickProcesses < maxConcurrentImageMagickProcesses && imageMagickQueue.length > 0) {
      const request = imageMagickQueue.shift();
      runImageMagickProcess(request);
    }
  }

  // Actually run an ImageMagick process
  function runImageMagickProcess(request) {
    runningImageMagickProcesses++;

    const processString = `
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", ""]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `;

    try {
      const processObj = Qt.createQmlObject(processString, root, "ImageProcess_" + request.cacheKey);
      processObj.command = ["sh", "-c", request.command];

      processObj.exited.connect(function (exitCode) {
        processObj.destroy();
        runningImageMagickProcesses--;
        request.onComplete(exitCode, processObj);
        processImageMagickQueue();
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to create process:", e);
      runningImageMagickProcesses--;
      request.onError(e);
      processImageMagickQueue();
    }
  }

  function runProcess(command, cacheKey, outputPath, sourcePath) {
    queueImageMagickProcess({
                              command: command,
                              cacheKey: cacheKey,
                              onComplete: function (exitCode, proc) {
                                if (exitCode !== 0) {
                                  const stderrText = proc.stderr.text || "";
                                  Logger.e("ImageCache", "Processing failed:", stderrText);
                                  notifyCallbacks(cacheKey, sourcePath, false);
                                } else {
                                  Logger.d("ImageCache", "Processing complete:", outputPath);
                                  notifyCallbacks(cacheKey, outputPath, true);
                                }
                              },
                              onError: function () {
                                notifyCallbacks(cacheKey, sourcePath, false);
                              }
                            });
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
    color: "transparent"
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
  // Utility Functions (with process queue to prevent fd exhaustion)
  // -------------------------------------------------

  // Queue a utility process and run it when a slot is available
  function queueUtilityProcess(request) {
    utilityProcessQueue.push(request);
    processUtilityQueue();
  }

  // Process queued utility requests up to the concurrency limit
  function processUtilityQueue() {
    while (runningUtilityProcesses < maxConcurrentUtilityProcesses && utilityProcessQueue.length > 0) {
      const request = utilityProcessQueue.shift();
      runUtilityProcess(request);
    }
  }

  // Actually run a utility process
  function runUtilityProcess(request) {
    runningUtilityProcesses++;

    try {
      const processObj = Qt.createQmlObject(request.processString, root, request.name);

      processObj.exited.connect(function (exitCode) {
        processObj.destroy();
        runningUtilityProcesses--;
        request.onComplete(exitCode, processObj);
        processUtilityQueue();
      });

      processObj.running = true;
    } catch (e) {
      Logger.e("ImageCache", "Failed to create " + request.name + ":", e);
      runningUtilityProcesses--;
      request.onError(e);
      processUtilityQueue();
    }
  }

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

    queueUtilityProcess({
                          name: "MtimeProcess",
                          processString: processString,
                          onComplete: function (exitCode, proc) {
                            const mtime = exitCode === 0 ? proc.stdout.text.trim() : "";
                            callback(mtime);
                          },
                          onError: function () {
                            callback("");
                          }
                        });
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

    queueUtilityProcess({
                          name: "FileExistsProcess",
                          processString: processString,
                          onComplete: function (exitCode) {
                            callback(exitCode === 0);
                          },
                          onError: function () {
                            callback(false);
                          }
                        });
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

    queueUtilityProcess({
                          name: "IdentifyProcess",
                          processString: processString,
                          onComplete: function (exitCode, proc) {
                            let width = 0, height = 0;
                            if (exitCode === 0) {
                              const parts = proc.stdout.text.trim().split(" ");
                              if (parts.length >= 2) {
                                width = parseInt(parts[0], 10) || 0;
                                height = parseInt(parts[1], 10) || 0;
                              }
                            }
                            callback(width, height);
                          },
                          onError: function () {
                            callback(0, 0);
                          }
                        });
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

  function invalidateLarge(sourcePath) {
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
