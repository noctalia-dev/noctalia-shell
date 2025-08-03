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
    property string currentWallpaper: Settings.settings.currentWallpaper
    property bool scanning: false
    property string transitionType: Settings.settings.transitionType
    property var randomChoices: ["fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer"]

    function loadWallpapers() {
        scanning = true;
        wallpaperList = [];
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
        var randomIndex = Math.floor(Math.random() * wallpaperList.length);
        var randomPath = wallpaperList[randomIndex];
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
        // Swww supports many images format but Quickshell only support a subset of those.
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                var files = [];
                var filesSwww = [];
                for (var i = 0; i < count; i++) {
                    var filepath = (Settings.settings.wallpaperFolder !== undefined ? Settings.settings.wallpaperFolder : "") + "/" + get(i, "fileName");
                    files.push(filepath);
                }
                wallpaperList = files;
                scanning = false;
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
