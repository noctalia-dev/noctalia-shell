pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Weather logic and caching
Singleton {
    id: root

    property string locationFile: Quickshell.env("NOCTALIA_WEATHER_FILE") || (Settings.cacheDir + "location.json")
    property int weatherUpdateFrequency: 30 * 60 // 30 minutes expressed in seconds
    property alias data: adapter // Used to access via LocationService.data.xxx
    property bool isFetchingWeather: false

    FileView {
        path: root.locationFile
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            root.updateWeather();
        }
        onLoadFailed: function (error) {
            root.updateWeather();
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
            root.updateWeather();
        }
    }

    // --------------------------------
    function init() {
        // does nothing but ensure the singleton is created
        // do not remove
        Logger.log("Location", "Service started");
    }

    // --------------------------------
    function resetWeather() {
        Logger.log("Location", "Resetting weather data");

        data.latitude = "";
        data.longitude = "";
        data.name = "";
        data.weatherLastFetch = 0;
        data.weather = null;

        // Try to fetch immediately
        updateWeather();
    }

    // --------------------------------
    function updateWeather() {
        if (isFetchingWeather) {
            Logger.warn("Location", "Weather is still fetching");
            return;
        }

        if (data.latitude === "") {
            Logger.warn("Location", "Why is my latitude empty");
        }

        if ((data.weatherLastFetch === "") || (data.weather === null) || (data.latitude === "") || (data.longitude === "") || (data.name !== Settings.data.location.name) || (Time.timestamp >= data.weatherLastFetch + weatherUpdateFrequency)) {
            getFreshWeather();
        }
    }

    // --------------------------------
    function getFreshWeather() {
        isFetchingWeather = true;

        console.log("Sync Location");

        let cityName = Settings.data.location.name;

        if (Settings.data.location.autoDetect) {
            findCurrentLocation().then(function ({
                    cityName,
                    latitude,
                    longitude
                }) {
                Logger.log("Location", "Geocoded", cityName, "to:", latitude, "/", longitude);

                // Save location name
                data.name = cityName;
                Settings.data.location.name = cityName;

                // Save GPS coordinates
                data.latitude = latitude.toString();
                data.longitude = longitude.toString();

                _fetchWeather(latitude, longitude);
            }).catch(errorCallback);
            return;
        }

        if ((data.latitude === "") || (data.longitude === "") || (data.name !== Settings.data.location.name)) {
            _geocodeLocation(cityName).then(function ({
                    latitude,
                    longitude
                }) {
                Logger.log("Location", "Geocoded", cityName, "to:", latitude, "/", longitude);

                // Save location name
                data.name = cityName;

                // Save GPS coordinates
                data.latitude = latitude.toString();
                data.longitude = longitude.toString();

                _fetchWeather(latitude, longitude);
            }).catch(errorCallback);
            return;
        }

        _fetchWeather(data.latitude, data.longitude);
    }

    // --------------------------------
    function _geocodeLocation(locationName) {
        return new Promise(function (resolve, reject) {
            Logger.log("Location", "Geocoding from api.open-meteo.com");
            const geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(locationName) + "&language=en&format=json";
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const geoData = JSON.parse(xhr.responseText);
                            // Logger.logJSON.stringify(geoData))
                            if (geoData.results && geoData.results.length > 0) {
                                resolve({
                                    latitude: geoData.results[0].latitude,
                                    longitude: geoData.results[0].longitude
                                });
                            } else {
                                reject("Geocoding: could not resolve location name");
                            }
                        } catch (e) {
                            reject("Failed to parse geocoding data: " + e);
                        }
                    } else {
                        reject("Geocoding error: " + xhr.status);
                    }
                }
            };
            xhr.open("GET", geoUrl);
            xhr.send();
        });
    }

    // --------------------------------
    function findCurrentLocation() {
        return new Promise(function (resolve, reject) {
            Logger.log("Location", "Detecting location via ipapi.co");
            const url = "https://ipapi.co/json/";
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            var resp = JSON.parse(xhr.responseText);
                            if (resp && resp.latitude !== undefined && resp.longitude !== undefined) {
                                resolve({
                                    cityName: resp.city,
                                    latitude: resp.latitude,
                                    longitude: resp.longitude
                                });
                            } else {
                                reject("IP geolocation: missing coordinates");
                            }
                        } catch (e) {
                            reject("Failed to parse IP geolocation data: " + e);
                        }
                    } else {
                        reject("IP geolocation error: " + xhr.status);
                    }
                }
            };
            xhr.open("GET", url);
            xhr.send();
        });
    }

    // --------------------------------
    function _fetchWeather(latitude, longitude) {
        return new Promise(function (resolve, reject) {
            Logger.log("Location", "Fetching weather from api.open-meteo.com");
            const url = "https://api.open-meteo.com/v1/forecast?latitude=" + latitude + "&longitude=" + longitude + "&current_weather=true&current=relativehumidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&timezone=auto";
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const weatherData = JSON.parse(xhr.responseText);
                            // Save data
                            data.weather = weatherData;
                            data.weatherLastFetch = Time.timestamp;
                            data.latitude = weatherData.latitude.toString();
                            data.longitude = weatherData.longitude.toString();

                            isFetchingWeather = false;
                            Logger.log("Location", "Cached weather to disk");
                            resolve(weatherData);
                        } catch (e) {
                            reject("Failed to parse weather data: " + e);
                        }
                    } else {
                        reject("Weather fetch error: " + xhr.status);
                    }
                }
            };
            xhr.open("GET", url);
            xhr.send();
        });
    }

    // --------------------------------
    function errorCallback(message) {
        Logger.error(message);
        isFetchingWeather = false;
    }

    // --------------------------------
    function weatherSymbolFromCode(code) {
        if (code === 0)
            return "sunny";
        if (code === 1 || code === 2)
            return "partly_cloudy_day";
        if (code === 3)
            return "cloud";
        if (code >= 45 && code <= 48)
            return "foggy";
        if (code >= 51 && code <= 67)
            return "rainy";
        if (code >= 71 && code <= 77)
            return "weather_snowy";
        if (code >= 80 && code <= 82)
            return "rainy";
        if (code >= 95 && code <= 99)
            return "thunderstorm";
        return "cloud";
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