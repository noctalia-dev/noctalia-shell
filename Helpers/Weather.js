/**
 * Fetches geographic coordinates for a given city name
 * @param {string} city - The name of the city to get coordinates for
 * @returns {Promise<{latitude: number, longitude: number}>} A promise that resolves to the coordinates
 */
function fetchCoordinates(city) {
  return new Promise(function (resolve, reject) {
    const geoUrl =
      "https://geocoding-api.open-meteo.com/v1/search?name=" +
      encodeURIComponent(city) +
      "&language=en&format=json";

    const xhr = new XMLHttpRequest();

    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var geoData = JSON.parse(xhr.responseText);
            if (geoData.results && geoData.results.length > 0) {
              var r = geoData.results[0];
              resolve({ latitude: r.latitude, longitude: r.longitude });
            } else {
              reject(new Error("City not found."));
            }
          } catch (e) {
            reject(new Error("Failed to parse geocoding data."));
          }
        } else {
          reject(new Error("Geocoding error: " + xhr.status));
        }
      }
    };
    xhr.open("GET", geoUrl);
    xhr.send();
  });
}
/**
 * Fetches weather data for a given location
 * @param {number} latitude - The latitude coordinate
 * @param {number} longitude - The longitude coordinate
 * @returns {Promise<Object>} A promise that resolves to weather data
 */
function fetchWeather(latitude, longitude) {
  return new Promise(function (resolve, reject) {
    const url =
      "https://api.open-meteo.com/v1/forecast?latitude=" +
      latitude +
      "&longitude=" +
      longitude +
      "&current_weather=true&current=relativehumidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&timezone=auto";

    const xhr = new XMLHttpRequest();

    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            const weatherData = JSON.parse(xhr.responseText);
            resolve(weatherData);
          } catch (e) {
            reject(new Error("Failed to parse weather data."));
          }
        } else {
          reject(new Error("Weather fetch error: " + xhr.status));
        }
      }
    };
    xhr.open("GET", url);
    xhr.send();
  });
}


/**
 * Fetches weather data for a specified city
 * @param {string} city - The name of the city to fetch weather data for
 * @returns {Promise<Object>} A promise that resolves to an object containing city info and weather data
 */
function fetchCityWeather(city) {
  return fetchCoordinates(city).then(function (coords) {
    return fetchWeather(coords.latitude, coords.longitude).then(function (
      weatherData
    ) {
      return {
        city: city,
        latitude: coords.latitude,
        longitude: coords.longitude,
        weather: weatherData,
      };
    });
  });
}
