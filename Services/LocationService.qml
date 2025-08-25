pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

// Weather logic and caching
Singleton {
  id: root

  property string locationFile: Quickshell.env("NOCTALIA_WEATHER_FILE") || (Settings.cacheDir + "location.json")
  property int weatherUpdateFrequency: 30 * 60 // 30 minutes expressed in seconds
  property bool isFetchingWeather: false
  property alias data: adapter // Used to access via LocationService.data.xxx

  FileView {
    path: locationFile
    onAdapterUpdated: writeAdapter()
    onLoaded: {
      updateWeather()
    }
    onLoadFailed: function (error) {
      updateWeather()
    }

    JsonAdapter {
      id: adapter

      property string latitude: ""
      property string longitude: ""
      property string name: ""
      property int weatherLastFetch: 0
      property var weather: null
    }
  }

  // Every 20s check if we need to fetch new weather
  Timer {
    id: updateTimer
    interval: 20 * 1000
    running: true
    repeat: true
    onTriggered: {
      updateWeather()
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.log("Location", "Service started")
  }

  // --------------------------------
  function resetWeather() {
    Logger.log("Location", "Resetting weather data")

    data.latitude = ""
    data.longitude = ""
    data.name = ""
    data.weatherLastFetch = 0
    data.weather = null

    // Try to fetch immediately
    updateWeather()
  }

  // --------------------------------
  function updateWeather() {
    if (isFetchingWeather) {
      Logger.warn("Location", "Weather is still fetching")
      return
    }

    if (data.latitude === "") {
      Logger.warn("Location", "Why is my latitude empty")
    }

    if ((data.weatherLastFetch === "") || (data.weather === null) || (data.latitude === "") || (data.longitude === "")
        || (data.name !== Settings.data.location.name)
        || (Time.timestamp >= data.weatherLastFetch + weatherUpdateFrequency)) {
      getFreshWeather()
    }
  }

  // --------------------------------
  function getFreshWeather() {
    isFetchingWeather = true
    if ((data.latitude === "") || (data.longitude === "") || (data.name !== Settings.data.location.name)) {

      _geocodeLocation(Settings.data.location.name, function (latitude, longitude) {
        Logger.log("Location", "Geocoded", Settings.data.location.name, "to:", latitude, "/", longitude)

        // Save location name
        data.name = Settings.data.location.name

        // Save GPS coordinates
        data.latitude = latitude.toString()
        data.longitude = longitude.toString()

        _fetchWeather(latitude, longitude, errorCallback)
      }, errorCallback)
    } else {
      _fetchWeather(data.latitude, data.longitude, errorCallback)
    }
  }

  // --------------------------------
  function _geocodeLocation(locationName, callback, errorCallback) {
    Logger.log("Location", "Geocoding location name")
    var geoUrl = "https://assets.noctalia.dev/geocode.php?city=" + encodeURIComponent(
          locationName) + "&language=en&format=json"
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var geoData = JSON.parse(xhr.responseText)
            // Logger.logJSON.stringify(geoData))
            if (geoData.lat != null) {
              callback(geoData.lat, geoData.lng)
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
    Logger.log("Location", "Fetching weather from api.open-meteo.com")
    var url = "https://api.open-meteo.com/v1/forecast?latitude=" + latitude + "&longitude=" + longitude
        + "&current_weather=true&current=relativehumidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&timezone=auto"
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var weatherData = JSON.parse(xhr.responseText)

            // Save data
            data.weather = weatherData
            data.weatherLastFetch = Time.timestamp
            data.latitude = weatherData.latitude.toString()
            data.longitude = weatherData.longitude.toString()

            isFetchingWeather = false
            Logger.log("Location", "Cached weather to disk")
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
    Logger.error(module, message)
    isFetchingWeather = false
  }

  // --------------------------------
  function weatherSymbolFromCode(code) {
    if (code === 0)
      return "sunny"
    if (code === 1 || code === 2)
      return "partly_cloudy_day"
    if (code === 3)
      return "cloud"
    if (code >= 45 && code <= 48)
      return "foggy"
    if (code >= 51 && code <= 67)
      return "rainy"
    if (code >= 71 && code <= 77)
      return "weather_snowy"
    if (code >= 80 && code <= 82)
      return "rainy"
    if (code >= 95 && code <= 99)
      return "thunderstorm"
    return "cloud"
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
