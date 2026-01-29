pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location.Calendar
import qs.Services.System

Singleton {
  id: root

  // Core state
  property var events: ([])
  property bool loading: false
  property bool available: false
  property string lastError: ""
  property var calendars: ([])

  property var dataProvider: null

  // Persistent cache
  property string cacheFile: Settings.cacheDir + "calendar.json"

  // Cache file handling
  FileView {
    id: cacheFileView
    path: root.cacheFile
    printErrors: false

    JsonAdapter {
      id: cacheAdapter
      property var cachedEvents: ([])
      property var cachedCalendars: ([])
      property string lastUpdate: ""
    }

    onLoadFailed: {
      cacheAdapter.cachedEvents = ([]);
      cacheAdapter.cachedCalendars = ([]);
      cacheAdapter.lastUpdate = "";
    }

    onLoaded: {
      loadFromCache();
    }
  }

  Component.onCompleted: {
    Logger.i("Calendar", "Service started");
    loadFromCache();
    checkAvailability();
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  function setEvents(newEvents) {
    root.events = newEvents;
    cacheAdapter.cachedEvents = newEvents;
    cacheAdapter.lastUpdate = new Date().toISOString();
    saveCache();
  }

  function setCalendars(newCalendars) {
    root.calendars = newCalendars;
    cacheAdapter.cachedCalendars = newCalendars;
    saveCache();
  }

  function loadCachedEvents() {
    if (cacheAdapter.cachedEvents.length > 0) {
      root.events = cacheAdapter.cachedEvents;
    }
  }

  function saveCache() {
    saveDebounce.restart();
  }

  // Load events and calendars from cache
  function loadFromCache() {
    if (cacheAdapter.cachedEvents && cacheAdapter.cachedEvents.length > 0) {
      root.events = cacheAdapter.cachedEvents;
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedEvents.length} cached event(s)`);
    }

    if (cacheAdapter.cachedCalendars && cacheAdapter.cachedCalendars.length > 0) {
      root.calendars = cacheAdapter.cachedCalendars;
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedCalendars.length} cached calendar(s)`);
    }

    if (cacheAdapter.lastUpdate) {
      Logger.d("Calendar", `Cache last updated: ${cacheAdapter.lastUpdate}`);
    }
  }

  // Auto-refresh timer (every 5 minutes)
  Timer {
    id: refreshTimer
    interval: 300000
    running: true
    repeat: true
    onTriggered: loadEvents()
  }

  // Core functions
  function checkAvailability() {
    if (!Settings.data.location.showCalendarEvents) {
      root.available = false;
      return;
    }

    Khal.init();
    EvolutionDataServer.init();
  }

  function loadCalendars() {
    if (!root.available || !dataProvider) {
      return;
    }

    dataProvider.loadCalendars();
  }
  function loadEvents(daysAhead = 31, daysBehind = 14) {
    if (!root.available || !dataProvider) {
      return;
    }

    dataProvider.loadEvents(daysAhead, daysBehind);
  }
}
