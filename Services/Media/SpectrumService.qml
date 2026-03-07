pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  function registerComponent(componentId) {
    root.registeredComponents[componentId] = true;
    root.registeredComponents = Object.assign({}, root.registeredComponents);
    Logger.d("Spectrum", "Component registered:", componentId, "- total:", root.registeredCount);
  }

  function unregisterComponent(componentId) {
    delete root.registeredComponents[componentId];
    root.registeredComponents = Object.assign({}, root.registeredComponents);
    Logger.d("Spectrum", "Component unregistered:", componentId, "- total:", root.registeredCount);
  }

  function isRegistered(componentId) {
    return root.registeredComponents[componentId] === true;
  }

  property var registeredComponents: ({})
  readonly property int registeredCount: Object.keys(registeredComponents).length
  property bool shouldRun: registeredCount > 0

  property var values: []
  property int barsCount: 32
  property bool isIdle: true

  PwAudioSpectrum {
    id: spectrum
    node: Pipewire.defaultAudioSink
    enabled: root.shouldRun
    barCount: root.barsCount
    frameRate: Settings.data.audio.spectrumFrameRate
    lowerCutoff: 50
    upperCutoff: 12000
    noiseReduction: 0.77
    smoothing: true

    onValuesChanged: {
      root.values = spectrum.values;
    }

    onIdleChanged: {
      root.isIdle = spectrum.idle;
    }
  }
}
