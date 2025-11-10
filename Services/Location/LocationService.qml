pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Weather logic and caching with stable UI properties
Singleton {
  id: root

  property string locationFile: Quickshell.env("NOCTALIA_WEATHER_FILE") || (Settings.cacheDir + "location.json")
  property int weatherUpdateFrequency: 30 * 60 // 30 minutes expressed in seconds
  property bool isFetchingWeather: false

  readonly property alias data: adapter // Used to access via LocationService.data.xxx from outside, best to use "adapter" inside the service.

  // Stable UI properties - only updated when location is fully resolved
  property bool coordinatesReady: false
  property string stableLatitude: ""
  property string stableLongitude: ""
  property string stableName: ""

  FileView {
    id: locationFileView
    path: locationFile
    printErrors: false
    onAdapterUpdated: saveTimer.start()
    onLoaded: {
      Logger.d("Location", "Loaded cached data")
      // Initialize stable properties on load
      if (adapter.latitude !== "" && adapter.longitude !== "" && adapter.weatherLastFetch > 0) {
        root.stableLatitude = adapter.latitude
        root.stableLongitude = adapter.longitude
        root.stableName = adapter.name
        root.coordinatesReady = true
        Logger.i("Location", "Coordinates ready")
      }
      updateWeather()
    }
    onLoadFailed: function (error) {
      updateWeather()
    }

    JsonAdapter {
      id: adapter

      // Core data properties
      property string latitude: ""
      property string longitude: ""
      property string name: ""
      property int weatherLastFetch: 0
      property var weather: null
    }
  }

  // Helper property for UI components (outside JsonAdapter to avoid binding loops)
  readonly property string displayCoordinates: {
    if (!root.coordinatesReady || root.stableLatitude === "" || root.stableLongitude === "") {
      return ""
    }
    const lat = parseFloat(root.stableLatitude).toFixed(4)
    const lon = parseFloat(root.stableLongitude).toFixed(4)
    return `${lat}, ${lon}`
  }

  // Every 20s check if we need to fetch new weather
  Timer {
    id: updateTimer
    interval: 20 * 1000
    running: Settings.data.location.weatherEnabled || Settings.data.colorSchemes.schedulingMode == "location"
    repeat: true
    onTriggered: {
      updateWeather()
    }
  }

  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: locationFileView.writeAdapter()
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.i("Location", "Service started")
  }

  // --------------------------------
  function resetWeather() {
    Logger.i("Location", "Resetting weather data")

    // Mark as changing to prevent UI updates
    root.coordinatesReady = false
    // Reset stable properties
    root.stableLatitude = ""
    root.stableLongitude = ""
    root.stableName = ""

    // Reset core data
    adapter.latitude = ""
    adapter.longitude = ""
    adapter.name = ""
    adapter.weatherLastFetch = 0
    adapter.weather = null

    // Try to fetch immediately
    updateWeather()
  }

  // --------------------------------
  function updateWeather() {
    if (!Settings.data.location.weatherEnabled) {
      return
    }

    if (isFetchingWeather) {
      Logger.w("Location", "Weather is still fetching")
      return
    }

    if ((adapter.weatherLastFetch === "") || (adapter.weather === null) || (adapter.latitude === "") || (adapter.longitude === "") || (adapter.name !== Settings.data.location.name) || (Time.timestamp >= adapter.weatherLastFetch + weatherUpdateFrequency)) {
      getFreshWeather()
    }
  }

  // --------------------------------
  function getFreshWeather() {
    isFetchingWeather = true

    // Check if location name has changed
    const locationChanged = data.name !== Settings.data.location.name
    if (locationChanged) {
      root.coordinatesReady = false
      Logger.d("Location", "Location changed from", adapter.name, "to", Settings.data.location.name)
    }

    if ((adapter.latitude === "") || (adapter.longitude === "") || locationChanged) {

      _geocodeLocation(Settings.data.location.name, function (latitude, longitude, name, country) {
        Logger.d("Location", "Geocoded", Settings.data.location.name, "to:", latitude, "/", longitude)

        // Save location name
        adapter.name = Settings.data.location.name

        // Save GPS coordinates
        adapter.latitude = latitude.toString()
        adapter.longitude = longitude.toString()

        root.stableName = `${name}, ${country}`

        _fetchWeather(latitude, longitude, errorCallback)
      }, errorCallback)
    } else {
      _fetchWeather(adapter.latitude, adapter.longitude, errorCallback)
    }
  }

  // --------------------------------
  function _geocodeLocation(locationName, callback, errorCallback) {
    Logger.d("Location", "Geocoding location name")
    var geoUrl = "https://assets.noctalia.dev/geocode.php?city=" + encodeURIComponent(locationName) + "&language=en&format=json"
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var geoData = JSON.parse(xhr.responseText)
            if (geoData.lat != null) {
              callback(geoData.lat, geoData.lng, geoData.name, geoData.country)
            } else {
              errorCallback("Location", "could not resolve location name")
            }
          } catch (e) {
            errorCallback("Location", "Failed to parse geocoding data: " + e)
          }
        } else {
          errorCallback("Location", "Geocoding error: " + xhr.status)
        }
      }
    }
    xhr.open("GET", geoUrl)
    xhr.send()
  }

  // --------------------------------
  function _fetchWeather(latitude, longitude, errorCallback) {
    Logger.d("Location", "Fetching weather from api.open-meteo.com")
    var url = "https://api.open-meteo.com/v1/forecast?latitude=" + latitude + "&longitude=" + longitude + "&current_weather=true&current=relativehumidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode,sunset,sunrise&timezone=auto"
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var weatherData = JSON.parse(xhr.responseText)
            //console.log(JSON.stringify(weatherData))

            // Save core data
            data.weather = weatherData
            data.weatherLastFetch = Time.timestamp

            // Update stable display values only when complete and successful
            root.stableLatitude = data.latitude = weatherData.latitude.toString()
            root.stableLongitude = data.longitude = weatherData.longitude.toString()
            root.coordinatesReady = true

            isFetchingWeather = false
            Logger.i("Location", "Cached weather to disk - stable coordinates updated")
          } catch (e) {
            errorCallback("Location", "Failed to parse weather data")
          }
        } else {
          errorCallback("Location", "Weather fetch error: " + xhr.status)
        }
      }
    }
    xhr.open("GET", url)
    xhr.send()
  }

  // --------------------------------
  function errorCallback(module, message) {
    Logger.e(module, message)
    isFetchingWeather = false
  }

  // --------------------------------
  function weatherSymbolFromCode(code) {
    if (code === 0)
      return "weather-sun"
    if (code === 1 || code === 2)
      return "weather-cloud-sun"
    if (code === 3)
      return "weather-cloud"
    if (code >= 45 && code <= 48)
      return "weather-cloud-haze"
    if (code >= 51 && code <= 67)
      return "weather-cloud-rain"
    if (code >= 71 && code <= 77)
      return "weather-cloud-snow"
    if (code >= 71 && code <= 77)
      return "weather-cloud-snow"
    if (code >= 85 && code <= 86)
      return "weather-cloud-snow"
    if (code >= 95 && code <= 99)
      return "weather-cloud-lightning"
    return "weather-cloud"
  }

  // --------------------------------
  function weatherDescriptionFromCode(code) {
    if (code === 0)
      return "Clear sky"
    if (code === 1)
      return "Mainly clear"
    if (code === 2)
      return "Partly cloudy"
    if (code === 3)
      return "Overcast"
    if (code === 45 || code === 48)
      return "Fog"
    if (code >= 51 && code <= 67)
      return "Drizzle"
    if (code >= 71 && code <= 77)
      return "Snow"
    if (code >= 80 && code <= 82)
      return "Rain showers"
    if (code >= 95 && code <= 99)
      return "Thunderstorm"
    return "Unknown"
  }

  // --------------------------------
  function celsiusToFahrenheit(celsius) {
    return 32 + celsius * 1.8
  }
}
