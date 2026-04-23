barWidget.setGlyph("pin")
barWidget.setText("Pin")
barWidget.setColor("secondary")

local pinned = false

function update()
  -- periodic tick, nothing to poll here
end

function onClick()
  pinned = not pinned
  if pinned then
    barWidget.setGlyph("unpin")
    barWidget.setText("Pinned")
    barWidget.setColor("error")
    barWidget.setGlyphColor("error")
  else
    barWidget.setGlyph("pin")
    barWidget.setText("Pin")
    barWidget.setColor("on_surface")
    barWidget.setGlyphColor("on_surface")
  end
end

function onRightClick()
  noctalia.runAsync("pavucontrol")
end

function onMiddleClick()
  barWidget.setGlyph("settings")
  barWidget.setText("Middle!")
  barWidget.setColor("tertiary")
  barWidget.setGlyphColor("tertiary")
end

function onHover(entered)
  if entered then
    barWidget.setColor("primary")
    barWidget.setGlyphColor("primary")
  else
    if muted then
      barWidget.setColor("error")
      barWidget.setGlyphColor("error")
    else
      barWidget.setColor("on_surface")
      barWidget.setGlyphColor("on_surface")
    end
  end
end
