local Flag = {}

Flag.IMAGE_BACKGROUND_NAME = 'background'
Flag.IMAGE_CROP_NAME = 'crop'
Flag.IMAGE_DPR_NAME = 'dpr'
Flag.IMAGE_GRAVITY_NAME = 'gravity'
Flag.IMAGE_X_NAME = 'x'
Flag.IMAGE_Y_NAME = 'y'
Flag.IMAGE_HEIGHT_NAME = 'height'
Flag.IMAGE_WIDTH_NAME = 'width'
Flag.IMAGE_RADIUS_NAME = 'radius'
Flag.IMAGE_QUALITY_NAME = 'quality'

local IMAGE_DEFAULTS = {
  [Flag.IMAGE_BACKGROUND_NAME] = 'white',
  [Flag.IMAGE_DPR_NAME] = 1,
  [Flag.IMAGE_GRAVITY_NAME] = 'center',
  [Flag.IMAGE_X_NAME] = 0,
  [Flag.IMAGE_Y_NAME] = 0,
  [Flag.IMAGE_RADIUS_NAME] = 0.1,
  [Flag.IMAGE_QUALITY_NAME] = 80
}

-- Base class method new
function Flag.new(name, value)
  local self = {}
  self.name = name
  self.value = value or IMAGE_DEFAULTS[name]

  setmetatable(self, { __index = Flag })
  return self
end

-- Derived class method setValue
---@param value string | number
---@param valueMapper string | number
function Flag:setValue(value, valueMapper)
  if value and value ~= '' then
    -- Check if it is an allowed text flag or cast to a number
    self.value = valueMapper[value] or tonumber(value)
  end
end

-- Apply limits to a given dimension
---@param dpr number
---@param max number
function Flag:scaleDimension(dpr, max)
  if (self.name == Flag.IMAGE_HEIGHT_NAME or self.name == Flag.IMAGE_WIDTH_NAME) and self.value and dpr then
    self.value = math.ceil(self.value * dpr)

    if self.value > max then
      self.value = max
    end
  end
end

return Flag
