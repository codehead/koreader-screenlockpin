local BD = require("ui/bidi")
local util = require("util")
local HorizontalGroup = require("ui/widget/horizontalgroup")

local HorizontalFlexGroup = HorizontalGroup:extend{
    width = nil,
    padding = 0,
}

function HorizontalFlexGroup:getSize()
    if not self._size then
        local mirrorItems = self.allow_mirroring and BD.mirroredUILayout()
        local items_w = 0
        self._size = { w = self.width, h = 0 }
        self._offsets = { }
        if mirrorItems then util.arrayReverse(self) end
        for i, widget in ipairs(self) do
            local w_size = widget:getSize()
            self._offsets[i] = {
                x = self.padding + items_w,
                y = w_size.h
            }
            items_w = items_w + w_size.w
            if w_size.h > self._size.h then
                self._size.h = w_size.h
            end
        end
        local flex_w = self.width - 2 * self.padding - items_w
        if flex_w > 0 then self:_rejustify(flex_w) end
        if mirrorItems then util.arrayReverse(self) end
    end
    return self._size
end

function HorizontalFlexGroup:_rejustify(free_space_w)
    if #self == 0 then return end
    if #self == 1 then
        -- single item => move to center
        self._offsets[1].x = self._offsets[1].x + math.floor(free_space_w / 2)
        return
    end
    -- multiple items => flex in between
    local spaces_left = #self - 1
    for i = 2, #self do
        local space_w = math.floor(free_space_w / spaces_left)
        free_space_w = free_space_w - space_w
        self._offsets[i].x = self._offsets[i].x + space_w
        spaces_left = spaces_left - 1
    end
end

function HorizontalFlexGroup:setWidth(width)
    self.width = width
    self:resetLayout()
end

return HorizontalFlexGroup
