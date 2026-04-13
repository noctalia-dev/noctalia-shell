.pragma library

// Address helpers
var macFromDevice = (dev) => {
  if (!dev) return "";
  if (dev.address && dev.address.length > 0) return dev.address;
  if (dev.nativePath && dev.nativePath.indexOf("/dev_") !== -1)
    return dev.nativePath.split("dev_")[1].split("_").join(":");
  return "";
};

var deviceKey = (dev) => {
  if (!dev) return "";
  if (dev.address && dev.address.length > 0) return dev.address.toUpperCase();
  if (dev.nativePath && dev.nativePath.length > 0) return dev.nativePath;
  if (dev.devicePath && dev.devicePath.length > 0) return dev.devicePath;
  return (dev.name || dev.deviceName || "") + "|" + (dev.icon || "");
};

var dedupeDevices = (list) => {
  if (!list || list.length === 0) return [];
  var seen = ({});
  var out = [];
  for (var i = 0; i < list.length; ++i) {
    var d = list[i];
    if (!d) continue;
    var k = deviceKey(d);
    if (k && !seen[k]) { seen[k] = true; out.push(d); }
  }
  return out;
};

// RSSI parsing
var parseRssiOutput = (text) => {
  try {
    text = text || "";
    var mParen = text.match(/\(\s*(-?\d+)\s*(?:d?b?m?)?\s*\)/i);
    if (mParen && mParen.length > 1) return Number(mParen[1]);
    var mDec = text.match(/RSSI:\s*(-?\d+)/i);
    if (mDec && mDec.length > 1) return Number(mDec[1]);
    var mHex = text.match(/RSSI:\s*0x([0-9a-fA-F]+)/i);
    if (mHex && mHex.length > 1) {
      var v = parseInt(mHex[1], 16);
      if (v >= 0x80000000) v = v - 0x100000000; // 32-bit two's complement
      else if (v >= 0x8000) v = v - 0x10000;     // 16-bit
      else if (v >= 0x80) v = v - 0x100;         // 8-bit
      return v;
    }
  } catch (e) {}
  return null;
};

var dbmToPercent = (dbm) => {
  if (dbm === null || dbm === undefined || isNaN(dbm)) return null;
  // Clamp simple linear map roughly from -100..0 dBm to 0..100%
  var pct = Math.round((Number(dbm) + 100) * 2);
  if (isNaN(pct)) return null;
  return Math.max(0, Math.min(100, pct));
};

// Signal helpers
var signalPercent = (device, cache, _version) => {
  if (!device) return null;
  try {
    var addr = macFromDevice(device);
    if (addr && cache && cache[addr] !== undefined) {
      var cached = Number(cache[addr]) | 0;
      return Math.max(0, Math.min(100, cached));
    }
  } catch (e) {}
  var s = device && device.signalStrength;
  if (s === undefined || s <= 0) return null;
  var p = Number(s) | 0;
  return Math.max(0, Math.min(100, p));
};

var signalIcon = (p) => {
  if (p === null) return "antenna-bars-off";
  if (p >= 80) return "antenna-bars-5";
  if (p >= 60) return "antenna-bars-4";
  if (p >= 40) return "antenna-bars-3";
  if (p >= 20) return "antenna-bars-2";
  return "antenna-bars-1";
};
