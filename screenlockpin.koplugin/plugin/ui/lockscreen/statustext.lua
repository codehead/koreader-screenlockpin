local Device = require("device")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local BD = require("ui/bidi")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local TextWidget = require("ui/widget/textwidget")
local T = ffiUtil.template

local function render_time()
    local clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    return "⌚ " .. clock
end

local function render_battery()
    if not Device:hasBattery() then return nil end

    local icon = ""
    local powerd = Device:getPowerDevice()
    local charge = powerd:getCapacity()
    local is_charging = false

    if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
        is_charging = powerd:isAuxCharging()
        charge = charge + powerd:getAuxCapacity()
        icon = powerd:getBatterySymbol(powerd:isAuxCharged(), is_charging, charge / 2)
    else
        is_charging = powerd:isCharging()
        icon = powerd:getBatterySymbol(powerd:isCharged(), is_charging, charge)
    end

    return BD.wrap(icon) .. " " .. (is_charging and "+" or "") .. charge .. "%"
end

local function render_frontlight()
    if not Device:hasFrontlight() then return nil end

    local icon = "☼"
    local powerd = Device:getPowerDevice()
    if powerd:isFrontlightOn() then
        if Device:isCervantes() or Device:isKobo() then
            return (icon .. " %d%%"):format(powerd:frontlightIntensity())
        else
            return (icon .. " %d"):format(powerd:frontlightIntensity())
        end
    else
        icon = "✺"
        return T(_("%1 Off"), icon)
    end
end

local LockScreenStatusText = TextWidget:extend {
    font = "ffont",
    font_size = 12,
    on_change = nil,
}

function LockScreenStatusText:init()
    self:resume()
    self.face = Font:getFace(self.font, self.font_size)
end

function LockScreenStatusText:free()
    self:pause()
    TextWidget.free(self)
end

function LockScreenStatusText:refreshText()
    local time = render_time()
    local battery = render_battery()
    local frontlight = render_frontlight()
    local arr = {}
    if frontlight then table.insert(arr, frontlight) end
    if battery then table.insert(arr, battery) end
    if time then table.insert(arr, time) end
    local prev_text = self.text
    self:setText(table.concat(arr, "   "))
    if self.text ~= prev_text then self.on_change() end
end

function LockScreenStatusText:interval()
    self:refreshText()
    -- schedule next auto refresh at full minute
    UIManager:scheduleIn(60 - (os.time() % 60), self.interval, self)
end

function LockScreenStatusText:pause() UIManager:unschedule(self.interval) end
LockScreenStatusText.resume = LockScreenStatusText.interval

LockScreenStatusText.onFrontlightStateChanged = LockScreenStatusText.refreshText
LockScreenStatusText.onCharging               = LockScreenStatusText.refreshText
LockScreenStatusText.onNotCharging            = LockScreenStatusText.refreshText

return LockScreenStatusText
