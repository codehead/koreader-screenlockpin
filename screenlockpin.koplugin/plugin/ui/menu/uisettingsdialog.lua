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
        {
            icon = "appbar.typeset",
            options = {
                {
                    name = "note_mode",
                    name_text = _("Show notes"),
                    toggle = { C_("Lock screen notes", "off"), C_("Lock screen notes", "button") },
                    args = { "disabled", "button" },
                    values = { "disabled", "button" },
                    event = "SetNoteMode",
                },
                {
                    name = "note_text",
                    name_text = _("Notes text"),
                    item_text = { _("Edit…") },
                    event = "EditNoteText",
                },
            },
        },
        {
            icon = "triangle",
            options = {
                {
                    name = "screenshots_mode",
                    name_text = _("Screenshots"),
                    toggle = { C_("Lock screen screenshots", "prevent"), C_("Lock screen screenshots", "allow") },
                    args = { "prevent", "allow" },
                    values = { "prevent", "allow" },
                    event = "SetScreenshotsMode",
                },
            },
        }
    },
}

function UiSettingsDialog:init()
    self.ui = self
    local uiSettings = pluginSettings.getUiSettings()
    local noteSettings = pluginSettings.getNoteSettings()
    local prevent_screenshots = pluginSettings.getPreventScreenshots()
    self.configurable = {
        ui_scale = uiSettings.scale,
        ui_pos_x = uiSettings.pos_x,
        ui_pos_y = 100 - uiSettings.pos_y,
        note_mode = noteSettings.mode,
        note_text = noteSettings.text,
        screenshots_mode = prevent_screenshots and "prevent" or "allow",
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

function UiSettingsDialog:onSetNoteMode(value)
    pluginSettings.setNoteMode(value)
    self.configurable.note_mode = value
    return true
end

function UiSettingsDialog:onEditNoteText()
    local InputDialog = require("ui/widget/inputdialog")
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen

    local current = self.configurable.note_text or ""
    self._note_input_dialog = InputDialog:new{
        title = _("Lock screen notes (emergency info / contact / etc.)"),
        input = current,
        scroll = true,
        allow_newline = true,
        text_height = Screen:scaleBySize(150),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self._note_input_dialog)
                        self._note_input_dialog = nil
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = self._note_input_dialog:getInputText() or ""
                        pluginSettings.setNoteText(text)
                        self.configurable.note_text = text
                        UIManager:close(self._note_input_dialog)
                        self._note_input_dialog = nil
                    end,
                },
            },
        },
    }
    UIManager:show(self._note_input_dialog)
    self._note_input_dialog:onShowKeyboard()
    return true
end

function UiSettingsDialog:onSetScreenshotsMode(mode)
    pluginSettings.setPreventScreenshots(mode == "prevent")
    self.configurable.screenshots_mode = mode
    return true
end

return UiSettingsDialog
