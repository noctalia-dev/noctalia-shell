-- GPU Screen Recorder widget for Noctalia
-- Controls gpu-screen-recorder recording and replay buffer.
--
-- Click mapping:
--   Left click  — toggle recording
--   Right click  — toggle replay buffer (if enabled), or save replay (if active)
--   Middle click — save replay buffer

local CHECK_TICKS = 8 -- 8 * 250ms = 2s between process checks
local PENDING_TICKS = 8

local state = "idle" -- idle | pending | recording | replay_pending | replaying
local outputPath = ""
local isAvailable = false
local tickCount = 0
local pendingTick = 0
local checkedAvailability = false

-- ── Helpers ──────────────────────────────────────────────────────────────

local function cfg(key, default)
    return barWidget.getConfig(key, default)
end

local function isProcessRunning()
    local exitCode = noctalia.runSync("pgrep -f '[g]pu-screen-recorder' >/dev/null 2>&1")
    return exitCode == 0
end

local function isReplayProcessRunning()
    local exitCode = noctalia.runSync("pgrep -f 'gpu-screen-recorder.*-r ' >/dev/null 2>&1")
    return exitCode == 0
end

local function checkAvailability()
    if noctalia.commandExists("gpu-screen-recorder") then
        return true
    end
    local exitCode = noctalia.runSync("command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | grep -q com.dec05eba.gpu_screen_recorder")
    return exitCode == 0
end

local function copyToClipboard(path)
    local uri = "file://" .. path:gsub(" ", "%%20"):gsub("'", "%%27"):gsub('"', "%%22")
    noctalia.runAsync("printf '%s' '" .. uri .. "' | wl-copy --type text/uri-list")
end

-- ── Command builders ─────────────────────────────────────────────────────

local function buildAudioFlags()
    local source = cfg("audio_source", "default_output")
    local codec = cfg("audio_codec", "opus")
    if source == "none" then return "" end
    if source == "both" then
        return '-ac ' .. codec .. ' -a "default_output|default_input"'
    end
    return "-ac " .. codec .. " -a " .. source
end

local function buildResolutionFlag()
    local res = cfg("resolution", "original")
    if res ~= "original" then return "-s " .. res end
    local codec = cfg("video_codec", "h264")
    if codec == "h264" then return "-s 4096x4096" end
    return ""
end

local function detectFocusedMonitor()
    local script = [[
set -euo pipefail
pos=$(hyprctl cursorpos)
cx=${pos%,*}; cy=${pos#*,}
mon=$(hyprctl monitors -j | jq -r --argjson cx "$cx" --argjson cy "$cy" \
  '.[] | select(($cx>=.x) and ($cx<(.x+.width)) and ($cy>=.y) and ($cy<(.y+.height))) | .name' \
  | head -n1)
[ -n "${mon:-}" ] || exit 1
echo "$mon"
]]
    local exitCode, stdout = noctalia.runSync(script)
    if exitCode == 0 and stdout ~= "" then
        return stdout
    end
    return nil
end

local function buildGsrPrefix()
    return [[
_gpuscreenrecorder_flatpak_installed() {
  flatpak list --app 2>/dev/null | grep -q "com.dec05eba.gpu_screen_recorder"
}
if command -v gpu-screen-recorder >/dev/null 2>&1; then
  gpu-screen-recorder]]
end

local function buildGsrSuffix()
    return [[

elif command -v flatpak >/dev/null 2>&1 && _gpuscreenrecorder_flatpak_installed; then
  flatpak run --command=gpu-screen-recorder com.dec05eba.gpu_screen_recorder]]
end

local function buildRecordCommand()
    local source = cfg("video_source", "portal")

    if source == "focused-monitor" then
        local mon = detectFocusedMonitor()
        if not mon then
            noctalia.notifyError("Recording failed", "Could not detect focused monitor")
            return nil
        end
        source = mon
    end

    local dir = cfg("directory", "")
    if dir == "" then dir = (noctalia.getenv("HOME") or "/tmp") .. "/Videos" end
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end

    local pattern = cfg("filename_pattern", "recording_%Y%m%d_%H%M%S")
    local filename = os.date(pattern) .. ".mp4"
    outputPath = dir .. filename

    local fps = cfg("frame_rate", 60)
    local codec = cfg("video_codec", "h264")
    local quality = cfg("quality", "very_high")
    local cursor = cfg("show_cursor", true) and "yes" or "no"
    local cr = cfg("color_range", "limited")
    local restore = cfg("restore_portal", false) and "-restore-portal-session yes" or ""
    local audioFlags = buildAudioFlags()
    local resFlag = buildResolutionFlag()

    local flags = string.format(
        '-w %s -f %d -k %s %s -q %s -cursor %s -cr %s %s %s -o "%s"',
        source, fps, codec, audioFlags, quality, cursor, cr, resFlag, restore, outputPath
    )

    return buildGsrPrefix() .. " " .. flags .. buildGsrSuffix() .. " " .. flags .. "\nfi"
end

local function buildReplayCommand()
    local source = cfg("video_source", "portal")

    if source == "focused-monitor" then
        local mon = detectFocusedMonitor()
        if not mon then
            noctalia.notifyError("Replay failed", "Could not detect focused monitor")
            return nil
        end
        source = mon
    end

    local dir = cfg("directory", "")
    if dir == "" then dir = (noctalia.getenv("HOME") or "/tmp") .. "/Videos" end
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end

    local duration = cfg("replay_duration", 30)
    local storage = cfg("replay_storage", "ram")
    local fps = cfg("frame_rate", 60)
    local codec = cfg("video_codec", "h264")
    local quality = cfg("quality", "very_high")
    local cursor = cfg("show_cursor", true) and "yes" or "no"
    local cr = cfg("color_range", "limited")
    local restore = cfg("restore_portal", false) and "-restore-portal-session yes" or ""
    local audioFlags = buildAudioFlags()
    local resFlag = buildResolutionFlag()

    local flags = string.format(
        '-w %s -c mp4 -f %d -k %s %s -q %s -cursor %s -cr %s %s -r %d -replay-storage %s %s -o "%s"',
        source, fps, codec, audioFlags, quality, cursor, cr, resFlag, duration, storage, restore, dir
    )

    return buildGsrPrefix() .. " " .. flags .. buildGsrSuffix() .. " " .. flags .. "\nfi"
end

-- ── Portal check ─────────────────────────────────────────────────────────

local function checkPortals()
    local exitCode = noctalia.runSync(
        "pidof xdg-desktop-portal >/dev/null 2>&1 && " ..
        "(pidof xdg-desktop-portal-wlr >/dev/null 2>&1 || " ..
        "pidof xdg-desktop-portal-hyprland >/dev/null 2>&1 || " ..
        "pidof xdg-desktop-portal-gnome >/dev/null 2>&1 || " ..
        "pidof xdg-desktop-portal-kde >/dev/null 2>&1)"
    )
    return exitCode == 0
end

-- ── Recording controls ───────────────────────────────────────────────────

local function startRecording()
    if not isAvailable or state ~= "idle" then return end

    if not checkPortals() then
        noctalia.notifyError("Recording failed", "xdg-desktop-portal is not running")
        return
    end

    local cmd = buildRecordCommand()
    if not cmd then return end

    state = "pending"
    pendingTick = 0
    noctalia.runAsync(cmd)
end

local function stopRecording()
    if state ~= "recording" and state ~= "pending" then return end

    noctalia.runAsync("pkill -SIGINT -f '^(/nix/store/.*-)?gpu-screen-recorder' 2>/dev/null || pkill -SIGINT -f '^com.dec05eba.gpu_screen_recorder' 2>/dev/null || true")
    -- Force kill fallback
    noctalia.runAsync("(sleep 3 && pkill -9 -f '^(/nix/store/.*-)?gpu-screen-recorder' 2>/dev/null || true) &")

    if state == "recording" then
        noctalia.notify("Recording saved", outputPath)
        if cfg("copy_to_clipboard", false) and outputPath ~= "" then
            copyToClipboard(outputPath)
        end
    end

    state = "idle"
end

-- ── Replay controls ──────────────────────────────────────────────────────

local function startReplay()
    if not isAvailable or state ~= "idle" then return end
    if not cfg("replay_enabled", false) then return end

    if not checkPortals() then
        noctalia.notifyError("Replay failed", "xdg-desktop-portal is not running")
        return
    end

    local cmd = buildReplayCommand()
    if not cmd then return end

    state = "replay_pending"
    pendingTick = 0
    noctalia.runAsync(cmd)
end

local function stopReplay()
    if state ~= "replaying" and state ~= "replay_pending" then return end

    noctalia.runAsync("pkill -SIGINT -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true")
    noctalia.runAsync("(sleep 3 && pkill -9 -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true) &")

    state = "idle"
    noctalia.notify("Replay buffer stopped")
end

local function saveReplay()
    if state ~= "replaying" then return end
    noctalia.runAsync("pkill -SIGUSR1 -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true")
    noctalia.notify("Replay saved")
end

-- ── State polling ────────────────────────────────────────────────────────

local function checkProcessState()
    if state == "pending" then
        pendingTick = pendingTick + CHECK_TICKS
        if pendingTick >= PENDING_TICKS then
            if isProcessRunning() then
                state = "recording"
                noctalia.notify("Recording started")
            else
                state = "idle"
            end
        end
    elseif state == "replay_pending" then
        pendingTick = pendingTick + CHECK_TICKS
        if pendingTick >= PENDING_TICKS then
            if isReplayProcessRunning() then
                state = "replaying"
                noctalia.notify("Replay buffer active")
            else
                state = "idle"
            end
        end
    elseif state == "recording" then
        if not isProcessRunning() then
            state = "idle"
            noctalia.notify("Recording saved", outputPath)
            if cfg("copy_to_clipboard", false) and outputPath ~= "" then
                copyToClipboard(outputPath)
            end
        end
    elseif state == "replaying" then
        if not isReplayProcessRunning() then
            state = "idle"
            noctalia.notify("Replay buffer stopped")
        end
    end
end

-- ── Display ──────────────────────────────────────────────────────────────

local function updateDisplay()
    local hideInactive = cfg("hide_inactive", false)

    if not isAvailable then
        barWidget.setGlyph("video-off")
        barWidget.setText("")
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setVisible(not hideInactive)
        return
    end

    if state == "recording" then
        barWidget.setGlyph("video")
        barWidget.setText("REC")
        barWidget.setGlyphColor("error")
        barWidget.setColor("error")
        barWidget.setVisible(true)
    elseif state == "pending" or state == "replay_pending" then
        barWidget.setGlyph("video")
        barWidget.setText("...")
        barWidget.setGlyphColor("primary")
        barWidget.setColor("primary")
        barWidget.setVisible(true)
    elseif state == "replaying" then
        barWidget.setGlyph("repeat")
        barWidget.setText("REPLAY")
        barWidget.setGlyphColor("secondary")
        barWidget.setColor("secondary")
        barWidget.setVisible(true)
    else
        barWidget.setGlyph("video")
        barWidget.setText("")
        barWidget.setGlyphColor("on_surface")
        barWidget.setVisible(not hideInactive)
    end
end

-- ── Callbacks ────────────────────────────────────────────────────────────

function update()
    tickCount = tickCount + 1

    if not checkedAvailability then
        checkedAvailability = true
        isAvailable = checkAvailability()
    end

    if tickCount % CHECK_TICKS == 0 then
        checkProcessState()
    end

    updateDisplay()
end

function onClick()
    if not isAvailable then return end
    if state == "recording" or state == "pending" then
        stopRecording()
    elseif state == "idle" then
        startRecording()
    end
end

function onRightClick()
    if not isAvailable then return end
    if state == "replaying" then
        saveReplay()
    elseif state == "idle" and cfg("replay_enabled", false) then
        startReplay()
    elseif state == "replay_pending" then
        stopReplay()
    end
end

function onMiddleClick()
    if state == "replaying" then
        saveReplay()
    elseif state == "replaying" or state == "replay_pending" then
        stopReplay()
    end
end
