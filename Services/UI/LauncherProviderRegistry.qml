pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  signal pluginProviderRegistryUpdated

  // Plugin provider storage
  property var pluginProviders: ({}) // { "plugin:pluginId": component }
  property var pluginProviderMetadata: ({}) // { "plugin:pluginId": metadata }

  function init() {
    Logger.i("LauncherProviderRegistry", "Service started");
  }

  // Register a plugin launcher provider
  function registerPluginProvider(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("LauncherProviderRegistry", "Cannot register plugin provider: invalid parameters");
      return false;
    }

    var providerId = "plugin:" + pluginId;

    pluginProviders[providerId] = component;
    pluginProviderMetadata[providerId] = metadata || {};

    Logger.i("LauncherProviderRegistry", "Registered plugin provider:", providerId);
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
