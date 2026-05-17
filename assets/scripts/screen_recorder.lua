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
local processCheckPending = false
local stateGeneration = 0
local updateDisplay

-- ── Helpers ──────────────────────────────────────────────────────────────

local function cfg(key, default)
    return barWidget.getConfig(key, default)
end

local function setState(nextState)
    if state == nextState then return end
    state = nextState
    stateGeneration = stateGeneration + 1
end

local function detectProcessStateAsync(callback)
    local pending = 6
    local isReplaying = false
    local isRecording = false

    local function finish(kind, matched)
        if matched then
            if kind == "replaying" then
                isReplaying = true
            elseif kind == "recording" then
                isRecording = true
            end
        end

        pending = pending - 1
        if pending > 0 then return end

        if isReplaying then
            callback("replaying")
        elseif isRecording then
            callback("recording")
        else
            callback(nil)
        end
    end

    local function queue(kind, name, token)
        local ok = noctalia.processMatches(function(matched)
            finish(kind, matched)
        end, name, token)
        if not ok then
            finish(kind, false)
        end
    end

    queue("replaying", "gpu-screen-recorder", " -r ")
    queue("replaying", "com.dec05eba.gpu_screen_recorder", " -r ")
    queue("recording", "gpu-screen-recorder", " -w ")
    queue("recording", "com.dec05eba.gpu_screen_recorder", " -w ")
    queue("recording", "gpu-screen-recorder", " -o ")
    queue("recording", "com.dec05eba.gpu_screen_recorder", " -o ")
end

local function flatpakGsrInstalled()
    if not noctalia.flatpakAppInstalled then
        return nil
    end
    return noctalia.flatpakAppInstalled("com.dec05eba.gpu_screen_recorder")
end

local function checkAvailability()
    if noctalia.commandExists("gpu-screen-recorder") then
        return true
    end
    return noctalia.commandExists("flatpak") and flatpakGsrInstalled() == true
end

local function copyToClipboard(path)
    local uri = "file://" .. path:gsub(" ", "%%20"):gsub("'", "%%27"):gsub('"', "%%22")
    noctalia.copyToClipboard(uri, "text/uri-list")
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
    if not noctalia.focusedOutputName then
        return nil
    end
    return noctalia.focusedOutputName()
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

local function checkPortalsAsync(callback)
    local pending = 5
    local hasPortal = false
    local hasBackend = false

    local function finish(kind, matched)
        if matched then
            if kind == "portal" then
                hasPortal = true
            elseif kind == "backend" then
                hasBackend = true
            end
        end

        pending = pending - 1
        if pending == 0 then
            callback(hasPortal and hasBackend)
        end
    end

    local function queue(kind, token)
        local ok = noctalia.processMatches(function(matched)
            finish(kind, matched)
        end, token)
        if not ok then
            finish(kind, false)
        end
    end

    queue("portal", "xdg-desktop-portal ")
    queue("backend", "xdg-desktop-portal-wlr ")
    queue("backend", "xdg-desktop-portal-hyprland ")
    queue("backend", "xdg-desktop-portal-gnome ")
    queue("backend", "xdg-desktop-portal-kde ")
end

-- ── Recording controls ───────────────────────────────────────────────────

local function startRecording()
    if not isAvailable or state ~= "idle" then return end

    setState("pending")
    pendingTick = 0
    updateDisplay()

    checkPortalsAsync(function(portalAvailable)
        if state ~= "pending" then return end

        if not portalAvailable then
            setState("idle")
            noctalia.notifyError("Recording failed", "xdg-desktop-portal is not running")
            updateDisplay()
            return
        end

        local cmd = buildRecordCommand()
        if not cmd then
            setState("idle")
            updateDisplay()
            return
        end

        if not noctalia.runAsync(cmd) then
            setState("idle")
            noctalia.notifyError("Recording failed", "Could not launch gpu-screen-recorder")
            updateDisplay()
        end
    end)
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

    setState("idle")
end

-- ── Replay controls ──────────────────────────────────────────────────────

local function startReplay()
    if not isAvailable or state ~= "idle" then return end
    if not cfg("replay_enabled", false) then return end

    setState("replay_pending")
    pendingTick = 0
    updateDisplay()

    checkPortalsAsync(function(portalAvailable)
        if state ~= "replay_pending" then return end

        if not portalAvailable then
            setState("idle")
            noctalia.notifyError("Replay failed", "xdg-desktop-portal is not running")
            updateDisplay()
            return
        end

        local cmd = buildReplayCommand()
        if not cmd then
            setState("idle")
            updateDisplay()
            return
        end

        if not noctalia.runAsync(cmd) then
            setState("idle")
            noctalia.notifyError("Replay failed", "Could not launch gpu-screen-recorder")
            updateDisplay()
        end
    end)
end

local function stopReplay()
    if state ~= "replaying" and state ~= "replay_pending" then return end

    noctalia.runAsync("pkill -SIGINT -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true")
    noctalia.runAsync("(sleep 3 && pkill -9 -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true) &")

    setState("idle")
    noctalia.notify("Replay buffer stopped")
end

local function saveReplay()
    if state ~= "replaying" then return end
    noctalia.runAsync("pkill -SIGUSR1 -f 'gpu-screen-recorder.*-r ' 2>/dev/null || true")
    noctalia.notify("Replay saved")
end

-- ── State polling ────────────────────────────────────────────────────────

local function checkProcessState(processState)
    if state == "pending" then
        pendingTick = pendingTick + CHECK_TICKS
        if pendingTick >= PENDING_TICKS then
            if processState == "recording" then
                setState("recording")
                noctalia.notify("Recording started")
            else
                setState("idle")
            end
        end
    elseif state == "replay_pending" then
        pendingTick = pendingTick + CHECK_TICKS
        if pendingTick >= PENDING_TICKS then
            if processState == "replaying" then
                setState("replaying")
                noctalia.notify("Replay buffer active")
            else
                setState("idle")
            end
        end
    elseif state == "recording" then
        if processState ~= "recording" then
            setState("idle")
            noctalia.notify("Recording saved", outputPath)
            if cfg("copy_to_clipboard", false) and outputPath ~= "" then
                copyToClipboard(outputPath)
            end
        end
    elseif state == "replaying" then
        if processState ~= "replaying" then
            setState("idle")
            noctalia.notify("Replay buffer stopped")
        end
    elseif state == "idle" then
        if processState ~= nil then
            setState(processState)
        end
    end
end

local function requestProcessStateCheck()
    if processCheckPending then return end

    processCheckPending = true
    local generation = stateGeneration
    detectProcessStateAsync(function(processState)
        processCheckPending = false
        if generation ~= stateGeneration then return end
        if processState ~= nil then
            isAvailable = true
        end
        checkProcessState(processState)
        updateDisplay()
    end)
end

-- ── Display ──────────────────────────────────────────────────────────────

function updateDisplay()
    local hideInactive = cfg("hide_inactive", false)

    if not isAvailable then
        barWidget.setGlyph("video-off")
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setVisible(not hideInactive)
        return
    end

    if state == "recording" then
        barWidget.setGlyph("video")
        barWidget.setGlyphColor("error")
        barWidget.setColor("error")
        barWidget.setVisible(true)
    elseif state == "pending" or state == "replay_pending" then
        barWidget.setGlyph("video")
        barWidget.setGlyphColor("primary")
        barWidget.setColor("primary")
        barWidget.setVisible(true)
    elseif state == "replaying" then
        barWidget.setGlyph("repeat")
        barWidget.setGlyphColor("secondary")
        barWidget.setColor("secondary")
        barWidget.setVisible(true)
    else
        barWidget.setGlyph("video")
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
        requestProcessStateCheck()
    end

    if tickCount % CHECK_TICKS == 0 then
        requestProcessStateCheck()
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

function onIpc(event, payload)
    if event == "start" then
        startRecording()
    elseif event == "stop" then
        stopRecording()
    elseif event == "toggle" then
        onClick()
    elseif event == "replay-start" then
        startReplay()
    elseif event == "replay-stop" then
        stopReplay()
    elseif event == "replay-toggle" then
        if state == "replaying" or state == "replay_pending" then
            stopReplay()
        elseif state == "idle" then
            startReplay()
        end
    elseif event == "replay-save" or event == "save-replay" then
        saveReplay()
    else
        noctalia.log("screen_recorder: unknown IPC event '" .. event .. "'")
    end
end
