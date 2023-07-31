local Flag = {}

Flag.IMAGE_BACKGROUND_NAME = 'background'
Flag.IMAGE_CROP_NAME = 'crop'
Flag.IMAGE_DPR_NAME = 'dpr'
Flag.IMAGE_GRAVITY_NAME = 'gravity'
Flag.IMAGE_X_NAME = 'x'
Flag.IMAGE_Y_NAME = 'y'
Flag.IMAGE_HEIGHT_NAME = 'height'
Flag.IMAGE_WIDTH_NAME = 'width'

local IMAGE_DEFAULTS = {
  [Flag.IMAGE_BACKGROUND_NAME] = 'white',
  [Flag.IMAGE_DPR_NAME] = 1,
  [Flag.IMAGE_GRAVITY_NAME] = 'center',
  [Flag.IMAGE_X_NAME] = 0,
  [Flag.IMAGE_Y_NAME] = 0,
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
---@param d number
---@param dpr number
---@param max number
---@return number?
function Flag.limitDimension(d, dpr, max)
  if d and dpr and max then
    local dimension = d and dpr and math.ceil(d * dpr)
    if dimension > max then
      return max
    end

    return dimension
  end

  return nil
end

return Flag
