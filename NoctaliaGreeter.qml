pragma ComponentBehavior

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

import qs.Commons

Item {
  id: root

  // Config via environment variables
  readonly property string instant_auth: Quickshell.env("NOCTALIA_DM_INSTANTAUTH")
  readonly property string preferred_session: Quickshell.env("NOCTALIA_DM_PREF_SES")
  readonly property string preferred_user: Quickshell.env("NOCTALIA_DM_PREF_USR")
  // Fallback to empty string and log later to avoid assigning console.log result
  readonly property string sessions: Quickshell.env("NOCTALIA_DM_SESSIONS") || ""
  readonly property string wallpaper_path: Quickshell.env("NOCTALIA_DM_WALLPATH")

  // Noctalia config paths
  readonly property string noctaliaConfigDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/noctalia/"
  readonly property string noctaliaSettingsFile: noctaliaConfigDir + "settings.json"

  // Wallpaper state from noctalia config
  property string noctaliaWallpaper: ""
  property string currentMonitorName: ""

  function authenticate() {
    Greetd.createSession(users.current_user)
  }

  Component.onCompleted: {
    if (sessions == "") {
      console.log("[WARN] empty sessions list, defaulting to hyprland")
      sessions.current_session = "hyprland"
      sessions.current_session_name = "hyprland"
    }

    // Initialize session from saved settings after UI load (final check occurs after sessions load too)
    const saved = GreeterSettings.lastSessionId
    if (saved && sessions.session_execs.length > 0) {
      for (var i = 0; i < sessions.session_names.length; i++) {
        if (sessions.session_execs[i].toLowerCase().includes(saved.toLowerCase()) || sessions.session_names[i].toLowerCase().includes(saved.toLowerCase())) {
          sessions.current_ses_index = i
          break
        }
      }
    }
  }

  // Load noctalia settings to get wallpaper
  FileView {
    id: noctaliaSettingsLoader
    path: root.noctaliaSettingsFile
    watchChanges: true

    JsonAdapter {
      id: noctaliaSettings
      property JsonObject wallpaper: JsonObject {
        property bool enabled: true
        property string directory: ""
        property bool setWallpaperOnAllMonitors: true
        property list<var> monitors: []
      }
    }

    onLoaded: {
      console.log("[INFO] Loaded noctalia settings from:", root.noctaliaSettingsFile)
      updateWallpaperFromNoctaliaConfig()
    }

    onLoadFailed: function (error) {
      console.log("[WARN] Failed to load noctalia settings:", error)
      console.log("[INFO] Using fallback wallpaper from environment variable")
    }

    Component.onCompleted: reload()
  }

  function updateWallpaperFromNoctaliaConfig() {
    if (!noctaliaSettings.wallpaper.enabled) {
      console.log("[INFO] Wallpaper disabled in noctalia config")
      return
    }

    // Get current monitor name (you may need to adapt this based on your setup)
    if (Quickshell.screens.length > 0) {
      currentMonitorName = Quickshell.screens[0].name
    }

    // Look for monitor-specific wallpaper
    const monitors = noctaliaSettings.wallpaper.monitors
    let foundWallpaper = ""

    if (monitors && monitors.length > 0) {
      for (var i = 0; i < monitors.length; i++) {
        const monitor = monitors[i]
        if (monitor && monitor.name === currentMonitorName && monitor.wallpaper) {
          foundWallpaper = monitor.wallpaper
          console.log("[INFO] Found monitor-specific wallpaper for", currentMonitorName + ":", foundWallpaper)
          break
        }
      }
    }

    // Fallback to directory + some default logic if no specific wallpaper found
    if (!foundWallpaper && noctaliaSettings.wallpaper.directory) {
      console.log("[INFO] No monitor-specific wallpaper found, using directory:", noctaliaSettings.wallpaper.directory)
      // You might want to implement directory scanning logic here
      // For now, we'll just use the directory path as a fallback
      foundWallpaper = noctaliaSettings.wallpaper.directory
    }

    if (foundWallpaper) {
      root.noctaliaWallpaper = foundWallpaper
      console.log("[INFO] Using noctalia wallpaper:", foundWallpaper)
    } else {
      console.log("[INFO] No wallpaper found in noctalia config, using environment fallback")
    }
  }

  // Main greeter interface
  WlSessionLock {
    id: sessionLock

    property string fakeBuffer: ""
    property string passwdBuffer: ""
    readonly property bool unlocking: Greetd.state == GreetdState.Authenticating

    locked: true

    WlSessionLockSurface {
      // Background with wallpaper and gradient overlay
      Rectangle {
        anchors.fill: parent
        color: Color.mSurface

        // Wallpaper - prioritize noctalia config, fallback to environment variable
        Image {
          anchors.fill: parent
          source: root.noctaliaWallpaper || root.wallpaper_path
          fillMode: Image.PreserveAspectCrop
          visible: (root.noctaliaWallpaper || root.wallpaper_path) !== ""

          onStatusChanged: {
            if (status === Image.Error) {
              console.log("[ERROR] Failed to load wallpaper:", source)
            } else if (status === Image.Ready) {
              console.log("[INFO] Successfully loaded wallpaper:", source)
            }
          }
        }

        // Gradient overlay similar to your lockscreen
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop {
              color: Qt.rgba(0, 0, 0, 0.6)
              position: 0.0
            }
            GradientStop {
              color: Qt.rgba(0, 0, 0, 0.3)
              position: 0.3
            }
            GradientStop {
              color: Qt.rgba(0, 0, 0, 0.4)
              position: 0.7
            }
            GradientStop {
              color: Qt.rgba(0, 0, 0, 0.7)
              position: 1.0
            }
          }
        }

        // Animated particles like your lockscreen
        Repeater {
          model: 20
          Rectangle {
            width: Math.random() * 4 + 2
            height: width
            radius: width * 0.5
            color: Color.applyOpacity(Color.mPrimary, "4D")
            x: Math.random() * parent.width
            y: Math.random() * parent.height

            SequentialAnimation on opacity {
              loops: Animation.Infinite
              NumberAnimation {
                to: 0.8
                duration: 2000 + Math.random() * 3000
              }
              NumberAnimation {
                to: 0.1
                duration: 2000 + Math.random() * 3000
              }
            }
          }
        }
      }

      Item {
        anchors.fill: parent

        ColumnLayout {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: 80
          spacing: 40

          // Time and Date display
          Column {
            spacing: 10
            Layout.alignment: Qt.AlignHCenter

            Text {
              id: timeText
              text: Qt.formatDateTime(new Date(), "HH:mm")
              font.family: "DejaVu Sans"
              font.pointSize: 72
              font.weight: Font.Bold
              color: Color.mOnSurface
              horizontalAlignment: Text.AlignHCenter

              SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation {
                  to: 1.02
                  duration: 2000
                  easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                  to: 1.0
                  duration: 2000
                  easing.type: Easing.InOutQuad
                }
              }
            }

            Text {
              id: dateText
              text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
              font.family: "DejaVu Sans"
              font.pointSize: 24
              font.weight: Font.Light
              color: Color.mOnSurface
              horizontalAlignment: Text.AlignHCenter
              width: timeText.width
            }
          }

          // Centered circular avatar area
          Rectangle {
            width: 108
            height: 108
            radius: width * 0.5
            color: "transparent"
            border.color: Color.mPrimary
            border.width: 2
            anchors.horizontalCenter: parent.horizontalCenter
            z: 10

            Rectangle {
              anchors.centerIn: parent
              width: parent.width + 24
              height: parent.height + 24
              radius: width * 0.5
              color: "transparent"
              border.color: Color.applyOpacity(Color.mPrimary, "4D")
              border.width: 1
              z: -1
              visible: !sessionLock.unlocking

              SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation {
                  to: 1.1
                  duration: 1500
                  easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                  to: 1.0
                  duration: 1500
                  easing.type: Easing.InOutQuad
                }
              }
            }

            // User avatar - use noctalia avatar with circular shader, fallback to initial
            Rectangle {
              anchors.centerIn: parent
              width: 100
              height: 100
              radius: width * 0.5
              color: Color.mPrimary

              // Raw image used as texture source for the shader
              Image {
                id: avatarImage
                anchors.fill: parent
                source: GreeterSettings.noctaliaAvatarImage
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: false

                onStatusChanged: {
                  if (status === Image.Error && GreeterSettings.noctaliaAvatarImage) {
                    console.log("[WARN] Failed to load avatar image:", GreeterSettings.noctaliaAvatarImage)
                  } else if (status === Image.Ready) {
                    console.log("[INFO] Successfully loaded avatar image:", GreeterSettings.noctaliaAvatarImage)
                  }
                }
              }

              // Circular mask shader effect
              ShaderEffect {
                anchors.fill: parent
                visible: avatarImage.status === Image.Ready
                property var source: avatarImage
                property real imageOpacity: 1.0
                fragmentShader: Qt.resolvedUrl("./Shaders/qsb/circled_image.frag.qsb")
              }

              // Fallback to initial letter if no avatar image
              Text {
                anchors.centerIn: parent
                text: users.current_user.charAt(0).toUpperCase()
                font.pointSize: 36
                font.bold: true
                color: Color.mOnSurface
                visible: avatarImage.status !== Image.Ready
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: parent.scale = 1.05
              onExited: parent.scale = 1.0
              onClicked: users.next()
            }

            Behavior on scale {
              NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
              }
            }
          }

          // Session selector below avatar
          Rectangle {
            height: 40
            radius: 20
            color: "transparent"
            border.color: Color.mPrimary
            border.width: 1
            anchors.horizontalCenter: parent.horizontalCenter

            // Make width depend on text length
            width: Math.max(180, sessionNameText.paintedWidth + 40)

            Text {
              id: sessionNameText
              anchors.centerIn: parent
              text: sessions.current_session_name.replace(/\(|\)/g, "")
              color: Color.mOnSurface
              font.pointSize: 16
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                sessions.next()
                // Persist selection (use identifier from exec or sanitized name)
                const ident = sessions.current_session.split(" ")[0]
                GreeterSettings.setLastSessionId(ident || sessions.current_session_name)
              }
            }
          }
        }

        // Terminal-style input area
        Rectangle {
          id: terminalBackground
          width: 720
          height: 280
          anchors.centerIn: parent
          anchors.verticalCenterOffset: 50
          radius: 20
          color: Color.applyOpacity(Color.mSurface, "E6")
          border.color: Color.mPrimary
          border.width: 2

          // Terminal scanlines effect
          Repeater {
            model: 20
            Rectangle {
              width: parent.width
              height: 1
              color: Color.applyOpacity(Color.mPrimary, "1A")
              y: index * 10
              opacity: 0.3
              SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation {
                  to: 0.6
                  duration: 2000 + Math.random() * 1000
                }
                NumberAnimation {
                  to: 0.1
                  duration: 2000 + Math.random() * 1000
                }
              }
            }
          }

          // Terminal header
          Rectangle {
            width: parent.width
            height: 40
            color: Color.applyOpacity(Color.mPrimary, "33")
            topLeftRadius: 18
            topRightRadius: 18

            RowLayout {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 10

              Text {
                text: "SECURE TERMINAL"
                color: Color.mOnSurface
                font.family: "DejaVu Sans Mono"
                font.pointSize: 14
                font.weight: Font.Bold
                Layout.fillWidth: true
              }

              Text {
                text: "USER: " + users.current_user
                color: Color.mOnSurface
                font.family: "DejaVu Sans Mono"
                font.pointSize: 12
              }
            }
          }

          // Terminal content
          ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            anchors.topMargin: 55
            spacing: 15

            RowLayout {
              Layout.fillWidth: true
              spacing: 10

              Text {
                text: users.current_user + "@noctalia:~$"
                color: Color.mPrimary
                font.family: "DejaVu Sans Mono"
                font.pointSize: 16
                font.weight: Font.Bold
              }

              Text {
                text: "sudo start-session"
                color: Color.mOnSurface
                font.family: "DejaVu Sans Mono"
                font.pointSize: 16
              }

              // Visible password input (terminal style)
              TextInput {
                id: terminalPassword
                color: Color.mOnSurface
                font.family: "DejaVu Sans Mono"
                font.pointSize: 16
                echoMode: TextInput.Password
                passwordCharacter: "*"
                passwordMaskDelay: 0
                focus: true
                text: sessionLock.passwdBuffer
                // Size to content for terminal look
                width: Math.max(1, contentWidth)
                selectByMouse: false

                Component.onCompleted: terminalPassword.forceActiveFocus()

                onTextChanged: sessionLock.passwdBuffer = text

                Keys.onPressed: kevent => {
                  if (kevent.key === Qt.Key_Enter || kevent.key === Qt.Key_Return) {
                    if (Greetd.state == GreetdState.Inactive) {
                      root.authenticate()
                      kevent.accepted = true
                    }
                  } else if (kevent.key === Qt.Key_Escape) {
                    sessionLock.passwdBuffer = ""
                    terminalPassword.text = ""
                    kevent.accepted = true
                  }
                }
              }
            }

            Text {
              text: sessionLock.unlocking ? "Authenticating..." : ""
              color: sessionLock.unlocking ? Color.mPrimary : "transparent"
              font.family: "DejaVu Sans Mono"
              font.pointSize: 16
              Layout.fillWidth: true

              SequentialAnimation on opacity {
                running: sessionLock.unlocking
                loops: Animation.Infinite
                NumberAnimation {
                  to: 1.0
                  duration: 800
                }
                NumberAnimation {
                  to: 0.5
                  duration: 800
                }
              }
            }

            // Execute button
            Rectangle {
              width: 120
              height: 40
              radius: 10
              color: executeButtonArea.containsMouse ? Color.mPrimary : Color.applyOpacity(Color.mPrimary, "33")
              border.color: Color.mPrimary
              border.width: 1
              enabled: !sessionLock.unlocking
              Layout.alignment: Qt.AlignRight
              Layout.bottomMargin: -10

              Text {
                anchors.centerIn: parent
                text: sessionLock.unlocking ? "EXECUTING" : "EXECUTE"
                color: executeButtonArea.containsMouse ? Color.mOnSurface : Color.mPrimary
                font.family: "DejaVu Sans Mono"
                font.pointSize: 14
                font.weight: Font.Bold
              }

              MouseArea {
                id: executeButtonArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.authenticate()

                SequentialAnimation on scale {
                  running: executeButtonArea.containsMouse
                  NumberAnimation {
                    to: 1.05
                    duration: 200
                    easing.type: Easing.OutCubic
                  }
                }

                SequentialAnimation on scale {
                  running: !executeButtonArea.containsMouse
                  NumberAnimation {
                    to: 1.0
                    duration: 200
                    easing.type: Easing.OutCubic
                  }
                }
              }

              SequentialAnimation on scale {
                loops: Animation.Infinite
                running: sessionLock.unlocking
                NumberAnimation {
                  to: 1.02
                  duration: 600
                  easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                  to: 1.0
                  duration: 600
                  easing.type: Easing.InOutQuad
                }
              }
            }
          }

          // Terminal border glow
          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: Color.applyOpacity(Color.mPrimary, "4D")
            border.width: 1
            z: -1

            SequentialAnimation on opacity {
              loops: Animation.Infinite
              NumberAnimation {
                to: 0.6
                duration: 2000
                easing.type: Easing.InOutQuad
              }
              NumberAnimation {
                to: 0.2
                duration: 2000
                easing.type: Easing.InOutQuad
              }
            }
          }
        }

        // Power buttons at bottom right
        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 50
          spacing: 20

          Rectangle {
            width: 60
            height: 60
            radius: width * 0.5
            color: powerButtonArea.containsMouse ? Color.mError : Color.applyOpacity(Color.mError, "33")
            border.color: Color.mError
            border.width: 2

            Text {
              anchors.centerIn: parent
              text: "⏻"
              font.pointSize: 24
              color: powerButtonArea.containsMouse ? Color.mOnSurface : Color.mError
            }

            MouseArea {
              id: powerButtonArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                console.log("Power off clicked")
              }
            }
          }

          Rectangle {
            width: 60
            height: 60
            radius: width * 0.5
            color: restartButtonArea.containsMouse ? Color.mPrimary : Color.applyOpacity(Color.mPrimary, "33")
            border.color: Color.mPrimary
            border.width: 2

            Text {
              anchors.centerIn: parent
              text: "↻"
              font.pointSize: 24
              color: restartButtonArea.containsMouse ? Color.mOnSurface : Color.mPrimary
            }

            MouseArea {
              id: restartButtonArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                console.log("Reboot clicked")
              }
            }
          }

          Rectangle {
            width: 60
            height: 60
            radius: width * 0.5
            color: suspendButtonArea.containsMouse ? Color.mSecondary : Color.applyOpacity(Color.mSecondary, "33")
            border.color: Color.mSecondary
            border.width: 2

            Text {
              anchors.centerIn: parent
              text: "💤"
              font.pointSize: 20
              color: suspendButtonArea.containsMouse ? Color.mOnSurface : Color.mSecondary
            }

            MouseArea {
              id: suspendButtonArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                console.log("Suspend clicked")
              }
            }
          }
        }
      }

      // Hidden password input (keeps key handling consistent)
      TextInput {
        id: passwordInput
        width: 0
        height: 0
        visible: false
        focus: true
        echoMode: TextInput.Password
        text: sessionLock.passwdBuffer

        onTextChanged: {
          sessionLock.passwdBuffer = text
        }

        Component.onCompleted: {
          passwordInput.forceActiveFocus()
        }

        Keys.onPressed: kevent => {
          if (kevent.key === Qt.Key_Enter || kevent.key === Qt.Key_Return) {
            if (Greetd.state == GreetdState.Inactive) {
              root.authenticate()
            }
            kevent.accepted = true
          }
        }
      }
    }
  }

  // Greetd connections
  Connections {
    target: Greetd

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      console.log("[GREETD] msg='" + message + "' err='" + error + "' resreq=" + responseRequired + " echo=" + echoResponse)

      if (responseRequired) {
        Greetd.respond(sessionLock.passwdBuffer)
        sessionLock.passwdBuffer = ""
        sessionLock.fakeBuffer = ""
        return
      }

      // Finger print support
      Greetd.respond("")
    }

    function onReadyToLaunch() {
      sessionLock.locked = false
      console.log("[GREETD EXEC] " + sessions.current_session)
      // Let greetd handle quitting to avoid compositor handoff glitches
      Greetd.launch(sessions.current_session.split(" "), [], true)
    }
  }

  // User management process
  Process {
    id: users

    property string current_user: users_list[current_user_index] ?? ""
    property int current_user_index: 0
    property list<string> users_list: []

    function next() {
      current_user_index = (current_user_index + 1) % users_list.length
    }

    command: ["awk", `BEGIN { FS = ":"} /\\/home/ { print $1 }`, "/etc/passwd"]
    running: true

    stderr: SplitParser {
      onRead: data => console.log("[ERR] " + data)
    }
    stdout: SplitParser {
      onRead: data => {
        console.log("[USERS] " + data)
        if (data == root.preferred_user) {
          console.log("[INFO] Found preferred user " + root.preferred_user)
          users.current_user_index = users.users_list.length
        }
        users.users_list.push(data)
      }
    }

    onExited: if (root.instant_auth && !users.running) {
      console.log("[USERS EXIT]")
      root.authenticate()
    }
  }

  // Session management process
  Process {
    id: sessions

    property int current_ses_index: 0
    property string current_session: session_execs[current_ses_index] ?? "hyprland"
    property string current_session_name: session_names[current_ses_index] ?? "Hyprland"
    property list<string> session_execs: []
    property list<string> session_names: []
    property bool restoredFromSettings: false

    function next() {
      current_ses_index = (current_ses_index + 1) % session_execs.length
    }

    function moveToFront(index) {
      if (index <= 0 || index >= session_execs.length)
        return
      const exec = session_execs[index]
      const name = session_names[index]
      session_execs.splice(index, 1)
      session_names.splice(index, 1)
      session_execs.unshift(exec)
      session_names.unshift(name)
      current_ses_index = 0
    }

    command: [Qt.resolvedUrl("./scripts/session.sh"), root.sessions]
    running: true

    stderr: SplitParser {
      onRead: data => console.log("[ERR] " + data)
    }
    stdout: SplitParser {
      onRead: data => {
        const parsedData = data.split(",")
        console.log("[SESSIONS] " + parsedData[2])
        if (parsedData[0] == root.preferred_session) {
          console.log("[INFO] Found preferred session " + root.preferred_session)
          sessions.current_ses_index = sessions.session_names.length
        }
        sessions.session_names.push(parsedData[1])
        sessions.session_execs.push(parsedData[2])
      }
    }

    onExited: {
      // After sessions populated, prefer saved session as first entry
      if (!restoredFromSettings && GreeterSettings.lastSessionId && session_execs.length > 0) {
        const saved = GreeterSettings.lastSessionId.toLowerCase()
        let idx = -1
        for (var i = 0; i < session_execs.length; i++) {
          if (session_execs[i].toLowerCase().includes(saved) || session_names[i].toLowerCase().includes(saved)) {
            idx = i
            break
          }
        }
        if (idx >= 0) {
          moveToFront(idx)
          restoredFromSettings = true
        }
      }

      if (root.instant_auth && !users.running) {
        console.log("[SESSIONS EXIT]")
        root.authenticate()
      }
    }
  }

  // Timer to update time
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (typeof timeText !== 'undefined' && timeText) {
        timeText.text = Qt.formatDateTime(new Date(), "HH:mm")
      }
      if (typeof dateText !== 'undefined' && dateText) {
        dateText.text = Qt.formatDateTime(new Date(), "dddd, MMMM d")
      }
    }
  }
}
