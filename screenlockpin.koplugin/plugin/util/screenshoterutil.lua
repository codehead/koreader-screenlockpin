local logger = require("logger")
local Screenshoter = require("ui/widget/screenshoter")

local function noop() end

local FIELDS = { "onKeyPressShoot", "onTapDiagonal", "onSwipeDiagonal" }
local restore = {}

local function freezeScreenshoterAbi()
    for _, field in ipairs(FIELDS) do
        if restore[field] == nil then
            logger.dbg("ScreenLockPin: monkey-patching Screenshoter." .. field .. " to noop")
            restore[field] = Screenshoter[field]
            Screenshoter[field] = noop
        end
    end
end

local function unfreezeScreenshoterAbi()
    for _, field in ipairs(FIELDS) do
        if restore[field] ~= nil then
            logger.dbg("ScreenLockPin: restoring original Screenshoter." .. field)
            Screenshoter[field] = restore[field]
            restore[field] = nil
        end
    end
end

return {
    freezeScreenshoterAbi = freezeScreenshoterAbi,
    unfreezeScreenshoterAbi = unfreezeScreenshoterAbi,
}
