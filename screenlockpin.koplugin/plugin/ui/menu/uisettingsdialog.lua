local _ = require("gettext")
local C_ = _.pgettext
local ConfigDialog = require("ui/widget/configdialog")

local pluginSettings = require("plugin/settings")

local UiSettingsDialog = ConfigDialog:extend {
    config_options = {
        prefix = "screenlockpin",
        {
            icon = "zoom.content",
            options = {
                {
                    name = "ui_pos_y",
                    name_text = _("Vertical position"),
                    toggle = { C_("Panel position", "top"), C_("Panel position", "center"), C_("Panel position", "bottom") },
                    values = { 100, 50, 0 },
                    args = { 100, 50, 0 },
                    event = "SetPositionY",
                    more_options = true,
                    more_options_param = {
                        value_min = 0,
                        value_max = 100,
                        value_step = 2,
                        value_hold_step = 10,
                        unit = "%",
                        name = "ui_pos_y",
                        name_text = _("Set vertical panel position (0 = bottom, 100 = top)"),
                        event = "SetPositionY",
                    },
                },
                {
                    name = "ui_pos_x",
                    name_text = _("Horizontal position"),
                    toggle = { C_("Panel position", "left"), C_("Panel position", "center"), C_("Panel position", "right") },
                    values = { 0, 50, 100 },
                    args = { 0, 50, 100 },
                    event = "SetPositionX",
                    more_options = true,
                    more_options_param = {
                        value_min = 0,
                        value_max = 100,
                        value_step = 2,
                        value_hold_step = 10,
                        unit = "%",
                        name = "ui_pos_x",
                        name_text = _("Set horizontal panel position (0 = left, 100 = right)"),
                        event = "SetPositionX",
                    },
                },
                {
                    name = "ui_scale",
                    name_text = _("Panel size"),
                    toggle = { C_("Panel size", "small"), C_("Panel size", "medium"), C_("Panel size", "large") },
                    values = { 0, 40, 100 },
                    args = { 0, 40, 100 },
                    event = "SetScale",
                    more_options = true,
                    more_options_param = {
                        value_min = 0,
                        value_max = 100,
                        value_step = 2,
                        value_hold_step = 10,
                        unit = "%",
                        name = "ui_scale",
                        name_text = _("Set panel size (0 = small, 100 = large)"),
                        event = "SetScale",
                    },
                },
            },
        },
    },
}

function UiSettingsDialog:init()
    self.ui = self
    local uiSettings = pluginSettings.getUiSettings()
    self.configurable = {
        ui_scale = uiSettings.scale,
        ui_pos_x = uiSettings.pos_x,
        ui_pos_y = 100 - uiSettings.pos_y,
    }
    ConfigDialog.init(self)
end

function UiSettingsDialog:onSetPositionX(value)
    pluginSettings.setUiSetting("pos_x", value)
    self.configurable.ui_pos_x = value
    return true
end

function UiSettingsDialog:onSetPositionY(value)
    pluginSettings.setUiSetting("pos_y", 100 - value)
    self.configurable.ui_pos_y = value
    return true
end

function UiSettingsDialog:onSetScale(value)
    pluginSettings.setUiSetting("scale", value)
    self.configurable.ui_scale = value
    return true
end

return UiSettingsDialog
