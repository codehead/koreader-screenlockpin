local _ = require("gettext")
local logger = require("logger")
local Device = require("device")
local ffiutil = require("ffi/util")
local UIManager = require("ui/uimanager")
local Screensaver = require("ui/screensaver")
local InfoMessage = require("ui/widget/infomessage")
local Screen = Device.screen
local T = ffiutil.template

local pluginSettings = require("plugin/settings")
local screensaverUtil = require("plugin/util/screensaverutil")
local screenshoterUtil = require("plugin/util/screenshoterutil")
local NotesFrame = require("plugin/ui/lockscreen/notesframe")
local LockScreenFrame = require("plugin/ui/lockscreen/lockscreenframe")

local overlay
local notes

local function relayout(refreshmode)
    overlay:relayout(nil)
    if Screensaver.screensaver_widget then
        Screensaver.screensaver_widget:update()
    end
    UIManager:setDirty("all", refreshmode)
end

local function onSetRotationMode(_, mode)
    if not overlay then return end
    local old_mode = Screen:getRotationMode()
    if mode ~= nil and mode ~= old_mode then
        logger.dbg("ScreenLockPin: update rotation from " .. old_mode .. " to " .. mode)
        Screen:setRotationMode(mode)
        relayout("full")
    end
end

local function onScreenResize()
    if not overlay then return end
    logger.dbg("ScreenLockPin: handle screen resize")
    relayout("full")
end

local function formatAttempts()
    local attempts_by_length = pluginSettings.readPersistentCache("attempts_by_length") or {}
    local str = ""
    for len, attempts in pairs(attempts_by_length) do
        if str ~= "" then str = str .. "\n" end
        local line = "  " .. T(_("Length %1: %2 attempts"), len, attempts)
        str = str .. line
    end
    return str
end

local function closeLockScreenDueToUnlock()
    if not overlay then return end
    logger.dbg("ScreenLockPin: close lock screen")
    screensaverUtil.unfreezeScreensaverAbi()
    screensaverUtil.totalCleanup()
    screenshoterUtil.unfreezeScreenshoterAbi()
    UIManager:close(overlay, "full", overlay:getRefreshRegion())
    overlay = nil
    local throttled_times = pluginSettings.readPersistentCache("throttled_times") or 0
    if throttled_times >= 2 then
        UIManager:show(InfoMessage:new{
            text = T(_("Caution!\nHigh amount of failed PIN inputs detected.\n%1"), formatAttempts()),
            icon = "notice-warning",
        })
        pluginSettings.putPersistentCache("throttled_times", 0)
        pluginSettings.putPersistentCache("attempts_by_length", nil)
    end
end

local function onSuspend()
    if notes then
        UIManager:close(notes)
        notes = nil
    end
    if not overlay then return end
    Device.screen_saver_lock = false
    overlay:setVisible(false)
    UIManager:setDirty("all", "full", overlay:getRefreshRegion())
end

local function reuseShowOverlay()
    logger.dbg("ScreenLockPin: clear & show lock")
    overlay:clearInput()
    overlay:setVisible(true)
    UIManager:setDirty(overlay, "full", overlay:getRefreshRegion())
end

local function onResume()
    if not pluginSettings.shouldLockOnWakeup() then return end
    if not overlay then return end
    Device.screen_saver_lock = true
    reuseShowOverlay()
end

local function showNotes()
    if notes or not overlay then return end
    local text = pluginSettings.getNoteSettings().text or _("No note configured.")
    local scale = pluginSettings.getUiSettings().scale / 100
    notes = NotesFrame:new {
        text = text,
        region = overlay._content_region,
        scale = scale,
        on_close = function()
            UIManager:close(notes, "ui", notes.region)
            notes = nil
        end
    }
    UIManager:show(notes, "ui", notes.region)
end

local function showOrClearLockScreen(cause)
    if cause == "resume" and overlay then
        logger.dbg("ScreenLockPin: ignoring duplicate resume trigger")
        -- ignore duplicate resume (triggered by plugin:onResume), it's already
        -- been handled by widget:onResume (while overlay is shown)
        return
    end
    logger.dbg("ScreenLockPin: show lock screen (" .. cause .. ")")
    if overlay then return reuseShowOverlay() end
    logger.dbg("ScreenLockPin: create lock screen")
    screensaverUtil.freezeScreensaverAbi()
    screenshoterUtil.freezeScreenshoterAbi()
    overlay = LockScreenFrame:new {
        -- UIManager performance tweaks
        modal = true,
        disable_double_tap = true,
        -- UIManager hook (called on ui root elements): handle rotation if not locked to orientation
        onSetRotationMode = onSetRotationMode,
        -- UIManager hook (called on ui root elements)
        onScreenResize = onScreenResize,
        -- UIManager hook (called on ui root elements)
        onSuspend = onSuspend,
        -- UIManager hook (called on ui root elements)
        onResume = onResume,
        -- LockScreenFrame
        on_unlock = closeLockScreenDueToUnlock,
        on_show_notes = showNotes,
    }
    UIManager:show(overlay, "full", overlay:getRefreshRegion())
end

return {
    showOrClearLockScreen = showOrClearLockScreen,
}
