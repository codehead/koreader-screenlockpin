local logger = require("logger")

--
-- Init
--

local function migrateSettings()
    -- migrate from 2025.10
    if G_reader_settings:has("screenlockpin") then
        -- rename screenlockpin -> screenlockpin_pin
        G_reader_settings:saveSetting("screenlockpin_pin", G_reader_settings:readSetting("screenlockpin"))
        G_reader_settings:delSetting("screenlockpin")
    end
    -- migrate from 2025.10-2 and earlier
    if G_reader_settings:has("screenlockpin_returndelay") then
        -- rename screenlockpin_returndelay -> screenlockpin_restore_screensaver_delay
        G_reader_settings:saveSetting("screenlockpin_restore_screensaver_delay", G_reader_settings:readSetting("screenlockpin_returndelay"))
        G_reader_settings:delSetting("screenlockpin_returndelay")
    end
    -- migrate from 2025.10-3
    if G_reader_settings:has("screenlockpin_version") then
        G_reader_settings:delSetting("screenlockpin_version")
        -- migrate floating ui_scale [0,1] to integer [0,100]
        local uiScale = G_reader_settings:readSetting("screenlockpin_ui_scale")
        if uiScale < 1 then
            G_reader_settings:saveSetting("screenlockpin_ui_scale", math.floor(uiScale * 100))
        end
    end
end

local function mergeDefaultSettings()
    if G_reader_settings:hasNot("screenlockpin_ui_scale") then
        G_reader_settings:saveSetting("screenlockpin_ui_scale", 40)
    end
    if G_reader_settings:hasNot("screenlockpin_ui_pos_x") then
        G_reader_settings:saveSetting("screenlockpin_ui_pos_x", 50)
    end
    if G_reader_settings:hasNot("screenlockpin_ui_pos_y") then
        G_reader_settings:saveSetting("screenlockpin_ui_pos_y", 50)
    end
    if G_reader_settings:hasNot("screenlockpin_pin") then
        G_reader_settings:saveSetting("screenlockpin_pin", "0000")
    end
    if G_reader_settings:hasNot("screenlockpin_onboot") then
        G_reader_settings:makeFalse("screenlockpin_onboot")
    end
    if G_reader_settings:hasNot("screenlockpin_ratelimit") then
        G_reader_settings:makeTrue("screenlockpin_ratelimit")
    end
    if G_reader_settings:hasNot("screenlockpin_note_mode") then
        G_reader_settings:saveSetting("screenlockpin_note_mode", "disabled")
    end
    if G_reader_settings:hasNot("screenlockpin_note_text") then
        G_reader_settings:saveSetting("screenlockpin_note_text", "")
    end
    if G_reader_settings:hasNot("screenlockpin_prevent_screenshots") then
        G_reader_settings:saveSetting("screenlockpin_prevent_screenshots", true)
    end
end

local function init()
    logger.dbg("ScreenLockPin: init settings")
    migrateSettings()
    mergeDefaultSettings()
end

--
-- Cosmetic Options
--

local function getUiSettings()
    return {
        scale = G_reader_settings:readSetting("screenlockpin_ui_scale"),
        pos_x = G_reader_settings:readSetting("screenlockpin_ui_pos_x"),
        pos_y = G_reader_settings:readSetting("screenlockpin_ui_pos_y"),
    }
end

local function setUiSettings(settings)
    if settings.scale ~= nil then
        G_reader_settings:saveSetting("screenlockpin_ui_scale", settings.scale)
    end
    if settings.pos_x ~= nil then
        G_reader_settings:saveSetting("screenlockpin_ui_pos_x", settings.pos_x)
    end
    if settings.pos_y ~= nil then
        G_reader_settings:saveSetting("screenlockpin_ui_pos_y", settings.pos_y)
    end
end

local function setUiSetting(key, value)
    G_reader_settings:saveSetting("screenlockpin_ui_" .. key, value)
end

local function getNoteSettings()
    return {
        mode = G_reader_settings:readSetting("screenlockpin_note_mode"),
        text = G_reader_settings:readSetting("screenlockpin_note_text"),
    }
end

local function setNoteMode(mode)
    G_reader_settings:saveSetting("screenlockpin_note_mode", mode)
end

local function setNoteText(text)
    G_reader_settings:saveSetting("screenlockpin_note_text", text)
end

--
-- Prevent screenshots
--

local function getPreventScreenshots()
    return G_reader_settings:readSetting("screenlockpin_prevent_screenshots")
end

local function setPreventScreenshots(bool)
    G_reader_settings:saveSetting("screenlockpin_prevent_screenshots", bool)
end

--
-- PIN
--

local function readPin()
    return G_reader_settings:readSetting("screenlockpin_pin")
end

local function setPin(next_pin)
    --logger.dbg("ScreenLockPin: updating PIN to " .. next_pin)
    logger.dbg("ScreenLockPin: updating PIN to [redacted]")
    G_reader_settings:saveSetting("screenlockpin_pin", next_pin)
end

--
-- Persistent cache
--

local function readPersistentCache(key)
    local cache = G_reader_settings:readSetting("screenlockpin_cache") or {}
    if not key then return cache end
    return cache[key]
end

local function writePersistentCache(data)
    G_reader_settings:saveSetting("screenlockpin_cache", data)
end

local function putPersistentCache(key, data)
    local cache = readPersistentCache()
    cache[key] = data
    writePersistentCache(cache)
end

--
-- Lock on wakeup
--

local function shouldLockOnWakeup()
    return G_reader_settings:readSetting("screensaver_delay") == "plugin:screenlockpin"
end

local function setLockOnWakeup(bool)
    if bool == shouldLockOnWakeup() then return false end
    if bool then
        local return_value = G_reader_settings:readSetting("screensaver_delay")
        logger.dbg("ScreenLockPin: enable lock on wakeup (restore value: " .. (return_value or "nil") .. ")")
        G_reader_settings:saveSetting("screenlockpin_restore_screensaver_delay", return_value)
        G_reader_settings:saveSetting("screensaver_delay", "plugin:screenlockpin")
    else
        local return_value = G_reader_settings:readSetting("screenlockpin_restore_screensaver_delay")
        logger.dbg("ScreenLockPin: disable lock on wakeup (restore value: " .. (return_value or "nil -> disable") .. ")")
        G_reader_settings:saveSetting("screensaver_delay", return_value or "disable")
        G_reader_settings:delSetting("screenlockpin_restore_screensaver_delay")
    end
    return true
end

local function toggleLockOnWakeup()
    return setLockOnWakeup(not shouldLockOnWakeup())
end

--
-- Lock on boot
--

local function shouldLockOnBoot()
    return G_reader_settings:isTrue("screenlockpin_onboot")
end

local function toggleLockOnBoot()
    return G_reader_settings:toggle("screenlockpin_onboot")
end

--
-- Rate Limiter
--

local function shouldRateLimit()
    return G_reader_settings:isTrue("screenlockpin_ratelimit")
end

--
-- Cleanup
--

local function purge()
    -- cause restore of foreign screensaver_delay setting
    setLockOnWakeup(false)
    -- delete all our settings
    G_reader_settings:delSetting("screenlockpin_ui_scale")
    G_reader_settings:delSetting("screenlockpin_ui_pos_x")
    G_reader_settings:delSetting("screenlockpin_ui_pos_y")
    G_reader_settings:delSetting("screenlockpin_pin")
    G_reader_settings:delSetting("screenlockpin_onboot")
    G_reader_settings:delSetting("screenlockpin_ratelimit")
    G_reader_settings:delSetting("screenlockpin_restore_screensaver_delay")
    G_reader_settings:delSetting("screenlockpin_note_mode")
    G_reader_settings:delSetting("screenlockpin_note_text")
end

return {
    init = init,
    purge = purge,

    getUiSettings = getUiSettings,
    setUiSettings = setUiSettings,
    setUiSetting = setUiSetting,

    getNoteSettings = getNoteSettings,
    setNoteMode = setNoteMode,
    setNoteText = setNoteText,

    getPreventScreenshots = getPreventScreenshots,
    setPreventScreenshots = setPreventScreenshots,

    readPin = readPin,
    setPin = setPin,

    readPersistentCache = readPersistentCache,
    putPersistentCache = putPersistentCache,

    shouldLockOnBoot = shouldLockOnBoot,
    shouldLockOnWakeup = shouldLockOnWakeup,
    shouldRateLimit = shouldRateLimit,

    toggleLockOnBoot = toggleLockOnBoot,
    toggleLockOnWakeup = toggleLockOnWakeup,
}
