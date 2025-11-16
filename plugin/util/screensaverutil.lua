local logger = require("logger")
local Device = require("device")
local Screensaver = require("ui/screensaver")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")

local uiManagerUtil = require("plugin/util/uimanagerutil")

local function noop() end

local FIELDS = { "setup", "show", "close" }
local restore = {}

local function freezeScreensaverAbi()
    for _, field in ipairs(FIELDS) do
        if restore[field] == nil then
            logger.dbg("ScreenLockPin: monkey-patching Screensaver." .. field .. " to noop")
            restore[field] = Screensaver[field]
            Screensaver[field] = noop
        end
    end
end

local function unfreezeScreensaverAbi()
    for _, field in ipairs(FIELDS) do
        if restore[field] ~= nil then
            logger.dbg("ScreenLockPin: restoring original Screensaver." .. field)
            Screensaver[field] = restore[field]
            restore[field] = nil
        end
    end
end

local function showWhileAwake()
    if Screensaver.setup == noop then return end
    Screensaver:setup("lockscreen_backdrop")
    Screensaver:show()
    -- Device has two properties that determine if a power key press emits
    -- `Suspend` or `Resume`: screen_saver_mode and screen_saver_lock.
    --
    -- `mode && !lock` => Resume  ("suspended screen saver")
    -- `mode && lock`  => Suspend ("awake screen saver, but still locked")
    -- `!mode`         => Suspend ("awake and unlocked")
    --
    -- Since Screensaver:show() sets `mode = true`, we need to add `lock = true`
    -- in this case, since we keep the device awake.
    Device.screen_saver_lock = true
end

local function totalCleanup()
    uiManagerUtil.closeWidgetsOfClass(ScreenSaverWidget)
    Screensaver:cleanup()
end

return {
    freezeScreensaverAbi = freezeScreensaverAbi,
    unfreezeScreensaverAbi = unfreezeScreensaverAbi,

    showWhileAwake = showWhileAwake,
    totalCleanup = totalCleanup,
}
