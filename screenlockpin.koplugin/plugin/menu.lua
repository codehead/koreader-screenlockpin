local _ = require("gettext")

local pluginSettings = require("plugin/settings")
local settingsCtrl = require("plugin/ui/ctrl/settingsctrl")

local function options_enabled()
    return pluginSettings.getEnabled()
end

return {
    sorting_hint = "screen",
    text = _("Lock screen"),
    sub_item_table = {
        {
            text = _("Enable"),
            checked_func = options_enabled,
            check_callback_updates_menu = true,
            callback = function (menu_instance)
                pluginSettings.toggleEnabled()
                menu_instance:updateItems()
            end,
            separator = true,
        },
        {
            text = _("Lock on wakeup"),
            enabled_func = options_enabled,
            checked_func = pluginSettings.shouldLockOnWakeup,
            callback = pluginSettings.toggleLockOnWakeup,
        },
        {
            text = _("Lock on boot"),
            enabled_func = options_enabled,
            checked_func = pluginSettings.shouldLockOnBoot,
            callback = pluginSettings.toggleLockOnBoot,
            separator = true,
        },
        {
            text = _("Lock screen options"),
            enabled_func = options_enabled,
            callback = settingsCtrl.showUiSettingsDialog,
            separator = true,
        },
        {
            text = _("Change PIN"),
            enabled_func = options_enabled,
            callback = settingsCtrl.showChangePinDialog,
        },
    }
}
