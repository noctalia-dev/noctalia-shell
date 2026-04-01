pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Location and weather service with decoupled geocoding and weather fetching.
Singleton {
  id: root

  property string locationFile: Quickshell.env("NOCTALIA_WEATHER_FILE") || (Settings.cacheDir + "location.json")
  property int weatherUpdateFrequency: 30 * 60
  property bool isFetchingWeather: false

  // Talia weather
  readonly property int taliaMascotWeatherMonth: 3
  readonly property int taliaMascotWeatherDay: 1

  readonly property bool taliaWeatherMascotDayActive: {
    const d = Time.now;
    return d.getMonth() === root.taliaMascotWeatherMonth && d.getDate() === root.taliaMascotWeatherDay;
  }

  readonly property alias data: adapter

  // Stable UI properties - only updated when location is successfully geocoded
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
      Logger.d("Location", "Loaded cached data");
      if (adapter.latitude !== "" && adapter.longitude !== "" && adapter.weatherLastFetch > 0) {
        root.stableLatitude = adapter.latitude;
        root.stableLongitude = adapter.longitude;
        root.stableName = adapter.name;
        root.coordinatesReady = true;
        Logger.i("Location", "Coordinates ready");
      }
      update();
    }
    onLoadFailed: function (error) {
      update();
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

  // Formatted coordinates for UI display
  readonly property string displayCoordinates: {
    if (!root.coordinatesReady || root.stableLatitude === "" || root.stableLongitude === "") {
      return "";
    }
    const lat = parseFloat(root.stableLatitude).toFixed(4);
    const lon = parseFloat(root.stableLongitude).toFixed(4);
    return `${lat}, ${lon}`;
  }

  // Auto-geolocate timer - periodically updates location via IP geolocation
  Timer {
    id: autoLocateTimer
    interval: 30 * 60 * 1000
    running: Settings.data.location.autoLocate
    repeat: true
    triggeredOnStart: true
    onTriggered: root.geolocateAndApply()
  }

  // Update timer runs when weather is enabled or location-based scheduling is active
  Timer {
    id: updateTimer
    interval: 20 * 1000
    running: Settings.data.location.weatherEnabled || Settings.data.colorSchemes.schedulingMode == "location"
    repeat: true
    onTriggered: {
      update();
    }
  }

  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: locationFileView.writeAdapter()
  }

  function init() {
    Logger.i("Location", "Service started");
  }

  function resetWeather() {
    Logger.i("Location", "Resetting location and weather data");

    root.coordinatesReady = false;
    root.stableLatitude = "";
    root.stableLongitude = "";
    root.stableName = "";

    adapter.latitude = "";
    adapter.longitude = "";
    adapter.name = "";
    adapter.weatherLastFetch = 0;
    adapter.weather = null;
    update();
  }

  // Main update function - geocodes location if needed, then fetches weather if enabled
  function update() {
    updateLocation();

    if (Settings.data.location.weatherEnabled) {
      updateWeatherData();
    }
  }

  // Runs independently of weather toggle
  function updateLocation() {
    const locationChanged = adapter.name !== Settings.data.location.name;
    const needsGeocoding = (adapter.latitude === "") || (adapter.longitude === "") || locationChanged;

    if (!needsGeocoding) {
      return;
    }

    if (isFetchingWeather) {
      return;
    }

    isFetchingWeather = true;

    if (locationChanged) {
      root.coordinatesReady = false;
      Logger.d("Location", "Location changed from", adapter.name, "to", Settings.data.location.name);
    }

    geocodeLocation(Settings.data.location.name, function (latitude, longitude, name, country) {
      Logger.d("Location", "Geocoded", Settings.data.location.name, "to:", latitude, "/", longitude);

      adapter.name = Settings.data.location.name;
      adapter.latitude = latitude.toString();
      adapter.longitude = longitude.toString();
      root.stableLatitude = adapter.latitude;
      root.stableLongitude = adapter.longitude;
      root.stableName = `${name}, ${country}`;
      root.coordinatesReady = true;

      isFetchingWeather = false;
      Logger.i("Location", "Coordinates ready");

      if (locationChanged) {
        adapter.weatherLastFetch = 0;
        updateWeatherData();
      }
    }, errorCallback);
  }

  // Fetch weather data if enabled and coordinates are available
  function updateWeatherData() {
    if (!Settings.data.location.weatherEnabled) {
      return;
    }

    if (isFetchingWeather) {
      return;
    }

    if (adapter.latitude === "" || adapter.longitude === "") {
      Logger.w("Location", "Cannot fetch weather without coordinates");
      return;
    }
    const needsWeatherUpdate = (adapter.weatherLastFetch === "") || (adapter.weather === null) || (Time.timestamp >= adapter.weatherLastFetch + weatherUpdateFrequency);

    if (needsWeatherUpdate) {
      isFetchingWeather = true;
      fetchWeatherData(adapter.latitude, adapter.longitude, errorCallback);
    }
  }

  // Query geocoding API to convert location name to coordinates
  function geocodeLocation(locationName, callback, errorCallback) {
    if (locationName === "") {
      isFetchingWeather = false;
      return;
    }

    Logger.d("Location", "Geocoding location name");
    var geoUrl = "https://api.noctalia.dev/geocode?city=" + encodeURIComponent(locationName);
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var geoData = JSON.parse(xhr.responseText);
            if (geoData.lat != null) {
              callback(geoData.lat, geoData.lng, geoData.name, geoData.country);
            } else {
              errorCallback("Location", "could not resolve location name");
            }
          } catch (e) {
            errorCallback("Location", "Failed to parse geocoding data: " + e);
          }
        } else {
          errorCallback("Location", "Geocoding error: " + xhr.status);
        }
      }
    };
    xhr.open("GET", geoUrl);
    xhr.send();
  }

  // Fetch weather data from Open-Meteo API
  function fetchWeatherData(latitude, longitude, errorCallback) {
    Logger.d("Location", "Fetching weather from api.open-meteo.com");
    var url = "https://api.open-meteo.com/v1/forecast?latitude=" + latitude + "&longitude=" + longitude + "&current_weather=true&current=relativehumidity_2m,surface_pressure,is_day&daily=temperature_2m_max,temperature_2m_min,weathercode,sunset,sunrise&timezone=auto";
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var weatherData = JSON.parse(xhr.responseText);
            //console.log(JSON.stringify(weatherData))

            // Save core data
            data.weather = weatherData;
            data.weatherLastFetch = Time.timestamp;

            // Update stable display values only when complete and successful
            root.stableLatitude = data.latitude = weatherData.latitude.toString();
            root.stableLongitude = data.longitude = weatherData.longitude.toString();
            root.coordinatesReady = true;

            isFetchingWeather = false;
            Logger.d("Location", "Cached weather to disk - stable coordinates updated");
          } catch (e) {
            errorCallback("Location", "Failed to parse weather data");
          }
        } else {
          errorCallback("Location", "Weather fetch error: " + xhr.status);
        }
      }
    };
    xhr.open("GET", url);
    xhr.send();
  }

  // Geolocate via IP address using the Noctalia API
  function geolocate(callback, errorCallback) {
    Logger.d("Location", "Geolocating via IP");
    var url = "https://api.noctalia.dev/geolocate";
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var data = JSON.parse(xhr.responseText);
            if (data.lat != null) {
              callback(data.lat, data.lng, data.city, data.country);
            } else {
              errorCallback("Location", "Geolocate: no coordinates returned");
            }
          } catch (e) {
            errorCallback("Location", "Failed to parse geolocate data: " + e);
          }
        } else {
          errorCallback("Location", "Geolocate error: " + xhr.status);
        }
      }
    };
    xhr.open("GET", url);
    xhr.send();
  }

  // Geolocate via IP and apply the result as the current location
  function geolocateAndApply() {
    if (isFetchingWeather) {
      Logger.w("Location", "Geolocate skipped, fetch already in progress");
      return;
    }
    geolocate(function (lat, lng, city, country) {
      Logger.i("Location", "Geolocated to", city + ",", country);
      Settings.data.location.name = city;
      resetWeather();
    }, errorCallback);
  }

  // --------------------------------
  function errorCallback(module, message) {
    Logger.e(module, message);
    isFetchingWeather = false;
  }

  // --------------------------------
  function weatherSymbolFromCode(code, isDay) {
    if (code === 0)
      return isDay ? "weather-sun" : "weather-moon";
    if (code === 1 || code === 2)
      return isDay ? "weather-cloud-sun" : "weather-moon-stars";
    if (code === 3)
      return "weather-cloud";
    if (code >= 45 && code <= 48)
      return "weather-cloud-haze";
    if (code >= 51 && code <= 67)
      return "weather-cloud-rain";
    if (code >= 80 && code <= 82)
      return "weather-cloud-rain";
    if (code >= 71 && code <= 77)
      return "weather-cloud-snow";
    if (code >= 71 && code <= 77)
      return "weather-cloud-snow";
    if (code >= 85 && code <= 86)
      return "weather-cloud-snow";
    if (code >= 95 && code <= 99)
      return "weather-cloud-lightning";
    return "weather-cloud";
  }

  // --------------------------------
  function taliaWeatherImageFromCode(code, isDay) {
    if (code >= 40 && code <= 49)
      return Quickshell.shellDir + "/Assets/Talia/TaliaDazed.png";
    if (code >= 95 && code <= 99)
      return Quickshell.shellDir + "/Assets/Talia/TaliaFear.png";
    var wet = (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || (code >= 71 && code <= 77) || (code >= 85 && code <= 86);
    if (wet)
      return Quickshell.shellDir + "/Assets/Talia/TaliaSob.png";
    if ((code === 0 || code === 1 || code === 2) && isDay === false)
      return Quickshell.shellDir + "/Assets/Talia/TaliaVampire.png";
    if ((code === 0 && isDay === true) || code === 1 || code === 2)
      return Quickshell.shellDir + "/Assets/Talia/TaliaParty.png";
    return Quickshell.shellDir + "/Assets/Talia/TaliaBlank.png";
  }

  // --------------------------------
  function weatherDescriptionFromCode(code) {
    if (code === 0)
      return "Clear sky";
    if (code === 1)
      return "Mainly clear";
    if (code === 2)
      return "Partly cloudy";
    if (code === 3)
      return "Overcast";
    if (code === 45 || code === 48)
      return "Fog";
    if (code >= 51 && code <= 67)
      return "Drizzle";
    if (code >= 71 && code <= 77)
      return "Snow";
    if (code >= 80 && code <= 82)
      return "Rain showers";
    if (code >= 95 && code <= 99)
      return "Thunderstorm";
    return "Unknown";
  }

  // --------------------------------
  function celsiusToFahrenheit(celsius) {
    return 32 + celsius * 1.8;
  }
}
