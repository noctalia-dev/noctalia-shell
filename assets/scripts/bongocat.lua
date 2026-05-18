-- Bongo Cat — a cat that sits in your bar and slaps when you type or to the beat.
--
-- Configure the keyboard device in your bar config:
--   [widget.bongocat]
--   type         = "scripted"
--   script       = "scripts/bongocat.lua"
--   input_device    = "/dev/input/event6"
--   audio_spectrum = true
--   tappy_mode     = true
--   rave_mode      = true
--
-- When input_device is set and `evtest` is installed, the widget
-- automatically starts a single background reader (flock-guarded, so
-- multi-monitor / hot-reload won't spawn duplicates) that forwards
-- key events back to the widget over IPC.
--
-- Requirements: `evtest` installed, and your user in the `input` group.
-- Find your keyboard device with: sudo evtest  (or: ls -l /dev/input/by-id)
--
-- Font glyph map (bongocat.otf):
--   b=left paw up, d=left paw down, c=right paw up, a=right paw down
--   bc=idle, dc=left slap, ba=right slap, da=both slap
--   ef=sleep, gh=blink

barWidget.setFont("fonts/bongocat.otf")
barWidget.setText("bc")
barWidget.setUpdateInterval(50)

-- ── Auto-start keyboard reader ───────────────────────────────────────────
-- The Lua runtime can't consume a long-running process's streaming output,
-- so we spawn an external evtest→IPC bridge. flock keeps it to one instance
-- across every widget instance and across hot reloads.
local LOCK_FILE = "/tmp/noctalia-bongocat-input.lock"

local function startInputReader()
  local device = barWidget.getConfig("input_device", "")
  if device == nil or device == "" then
    return
  end
  -- Only accept a real evdev node — this string is interpolated into a shell
  -- command, so reject anything that isn't /dev/input/eventN.
  if not string.match(device, "^/dev/input/event%d+$") then
    noctalia.notifyError("Bongo Cat", "Invalid input_device (expected /dev/input/eventN): " .. device)
    return
  end
  if not noctalia.commandExists("evtest") then
    noctalia.notifyError("Bongo Cat", "evtest is not installed — cannot read keyboard input")
    return
  end

  local cmd = table.concat({
    "( flock -n 9 || exit 0; ",
    "evtest '", device, "' 2>/dev/null | while IFS= read -r line; do ",
    'case $line in *EV_KEY*) ;; *) continue ;; esac; ',
    'case $line in *BTN_TOOL_*) continue ;; esac; ',
    "p=; ",
    'case $line in *KEY_SPACE*) p=space ;; *KEY_ENTER*) p=enter ;; esac; ',
    "ev=; ",
    "case $line in ",
    "*'value 1'*) ev=keydown ;; ",
    "*'value 0'*) ev=keyup ;; ",
    "*'value 2'*) ev=keyrepeat ;; ",
    "esac; ",
    '[ -z "$ev" ] && continue; ',
    'noctalia msg scripted-widget bongocat all "$ev" "$p" >/dev/null 2>&1 & ',
    "done ) 9>'", LOCK_FILE, "'",
  })
  noctalia.runAsync(cmd)
end

startInputReader()

local STATE_IDLE = 0
local STATE_LEFT = 1
local STATE_RIGHT = 2
local STATE_BOTH = 3

local glyphs = { [STATE_IDLE] = "bc", [STATE_LEFT] = "dc", [STATE_RIGHT] = "ba", [STATE_BOTH] = "da" }
local SLEEP_GLYPH = "ef"
local BLINK_GLYPH = "gh"

local catState = STATE_IDLE
local leftWasLast = false
local paused = false
local waiting = false
local blinking = false

local AUDIO_SPECTRUM_ENABLED = barWidget.getConfig("audio_spectrum", false) == true
local RAVE_MODE = barWidget.getConfig("rave_mode", false) == true
local TAPPY_MODE = barWidget.getConfig("tappy_mode", false) == true
local USE_MPRIS_FILTER = barWidget.getConfig("use_mpris_filter", false) == true

local idleTicks = 0
local waitingTicks = 0
local blinkTicks = 0
local blinkDuration = 0
local nextBlinkIn = 0

local IDLE_TICKS = 5       -- 250ms to return paws to idle after typing stops
local WAITING_TICKS = 100  -- 5s of idle -> sleeping
local BLINK_DURATION = 9   -- ~450ms blink
local BLINK_MIN = 120      -- ~6s minimum between blinks
local BLINK_MAX = 280      -- ~14s max between blinks

local rainbowIndex = 1
local rainbowColors = { "#aa0000", "#b65c02", "#bb9c14", "#00a100", "#01019b", "#37005c", "#6a0196" }
local audioIntensity = 0
local smoothedIntensity = 0
local previousIntensity = 0
local bassIntensity = 0
local beatThreshold = 0.07
local bigBeatThreshold = 0.67
local beatDeltaThreshold = 0.014
local beatCooldownTicks = 0 -- ~100ms
local raveFlashTicks = 0    -- ~100ms
local audioConfigWarned = false

local function randomBlinkDelay()
  return BLINK_MIN + math.floor(math.random() * (BLINK_MAX - BLINK_MIN))
end

nextBlinkIn = randomBlinkDelay()

local function applyCatColor()
  if RAVE_MODE and raveFlashTicks > 0 then
    barWidget.setColor(rainbowColors[rainbowIndex], "script")
  else
    barWidget.setColor("on_surface")
  end
end

local function refreshDisplay()
  applyCatColor()
  if paused or waiting then
    barWidget.setText(SLEEP_GLYPH)
  elseif blinking then
    barWidget.setText(BLINK_GLYPH)
  else
    barWidget.setText(glyphs[catState] or "bc")
  end
end

local function onKeyDown(isBigHit)
  if paused then return end
  waiting = false
  waitingTicks = 0
  blinking = false

  if isBigHit then
    catState = STATE_BOTH
  elseif catState ~= STATE_IDLE then
    catState = STATE_BOTH
  else
    leftWasLast = not leftWasLast
    catState = leftWasLast and STATE_LEFT or STATE_RIGHT
  end
  idleTicks = 0
  refreshDisplay()
end

local function onKeyUp()
  if paused then return end
  waiting = false
  waitingTicks = 0

  if catState == STATE_BOTH then
    catState = leftWasLast and STATE_LEFT or STATE_RIGHT
  else
    catState = STATE_IDLE
  end
  idleTicks = 0
  refreshDisplay()
end

local function onKeyRepeat(isBigHit)
  if paused then return end
  waiting = false
  waitingTicks = 0

  if catState == STATE_IDLE then
    if isBigHit then
      catState = STATE_BOTH
    else
      catState = leftWasLast and STATE_LEFT or STATE_RIGHT
    end
  end
  idleTicks = 0
  refreshDisplay()
end

local function onBeatTap(isBigHit)
  if paused then return end
  waiting = false
  waitingTicks = 0
  blinking = false

  if isBigHit then
    catState = STATE_BOTH
  else
    leftWasLast = not leftWasLast
    catState = leftWasLast and STATE_LEFT or STATE_RIGHT
  end

  idleTicks = 0
  refreshDisplay()
end

local function parseCsvNumbers(csv)
  local values = {}
  if csv == nil or csv == "" then
    return values
  end
  for part in string.gmatch(csv, "([^,]+)") do
    values[#values + 1] = tonumber(part) or 0
  end
  return values
end

local function parseAudioState(csv)
  local parts = parseCsvNumbers(csv)
  return parts[1] == 1, parts[2] == 1
end

local function average(values, firstIndex, lastIndex)
  if lastIndex < firstIndex then
    return 0
  end
  local sum = 0
  local count = 0
  for i = firstIndex, lastIndex do
    sum = sum + (values[i] or 0)
    count = count + 1
  end
  if count == 0 then
    return 0
  end
  return sum / count
end

function update()
  if (RAVE_MODE or TAPPY_MODE) and not AUDIO_SPECTRUM_ENABLED and not audioConfigWarned then
    audioConfigWarned = true
    noctalia.notifyError("Bongo Cat", "Set audio_spectrum = true to use rave_mode or tappy_mode.")
  end

  if beatCooldownTicks > 0 then
    beatCooldownTicks = beatCooldownTicks - 1
  end

  if raveFlashTicks > 0 then
    raveFlashTicks = raveFlashTicks - 1
    if raveFlashTicks == 0 then
      refreshDisplay()
    end
  end

  if paused then return end

  -- Idle timeout: return paws to rest
  if catState ~= STATE_IDLE then
    idleTicks = idleTicks + 1
    if idleTicks >= IDLE_TICKS then
      catState = STATE_IDLE
      refreshDisplay()
    end
  end

  -- Waiting timeout: go to sleep
  if not waiting then
    waitingTicks = waitingTicks + 1
    if waitingTicks >= WAITING_TICKS then
      waiting = true
      blinking = false
      refreshDisplay()
    end
  end

  -- Blink logic (only when awake and idle)
  if not waiting and catState == STATE_IDLE then
    if blinking then
      blinkDuration = blinkDuration + 1
      if blinkDuration >= BLINK_DURATION then
        blinking = false
        blinkDuration = 0
        nextBlinkIn = randomBlinkDelay()
        refreshDisplay()
      end
    else
      nextBlinkIn = nextBlinkIn - 1
      if nextBlinkIn <= 0 then
        blinking = true
        blinkDuration = 0
        refreshDisplay()
      end
    end
  end
end

function onAudioSpectrum(valuesCsv, stateCsv)
  if paused then return end
  if not RAVE_MODE and not TAPPY_MODE then return end

  local audioActive, mprisPlaying = parseAudioState(stateCsv)
  if not audioActive then
    audioIntensity = 0
    return
  end
  if USE_MPRIS_FILTER and not mprisPlaying then
    return
  end

  local values = parseCsvNumbers(valuesCsv)
  if #values == 0 then
    audioIntensity = 0
    return
  end

  local subBassCount = math.min(4, #values)
  local bassCount = math.min(8, #values)
  local midCount = math.min(16, #values)
  local subBassAvg = average(values, 1, subBassCount)
  local bassAvg = average(values, 1, bassCount)
  local midAvg = average(values, 9, midCount)

  bassIntensity = subBassAvg
  audioIntensity = (bassAvg * 0.8) + (midAvg * 0.6)

  local alpha = 0.75
  previousIntensity = smoothedIntensity
  smoothedIntensity = alpha * audioIntensity + (1 - alpha) * smoothedIntensity

  local intensityDelta = smoothedIntensity - previousIntensity
  local isBeat = (intensityDelta > beatDeltaThreshold and smoothedIntensity > beatThreshold * 0.5)
      or (smoothedIntensity > beatThreshold and intensityDelta > 0)

  if isBeat and beatCooldownTicks <= 0 then
    if RAVE_MODE then
      rainbowIndex = (rainbowIndex % #rainbowColors) + 1
      raveFlashTicks = 2
      refreshDisplay()
    end

    if TAPPY_MODE then
      onBeatTap(bassIntensity > bigBeatThreshold)
    end

    beatCooldownTicks = 2
  end
end

function onClick()
  paused = not paused
  if not paused then
    waitingTicks = 0
    waiting = false
    catState = STATE_IDLE
  end
  refreshDisplay()
end

function onIpc(event, payload)
  if event == "keydown" then
    local isBigHit = payload == "space" or payload == "enter"
    onKeyDown(isBigHit)
  elseif event == "keyup" then
    onKeyUp()
  elseif event == "keyrepeat" then
    local isBigHit = payload == "space" or payload == "enter"
    onKeyRepeat(isBigHit)
  elseif event == "pause" then
    paused = true
    refreshDisplay()
  elseif event == "resume" then
    paused = false
    waiting = false
    waitingTicks = 0
    catState = STATE_IDLE
    refreshDisplay()
  elseif event == "toggle" then
    paused = not paused
    if not paused then
      waiting = false
      waitingTicks = 0
      catState = STATE_IDLE
    end
    refreshDisplay()
  end
end
