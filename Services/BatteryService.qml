pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services

Singleton {
  id: root

  enum ChargingMode {
    Disabled = 0,
    Full,
    Balanced,
    Lifespan
  }

  property int chargingMode: Settings.data.battery.chargingMode
  readonly property string batterySetterScript: Quickshell.shellDir + '/Bin/battery-manager/set-battery-treshold.sh'
  readonly property string batteryInstallerScript: Quickshell.shellDir + '/Bin/battery-manager/install-battery-manager.sh'
  readonly property string batteryUninstallerScript: Quickshell.shellDir + '/Bin/battery-manager/uninstall-battery-manager.sh'

  // This is used to omit toast message and writing mode to settings on startup
  property bool initialSetter: true

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery-exclamation"
    }

    if (charging) {
      return "battery-charging"
    } else {
      if (percent >= 90)
        return "battery-4"
      if (percent >= 50)
        return "battery-3"
      if (percent >= 25)
        return "battery-2"
      if (percent >= 0)
        return "battery-1"
      return "battery"
    }
  }

  function getThresholdValue(chargingMode) {
    switch (chargingMode) {
    case BatteryService.ChargingMode.Full:
      return "100"
    case BatteryService.ChargingMode.Balanced:
      return "80"
    case BatteryService.ChargingMode.Lifespan:
      return "60"
    }
  }

  function toggleEnabled(enabled) {
    if (enabled) {
      setChargingMode(BatteryService.ChargingMode.Full)
    } else {
      BatteryService.initialSetter = true
      ToastService.showNotice(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.uninstall-setup"))
      PanelService.getPanel("batteryPanel")?.toggle(this)
      uninstallerProcess.running = true
    }
  }

  function setChargingMode(newMode) {
    if (newMode !== BatteryService.ChargingMode.Full && newMode !== BatteryService.ChargingMode.Balanced && newMode !== BatteryService.ChargingMode.Lifespan) {
      Logger.warn("BatteryService", `Invalid charging mode set ${newMode}`)
      return
    }
    BatteryService.chargingMode = newMode
    BatteryService.applyChargingMode()
  }

  function cycleModes() {
    // Cycles charging modes from full to lifespan while skipping disabled
    const nextMode = (chargingMode % 3) + 1
    setChargingMode(nextMode)
  }

  function applyChargingMode() {
    let command = [batterySetterScript]

    // Currently the script sends notifications by default but quickshell
    // uses toast messages so the flag is passed to supress notifs
    command.push("-q")

    command.push(BatteryService.getThresholdValue(BatteryService.chargingMode))

    setterProcess.command = command
    setterProcess.running = true
  }

  function runInstaller() {
    installerProcess.command = ["pkexec", batteryInstallerScript]
    installerProcess.running = true
  }

  function init() {
    if (BatteryService.chargingMode !== BatteryService.ChargingMode.Disabled && BatteryService.chargingMode !== BatteryService.ChargingMode.Full) {
      BatteryService.applyChargingMode()
    }
  }

  Process {
    id: setterProcess
    workingDirectory: Quickshell.shellDir
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        Logger.log("BatteryService", "Battery threshold set successfully")
        if (BatteryService.initialSetter) {
          BatteryService.initialSetter = false
          return
        }
        ToastService.showNotice(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.set-success-desc", {
                                                                                  "percent": BatteryService.getThresholdValue(BatteryService.chargingMode)
                                                                                }))
        Settings.data.battery.chargingMode = BatteryService.chargingMode
      } else if (exitCode === 2) {
        ToastService.showWarning(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.initial-setup"))
        PanelService.getPanel("batteryPanel")?.toggle(this)
        BatteryService.runInstaller()
      } else {
        ToastService.showError(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.set-failed"))
        Logger.error("BatteryService", `Setter process failed with exit code: ${exitCode}`)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "SetterProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "SetterProcess stdout:", this.text)
        }
      }
    }
  }

  // Installer process - installs battery manager components
  Process {
    id: installerProcess
    workingDirectory: Quickshell.shellDir
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        ToastService.showNotice(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.install-success"))
        BatteryService.applyChargingMode()
      } else if (exitCode === 2) {
        ToastService.showError(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.install-missing"))
      } else if (exitCode === 3) {
        ToastService.showError(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.install-unsupported"))
      } else {
        ToastService.showError(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.install-failed"))
      }

      if (exitCode !== 0) {
        BatteryService.chargingMode = BatteryService.ChargingMode.Disabled
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "InstallerProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "InstallerProcess stdout:", this.text)
        }
      }
    }
  }

  Process {
    id: uninstallerProcess
    workingDirectory: Quickshell.shellDir
    command: ["pkexec", batteryUninstallerScript]
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        Logger.log("BatteryService", "Battery Manager uninstalled successfully")
        ToastService.showNotice(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.uninstall-success"))
        Settings.data.battery.chargingMode = BatteryService.chargingMode
        BatteryService.chargingMode = BatteryService.ChargingMode.Disabled
        cleanupProcess.running = true
      } else {
        ToastService.showError(I18n.tr("toast.battery-manager.title"), I18n.tr("toast.battery-manager.uninstall-failed"))
        Logger.error("BatteryService", `Uninstaller process failed with exit code: ${exitCode}`)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "UninstallerProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "UninstallerProcess stdout:", this.text)
        }
      }
    }
  }

  // Cleanup process - deletes uninstaller after it sucessfull ;
  Process {
    id: cleanupProcess
    workingDirectory: Quickshell.shellDir
    command: ["rm", "-rf", batteryUninstallerScript]
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        Logger.log("BatteryService", "Battery Manager uninstalled successfully")
      } else {
        Logger.error("BatteryService", `Cleanup process failed with exit code: ${exitCode}`)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "CleanupProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "CleanupProcess stdout:", this.text)
        }
      }
    }
  }
}
