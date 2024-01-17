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
Flag.IMAGE_MINPAD_NAME = 'minpad'

local IMAGE_DEFAULTS = {
  [Flag.IMAGE_BACKGROUND_NAME] = 'white',
  [Flag.IMAGE_GRAVITY_NAME] = 'center',
  [Flag.IMAGE_X_NAME] = 0,
  [Flag.IMAGE_Y_NAME] = 0,
  [Flag.IMAGE_QUALITY_NAME] = 80
}

-- Base class method new
function Flag.new(config, name, value)
  local self = {}
  self.config = config
  self.name = name
  self.value = value or IMAGE_DEFAULTS[name]
  self.isScalable = false
  self.makeDir = true

  if self.name == Flag.IMAGE_HEIGHT_NAME or self.name == Flag.IMAGE_WIDTH_NAME or self.name == Flag.IMAGE_RADIUS_NAME or self.name == Flag.IMAGE_MINPAD_NAME then
    self.isScalable = true
  end

  if self.name == Flag.IMAGE_DPR_NAME then
    self.makeDir = false
  end

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

-- Scale dimension
---@param dpr number
function Flag:scale(dpr)
  if self.value and self.value ~= '' then
    self.value = math.ceil(self.value * (dpr or 1))

    -- Apply limits
    if self.name == Flag.IMAGE_HEIGHT_NAME and self.config.maxImageHeight and self.value > self.config.maxImageHeight then
      self.value = self.config.maxImageHeight
    end

    if self.name == Flag.IMAGE_WIDTH_NAME and self.config.maxImageWidth and self.value > self.config.maxImageWidth then
      self.value = self.config.maxImageWidth
    end
  end
end

return Flag
