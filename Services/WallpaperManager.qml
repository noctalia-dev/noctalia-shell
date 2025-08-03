pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Settings

Singleton {
    id: manager

    Item {
        Component.onCompleted: {
            loadWallpapers();
            setCurrentWallpaper(currentWallpaper, true);
            toggleRandomWallpaper();
        }
    }

    property var wallpaperList: []
    property var wallpaperSwwwList: [] // Swww support more wallpapers format
    property string currentWallpaper: Settings.settings.currentWallpaper
    property bool scanning: false
    property string transitionType: Settings.settings.transitionType
    property var randomChoices: ["fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer"]

    function loadWallpapers() {
        scanning = true;
        wallpaperList = [];
        wallpaperSwwwList = [];
        folderModel.folder = "";
        folderModel.folder = "file://" + (Settings.settings.wallpaperFolder !== undefined ? Settings.settings.wallpaperFolder : "");
    }

    function changeWallpaper(path) {
        setCurrentWallpaper(path);
    }

    function setCurrentWallpaper(path, isInitial) {
        currentWallpaper = path;
        if (!isInitial) {
            Settings.settings.currentWallpaper = path;
        }
        if (Settings.settings.useSWWW) {
            if (Settings.settings.transitionType === "random") {
                transitionType = randomChoices[Math.floor(Math.random() * randomChoices.length)];
            } else {
                transitionType = Settings.settings.transitionType;
            }
            changeWallpaperProcess.running = true;
        }

        if (randomWallpaperTimer.running) {
            randomWallpaperTimer.restart();
        }

        generateTheme();
    }

    function setRandomWallpaper() {
        var randomIndex = Math.floor(Math.random() * wallpaperSwwwList.length);
        var randomPath = wallpaperSwwwList[randomIndex];
        if (!randomPath) {
            return;
        }
        setCurrentWallpaper(randomPath);
    }

    function toggleRandomWallpaper() {
        if (Settings.settings.randomWallpaper && !randomWallpaperTimer.running) {
            randomWallpaperTimer.start();
            setRandomWallpaper();
        } else if (!Settings.settings.randomWallpaper && randomWallpaperTimer.running) {
            randomWallpaperTimer.stop();
        }
    }
    
    function restartRandomWallpaperTimer() {
        if (Settings.settings.randomWallpaper) {
            randomWallpaperTimer.stop();
            randomWallpaperTimer.start();
        }
    }

    function generateTheme() {
        if (Settings.settings.useWallpaperTheme) {
            generateThemeProcess.running = true;
        }
    }

    Timer {
        id: randomWallpaperTimer
        interval: Settings.settings.wallpaperInterval * 1000
        running: false
        repeat: true
        onTriggered: setRandomWallpaper()
        triggeredOnStart: false
    }

    FolderListModel {
        id: folderModel
        // Swww supports many images format, Quickshell only support a subset of those.
        nameFilters: ["*.avif", "*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.tga", "*.tiff", "*.webp", "*.bmp", "*.ff"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                // Quickshell only supports a subset of images format
                var qsCompatibleExt = ["jpg", "jpeg", "png", "gif", "pnm", "bmp"]
                var files = [];
                var filesSwww = [];
                for (var i = 0; i < count; i++) {
                    var filepath = (Settings.settings.wallpaperFolder !== undefined ? Settings.settings.wallpaperFolder : "") + "/" + get(i, "fileName");
                    filesSwww.push(filepath);

                    // Second filter for remove all extension incompatible with QuickShell
                    var ext = filepath.split('.').pop().toLowerCase();
                    if (qsCompatibleExt.includes(ext)) {
                        files.push(filepath);
                    }
                }
                wallpaperList = files;
                wallpaperSwwwList = filesSwww;
                scanning = false;
                // console.log(wallpaperList.length);
                // console.log(wallpaperSwwwList.length);
            }
        }
    }

    Process {
        id: changeWallpaperProcess
        command: ["swww", "img", "--resize", Settings.settings.wallpaperResize, "--transition-fps", Settings.settings.transitionFps.toString(), "--transition-type", transitionType, "--transition-duration", Settings.settings.transitionDuration.toString(), currentWallpaper]
        running: false
    }
    
    Process {
        id: generateThemeProcess
        command: ["wallust", "run", currentWallpaper, "-u", "-k", "-d", "Templates"]
        workingDirectory: Quickshell.shellDir
        running: false
    }
}
