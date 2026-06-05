barWidget.define({
  label = "Scripted Button Test",
  icon = "terminal",
  description = "Test scripted button clicks plus glyph and color settings",
  pickable = false,
  settings = {
    { key = "label", type = "string", label = "Label", default = "Btop" },
    { key = "glyph", type = "glyph", label = "Glyph", default = "terminal" },
    { key = "normal_color", type = "color", label = "Color", default = "primary" },
    { key = "hover_color", type = "color", label = "Hover color", default = "hover" },
    { key = "terminal_command", type = "string", label = "Terminal command", default = "btop" },
  },
})

local hovering = false

local function cfg(key, default)
  return barWidget.getConfig(key, default)
end

local function currentColor()
  if hovering then
    return cfg("hover_color", "hover")
  end
  return cfg("normal_color", "primary")
end

local function applyDisplay()
  local color = currentColor()
  barWidget.setGlyph(cfg("glyph", "terminal"))
  barWidget.setText(cfg("label", "Btop"))
  barWidget.setColor(color, "script")
  barWidget.setGlyphColor(color, "script")
end

applyDisplay()

function update()
  applyDisplay()
end

function onClick()
  noctalia.runInTerminal(cfg("terminal_command", "btop"))
end

function onRightClick()
  noctalia.runAsync("pavucontrol")
end

function onMiddleClick()
  noctalia.notify("Scripted Button Test", "glyph=" .. cfg("glyph", "terminal") .. ", color=" .. currentColor())
end

function onHover(entered)
  hovering = entered == true
  applyDisplay()
end
