local _ = require("gettext")
local logger = require("logger")
local Dispatcher = require("dispatcher")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local EventListener = require("ui/widget/eventlistener")

local ScreenLockPinPublicApi = require("plugin/publicapi")
local pluginMenu = require("plugin/menu")
local pluginSettings = require("plugin/settings")
local pluginUpdater = require("plugin/updater")
local onBootHook = require("plugin/util/onboothook")
local screensaverUtil = require("plugin/util/screensaverutil")
local lockscreenCtrl = require("plugin/ui/ctrl/lockscreenctrl")

local ScreenLockPinPlugin = EventListener:extend {}

pluginSettings.init()

logger.dbg("ScreenLockPin: monkey-patching UIManager:run")
onBootHook.enable(function() ScreenLockPinPlugin.onBoot() end)

function ScreenLockPinPlugin:init()
    logger.dbg("ScreenLockPin: plugin init")
    Dispatcher:registerAction("screenlockpin_enable", {
        category  = "none",
        event     = "EnableLockScreen",
        title     = _("Enable lock screen"),
        device    = true,
    })
    Dispatcher:registerAction("screenlockpin_disable", {
        category  = "none",
        event     = "DisableLockScreen",
        title     = _("Disable lock screen"),
        device    = true,
    })
    Dispatcher:registerAction("screenlockpin_toggle", {
        category  = "none",
        event     = "ToggleLockScreenEnabled",
        title     = _("En/disable lock screen"),
        device    = true,
    })
    Dispatcher:registerAction("screenlockpin_lock", {
        category  = "none",
        event     = "LockScreen",
        title     = _("Lock the device"),
        device    = true,
    })
    Dispatcher:registerAction("screenlockpin_unlock", {
        category  = "none",
        event     = "UnlockScreen",
        title     = _("Unlock the device"),
        device    = true,
        separator = true,
    })
    self.ui.menu:registerToMainMenu({
        addToMainMenu = function(_, menu_items)
            logger.dbg("ScreenLockPin: adding menu")
            menu_items.screen_lockpin_reset = pluginMenu
        end
    })

    self.public_api = ScreenLockPinPublicApi
    PluginShare.screen_lock_pin = self.public

    UIManager:nextTick(function()
        local check_interval = pluginSettings.getCheckUpdateInterval()
        if check_interval > 0 then
            pluginUpdater.enableAutoChecks({
                min_seconds_between_checks = check_interval,
                min_seconds_between_remind = pluginSettings.getUpdateReminderInterval(),
            })
        end
    end)

    -- todo performance: register pluginshare.plugin_updater.pauseAllWhile() for efficient pause re-schedule
end

-- KOReader dispatcher actions (registered in ScreenLockPinPlugin:init)

function ScreenLockPinPlugin:onEnableLockScreen()
    self.public_api:enable("event")
    Notification:notify(_("Lock Screen Enabled."), Notification.SOURCE_DISPATCHER)
    return true
end

function ScreenLockPinPlugin:onDisableLockScreen()
    self.public_api:disable("event")
    Notification:notify(_("Lock Screen Disabled."), Notification.SOURCE_DISPATCHER)
    return true
end

function ScreenLockPinPlugin:onToggleLockScreenEnabled()
    if pluginSettings.getEnabled() then
        self:onDisableLockScreen()
    else
        self:onEnableLockScreen()
    end
    return true
end

function ScreenLockPinPlugin:onLockScreen()
    self.public_api:lock("event")
    return true
end

function ScreenLockPinPlugin:onUnlockScreen()
    self.public_api:unlock("event")
    return true
end

-- KOReader plugin hook (on plugin disable)

function ScreenLockPinPlugin.stopPlugin()
    logger.dbg("ScreenLockPin: disable plugin")
    onBootHook.disable()
    pluginSettings.purge()
    PluginShare.screen_lock_pin = nil
    pluginUpdater.disableAutoChecks()
    return true
end

-- KOReader plugin hook (on wakeup after suspend)

function ScreenLockPinPlugin.onResume()
    if not pluginSettings.getEnabled() then return end
    if not pluginSettings.shouldLockOnWakeup() then return end
    -- we hijacked the screensaver_delay (property of ui/screensaver.lua)
    -- any unknown values will be interpreted as "tap to exit from screensaver"
    -- this enables us to create a lock screen first before closing the
    -- screensaver. We get the responsibility to close the widget later…
    lockscreenCtrl.showOrClearLockScreen("resume")
end

-- Monkey-patched hook (registered via onBootHook)

function ScreenLockPinPlugin.onBoot()
    if not pluginSettings.getEnabled() then return end
    if not pluginSettings.shouldLockOnBoot() then return end
    logger.dbg("ScreenLockPin: lock on boot")
    screensaverUtil.showWhileAwake("lockonboot")
    lockscreenCtrl.showOrClearLockScreen("boot")
end

--

return ScreenLockPinPlugin
