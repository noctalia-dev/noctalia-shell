pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Noctalia

Singleton {
  id: root

  signal pluginProviderRegistryUpdated

  // Plugin provider storage
  property var pluginProviders: ({}) // { "plugin:pluginId": component }
  property var pluginProviderMetadata: ({}) // { "plugin:pluginId": metadata }

  // Persistent provider instances — survive LauncherCore destruction/recreation
  // so plugins don't re-parse large datasets on every launcher open.
  property var providerInstances: ({}) // { "plugin:pluginId": instance }

  function init() {
    Logger.i("LauncherProviderRegistry", "Service started");
  }

  // Register a plugin launcher provider and instantiate it immediately
  function registerPluginProvider(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("LauncherProviderRegistry", "Cannot register plugin provider: invalid parameters");
      return false;
    }

    var providerId = "plugin:" + pluginId;

    pluginProviders[providerId] = component;
    pluginProviderMetadata[providerId] = metadata || {};

    // Instantiate immediately so data loading starts in the background
    var pluginApi = PluginService.getPluginAPI(pluginId);
    if (pluginApi) {
      var instance = component.createObject(null, {
                                              pluginApi: pluginApi
                                            });
      if (instance) {
        providerInstances[providerId] = instance;
        if (instance.init)
          instance.init();
        Logger.i("LauncherProviderRegistry", "Registered and instantiated plugin provider:", providerId);
      } else {
        Logger.e("LauncherProviderRegistry", "Failed to instantiate plugin provider:", providerId);
      }
    }

    root.pluginProviderRegistryUpdated();
    return true;
  }

  // Unregister a plugin launcher provider
  function unregisterPluginProvider(pluginId) {
    var providerId = "plugin:" + pluginId;

    if (!pluginProviders[providerId]) {
      Logger.w("LauncherProviderRegistry", "Plugin provider not registered:", providerId);
      return false;
    }

    if (providerInstances[providerId]) {
      providerInstances[providerId].destroy();
      delete providerInstances[providerId];
    }

    delete pluginProviders[providerId];
    delete pluginProviderMetadata[providerId];

    Logger.i("LauncherProviderRegistry", "Unregistered plugin provider:", providerId);
    root.pluginProviderRegistryUpdated();
    return true;
  }

  // Get list of registered plugin provider IDs
  function getPluginProviders() {
    return Object.keys(pluginProviders);
  }

  // Get the live provider instance by ID
  function getProviderInstance(providerId) {
    return providerInstances[providerId] || null;
  }

  // Get provider component by ID
  function getProviderComponent(providerId) {
    return pluginProviders[providerId] || null;
  }

  // Get provider metadata by ID
  function getProviderMetadata(providerId) {
    return pluginProviderMetadata[providerId] || null;
  }

  // Check if ID is a plugin provider
  function isPluginProvider(id) {
    return id.startsWith("plugin:");
  }

  // Check if provider exists
  function hasProvider(providerId) {
    return providerId in pluginProviders;
  }
}
