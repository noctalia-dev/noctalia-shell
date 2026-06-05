-- Test widget for barWidget.setImage(path, watch).
--
-- Example config:
--   [widget.image_test]
--   type = "scripted"
--   script = "scripts/image_test.lua"
--   image_path = "noctalia.svg"
--   watch_image = true
--   image_width = 28
--   label = "Image"
--   show_label = true
--
-- For watch testing, point image_path at a writable absolute path, then replace
-- that file while Noctalia is running.

barWidget.define({
  label = "Scripted Image Test",
  version = "1.0.0",
  icon = "photo",
  description = "Test image display and image file watching",
  pickable = false,
  settings = {
    { key = "image_path", type = "file", label = "Image path", default = "noctalia.svg",
      extensions = { ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".gif" },
      description = "Absolute, ~/ path, or relative to the Noctalia assets directory" },
    { key = "watch_image", type = "bool", label = "Watch image file", default = true },
    { key = "image_width", type = "int", label = "Image width", default = 28, min = 1, max = 96 },
    { key = "image_height", type = "int", label = "Image height", default = 28, min = 1, max = 96 },
    { key = "label", type = "string", label = "Label", default = "Image" },
    { key = "show_label", type = "bool", label = "Show label", default = true },
  },
})

local imageMode = true
local watchOverride = nil

local function configBool(key, default)
  return barWidget.getConfig(key, default) == true
end

local function imagePath()
  return barWidget.getConfig("image_path", "noctalia.svg")
end

local function imageWidth()
  return barWidget.getConfig("image_width", 28)
end

local function imageHeight()
  return barWidget.getConfig("image_height", imageWidth())
end

local function watchEnabled()
  if watchOverride ~= nil then
    return watchOverride
  end
  return configBool("watch_image", true)
end

local function labelText(watch)
  if not configBool("show_label", true) then
    return ""
  end
  if not imageMode then
    return "Glyph"
  end

  local label = barWidget.getConfig("label", "Image")
  return label .. (watch and " W" or " S")
end

local function applyDisplay()
  local watch = watchEnabled()

  if imageMode then
    barWidget.setImage(imagePath(), watch, imageWidth(), imageHeight())
    barWidget.setColor("on_surface")
  else
    barWidget.setGlyph("photo")
    barWidget.setColor("tertiary")
    barWidget.setGlyphColor("tertiary")
  end

  barWidget.setText(labelText(watch))
end

barWidget.setUpdateInterval(1000)
applyDisplay()

function update()
  applyDisplay()
end

function onClick()
  imageMode = not imageMode
  applyDisplay()
end

function onMiddleClick()
  watchOverride = not watchEnabled()
  applyDisplay()
end

function onRightClick()
  local mode = imageMode and "image" or "glyph"
  local watch = watchEnabled() and "on" or "off"
  noctalia.notify("Scripted Image Test", "mode=" .. mode .. ", watch=" .. watch .. ", path=" .. imagePath())
end
