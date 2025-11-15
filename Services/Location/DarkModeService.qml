pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // --- Caching for Manual Dark Mode ---
  readonly property alias cache: cacheAdapter
  FileView {
	id: cacheFileView
	path: Settings.cacheDir + "darkmode.cache.json"
	onAdapterUpdated: saveTimer.start()
	JsonAdapter {
	  id: cacheAdapter
	  property bool manualDarkMode: true
	}
  }
  Timer {
	id: saveTimer
	interval: 1000
	onTriggered: cacheFileView.writeAdapter()
  }

  // --- Service State ---
  property var schedule: []
  property bool nextDarkModeState: false

  // --- Connections (simplified) ---
  // Only listen for proactive weather data updates when location mode is active
  Connections {
	target: LocationService.data
	enabled: Settings.data.colorSchemes.schedulingMode === "location"
	function onWeatherChanged() {
	  if (LocationService.data.weather !== null) {
		Logger.i("DarkModeService", "Weather data updated, re-evaluating schedule for location mode.")
		root.activateLocationMode()
		// Re-evaluate and reschedule immediately
	  }
	}
  }

  // --- Timers ---
  Timer {
	id: timer // For upcoming sunrise/sunset events
	onTriggered: {
	  Settings.data.colorSchemes.darkMode = root.nextDarkModeState
	  // After triggering, re-evaluate schedule for the next event based on current mode.
	  const mode = Settings.data.colorSchemes.schedulingMode
	  if (mode === "manual") {
		root.schedule = root.collectManualChanges()
		root.scheduleNextMode(root.schedule)
	  } else if (mode === "location" && LocationService.data.weather) {
		root.schedule = root.collectWeatherChanges(LocationService.data.weather)
		root.scheduleNextMode(root.schedule)
	  } else {
		Logger.w("DarkModeService", "Timer triggered but scheduling mode is not active or data missing.")
	  }
	}
  }

  // Polling timer for location mode (to ensure data freshness and re-evaluation)
  Timer {
	id: locationPollingTimer
	interval: 900000 // 15 minutes
	repeat: true
	running: false

	onTriggered: {
	  Logger.d("DarkModeService", "Polling for location data to update theme in location mode.")
	  root.activateLocationMode()
	  // This will fetch fresh data if needed and reschedule
	}
  }

  // --- Public API for UI to control scheduling ---
  function activateManualMode() {
	Logger.i("DarkModeService", "Activating manual scheduling mode.")
	locationPollingTimer.stop()
	// Stop polling if it was active

	root.schedule = collectManualChanges()
	applyCurrentMode(root.schedule)
	// Apply immediately
	scheduleNextMode(root.schedule)
	// Schedule next fixed event
  }

  function activateLocationMode() {
	Logger.i("DarkModeService", "Activating/Updating location scheduling mode.")
	locationPollingTimer.start()
	// Ensure polling is always active in this mode

	if (LocationService.data.weather) {
	  Logger.i("DarkModeService", "Location data available, using weather-based schedule.")
	  root.schedule = collectWeatherChanges(LocationService.data.weather)
	  applyCurrentMode(root.schedule)
	  scheduleNextMode(root.schedule)
	} else {
	  Logger.w("DarkModeService", "Location data not available. Temporarily falling back to manual schedule.")
	  root.schedule = collectManualChanges()
	  applyCurrentMode(root.schedule)
	  // Apply immediately with fallback schedule
	  scheduleNextMode(root.schedule)
	  // Schedule next change with fallback schedule
	}
  }

  function deactivateScheduling() {
	Logger.i("DarkModeService", "Deactivating scheduling modes.")
	locationPollingTimer.stop()
	// Stop any active polling
	timer.stop()
	// Stop any pending sunrise/sunset timer
  }

  // --- Service Initialization (Called on startup and mode change) ---
  function init() {
	Logger.i("DarkModeService", "Service initializing...")
	const mode = Settings.data.colorSchemes.schedulingMode

	if (mode === "manual") {
	  root.activateManualMode()
	} else if (mode === "location") {
	  root.activateLocationMode()
	} else {
	  // "off"
	  root.deactivateScheduling()
	}
  }

  // --- Core Helper Functions ---
  function applyCurrentMode(changes) {
	const now = Date.now()
	let lastChange = null
	for (var i = 0; i < changes.length; i++) {
	  if (changes[i].time < now) {
		lastChange = changes[i]
	  }
	}

	if (lastChange) {
	  Logger.d("DarkModeService", `Applying current mode. Should be: ${lastChange.darkMode ? 'dark' : 'light'}`)
	  Settings.data.colorSchemes.darkMode = lastChange.darkMode
	}
  }

  function scheduleNextMode(changes) {
	const now = Date.now()
	const nextChange = changes.find(change => change.time > now)
	if (nextChange) {
	  root.nextDarkModeState = nextChange.darkMode
	  timer.interval = nextChange.time - now
	  timer.restart()
	  Logger.d("DarkModeService", `Scheduled next change to ${nextChange.darkMode ? 'dark' : 'light'} in ${timer.interval}ms`)
	} else {
	  Logger.w("DarkModeService", "No future schedule changes found.")
	  timer.stop()
	  // No more changes to schedule
	}
  }

  // --- Data Collection Functions ---
  function parseTime(timeString) {
	const parts = timeString.split(":").map(Number)
	return {
	  "hour": parts[0],
	  "minute": parts[1]
	}
  }

  function collectManualChanges() {
	const sunriseTime = parseTime(Settings.data.colorSchemes.manualSunrise)
	const sunsetTime = parseTime(Settings.data.colorSchemes.manualSunset)
	const now = new Date()
	const year = now.getFullYear()
	const month = now.getMonth()
	const day = now.getDate()
	const yesterdaysSunset = new Date(year, month, day - 1, sunsetTime.hour, sunsetTime.minute)
	const todaysSunrise = new Date(year, month, day, sunriseTime.hour, sunriseTime.minute)
	const todaysSunset = new Date(year, month, day, sunsetTime.hour, sunsetTime.minute)
	const tomorrowsSunrise = new Date(year, month, day + 1, sunriseTime.hour, sunriseTime.minute)
	return [
		  {
			"time": yesterdaysSunset.getTime(),
			"darkMode": true
		  },
		  {
			"time": todaysSunrise.getTime(),
			"darkMode": false
		  },
		  {
			"time": todaysSunset.getTime(),
			"darkMode": true
		  },
		  {
			"time": tomorrowsSunrise.getTime(),
			"darkMode": false
		  }
		]
  }

  function collectWeatherChanges(weather) {
	const changes = []
	if (!weather || !weather.daily || !weather.daily.sunrise || weather.daily.sunrise.length === 0) {
	  Logger.w("DarkModeService", "Weather data is missing or invalid.")
	  return []
	}

	if (Date.now() < Date.parse(weather.daily.sunrise[0])) {
	  changes.push({
					 "time": Date.now() - 1,
					 "darkMode": true
				   })
	}

	for (var i = 0; i < weather.daily.sunrise.length; i++) {
	  if (weather.daily.sunrise[i] && weather.daily.sunset[i]) {
		changes.push({
					   "time": Date.parse(weather.daily.sunrise[i]),
					   "darkMode": false
					 })
		changes.push({
					   "time": Date.parse(weather.daily.sunset[i]),
					   "darkMode": true
					 })
	  }
	}
	return changes
  }
}
