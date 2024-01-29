local Flag                 = {}

-- IMAGE
Flag.IMAGE_BACKGROUND_NAME = 'background'
Flag.IMAGE_CROP_NAME       = 'crop'
Flag.IMAGE_DPR_NAME        = 'dpr'
Flag.IMAGE_GRAVITY_NAME    = 'gravity'
Flag.IMAGE_X_NAME          = 'x'
Flag.IMAGE_Y_NAME          = 'y'
Flag.IMAGE_HEIGHT_NAME     = 'height'
Flag.IMAGE_WIDTH_NAME      = 'width'
Flag.IMAGE_RADIUS_NAME     = 'radius'
Flag.IMAGE_QUALITY_NAME    = 'quality'
Flag.IMAGE_MINPAD_NAME     = 'minpad'

-- VIDEO
Flag.VIDEO_BACKGROUND_NAME = 'background'
Flag.VIDEO_CROP_NAME       = 'crop'
Flag.VIDEO_DPR_NAME        = 'dpr'
Flag.VIDEO_X_NAME          = 'x'
Flag.VIDEO_Y_NAME          = 'y'
Flag.VIDEO_HEIGHT_NAME     = 'height'
Flag.VIDEO_WIDTH_NAME      = 'width'

-- Base class method new
function Flag.new(config, name, value)
  local self = {}
  self.config = config
  self.name = name
  self.value = value
  self.isScalable = false
  self.makeDir = true

  if self.name == Flag.IMAGE_HEIGHT_NAME
      or self.name == Flag.IMAGE_WIDTH_NAME
      or self.name == Flag.IMAGE_X_NAME
      or self.name == Flag.IMAGE_Y_NAME
      or self.name == Flag.IMAGE_RADIUS_NAME
      or self.name == Flag.IMAGE_MINPAD_NAME
      or self.name == Flag.VIDEO_HEIGHT_NAME
      or self.name == Flag.VIDEO_WIDTH_NAME
      or self.name == Flag.VIDEO_X_NAME
      or self.name == Flag.VIDEO_Y_NAME
  then
    self.isScalable = true
  end

  if self.name == Flag.IMAGE_DPR_NAME or self.name == Flag.VIDEO_DPR_NAME then
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
    local scaledValue = math.ceil(self.value * (dpr or 1))

    if self.name == Flag.IMAGE_X_NAME
        or self.name == Flag.IMAGE_Y_NAME
        or self.name == Flag.VIDEO_X_NAME
        or self.name == Flag.VIDEO_Y_NAME
    then
      if self.value >= 1 then
        self.value = scaledValue
      end
    else
      self.value = scaledValue
    end

    -- Apply limits
    if self.name == Flag.IMAGE_HEIGHT_NAME
        and self.config.maxImageHeight
        and self.value > self.config.maxImageHeight
    then
      self.value = self.config.maxImageHeight
    end

    if self.name == Flag.IMAGE_WIDTH_NAME
        and self.config.maxImageWidth
        and self.value > self.config.maxImageWidth
    then
      self.value = self.config.maxImageWidth
    end

    if self.name == Flag.VIDEO_HEIGHT_NAME
        and self.config.maxVideoHeight
        and self.value > self.config.maxVideoHeight
    then
      self.value = self.config.maxVideoHeight
    end

    if self.name == Flag.VIDEO_WIDTH_NAME
        and self.config.maxVideoWidth
        and self.value > self.config.maxVideoWidth
    then
      self.value = self.config.maxVideoWidth
    end
  end
end

-- Calculate absolute x/y for values in (0, 1) range
---@param dimension number
function Flag:coordinateToAbsolute(dimension)
  if dimension
      and (self.name == Flag.VIDEO_X_NAME or self.name == Flag.VIDEO_Y_NAME)
      and self.value
      and self.value > 0
      and self.value < 1
  then
    self.value = self.value * dimension
  end
end

return Flag
