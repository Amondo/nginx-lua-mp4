local Flag = {
  -- IMAGE
  IMAGE_BACKGROUND_KEY = 'image_background',
  IMAGE_CROP_KEY       = 'image_crop',
  IMAGE_DPR_KEY        = 'image_dpr',
  IMAGE_GRAVITY_KEY    = 'image_gravity',
  IMAGE_X_KEY          = 'image_x',
  IMAGE_Y_KEY          = 'image_y',
  IMAGE_HEIGHT_KEY     = 'image_height',
  IMAGE_WIDTH_KEY      = 'image_width',
  IMAGE_RADIUS_KEY     = 'image_radius',
  IMAGE_QUALITY_KEY    = 'image_quality',
  IMAGE_MINPAD_KEY     = 'image_minpad',

  -- VIDEO
  VIDEO_BACKGROUND_KEY = 'video_background',
  VIDEO_CROP_KEY       = 'video_crop',
  VIDEO_DPR_KEY        = 'video_dpr',
  VIDEO_X_KEY          = 'video_x',
  VIDEO_Y_KEY          = 'video_y',
  VIDEO_HEIGHT_KEY     = 'video_height',
  VIDEO_WIDTH_KEY      = 'video_width',
  VIDEO_RADIUS_KEY     = 'video_radius',
  VIDEO_MINPAD_KEY     = 'video_minpad',
}


Flag.DEFAULTS = {
  [Flag.IMAGE_BACKGROUND_KEY] = {
    name = 'background',
    value = 'white',
    isScalable = false,
    makeDir = true,
  },
  [Flag.IMAGE_CROP_KEY] = {
    name = 'crop',
    value = nil,
    isScalable = false,
    makeDir = true,
  },
  [Flag.IMAGE_DPR_KEY] = {
    name = 'dpr',
    value = 1,
    isScalable = false,
    makeDir = false,
  },
  [Flag.IMAGE_GRAVITY_KEY] = {
    name = 'gravity',
    value = 'center',
    isScalable = false,
    makeDir = true,
  },
  [Flag.IMAGE_X_KEY] = {
    name = 'x',
    value = 0,
    isScalable = true,
    makeDir = true,
  },
  [Flag.IMAGE_Y_KEY] = {
    name = 'y',
    value = 0,
    isScalable = true,
    makeDir = true,
  },
  [Flag.IMAGE_HEIGHT_KEY] = {
    name = 'height',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.IMAGE_WIDTH_KEY] = {
    name = 'width',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.IMAGE_RADIUS_KEY] = {
    name = 'radius',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.IMAGE_QUALITY_KEY] = {
    name = 'quality',
    value = 80,
    isScalable = false,
    makeDir = true,
  },
  [Flag.IMAGE_MINPAD_KEY] = {
    name = 'minpad',
    value = nil,
    isScalable = true,
    makeDir = true,
  },

  -- VIDEO
  [Flag.VIDEO_BACKGROUND_KEY] = {
    name = 'background',
    value = 'black',
    isScalable = false,
    makeDir = true,
  },
  [Flag.VIDEO_CROP_KEY] = {
    name = 'crop',
    value = nil,
    isScalable = false,
    makeDir = true,
  },
  [Flag.VIDEO_DPR_KEY] = {
    name = 'dpr',
    value = 1,
    isScalable = false,
    makeDir = false,
  },
  [Flag.VIDEO_X_KEY] = {
    name = 'x',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.VIDEO_Y_KEY] = {
    name = 'y',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.VIDEO_HEIGHT_KEY] = {
    name = 'height',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.VIDEO_WIDTH_KEY] = {
    name = 'width',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.VIDEO_RADIUS_KEY] = {
    name = 'radius',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
  [Flag.VIDEO_MINPAD_KEY] = {
    name = 'minpad',
    value = nil,
    isScalable = true,
    makeDir = true,
  },
}

-- Base class method new
function Flag.new(key, value)
  local self = {}

  local defaults = Flag.DEFAULTS[key]

  if defaults then
    self.name = defaults.name
    self.value = defaults.value
    self.key = key
    self.isScalable = defaults.isScalable
    self.makeDir = defaults.makeDir

    -- if value and value ~= '' then
    --   -- Check if it is an allowed text flag or cast to a number
    --   self.value = valueMapper[value] or tonumber(value)
    -- end

    setmetatable(self, { __index = Flag })
    return self
  end
end

-- Derived class method setValue
---@param value string | number
---@param valueMapper table
function Flag:setValue(value, valueMapper)
  if value and value ~= '' then
    -- Check if it is an allowed text flag or cast to a number
    self.value = (valueMapper and valueMapper[value]) or tonumber(value)
  end
end

-- Scale dimension
---@param multiplier number
function Flag:scale(multiplier)
  if not self.value or self.value == '' then
    return
  end

  local scaledValue = math.ceil(self.value * (multiplier or 1))

  if self.key == Flag.IMAGE_X_KEY
      or self.key == Flag.IMAGE_Y_KEY
      or self.key == Flag.VIDEO_X_KEY
      or self.key == Flag.VIDEO_Y_KEY
  then
    if self.value >= 1 then
      self.value = scaledValue
    end
  else
    self.value = scaledValue
  end
end

-- Calculate absolute x/y for values in (0, 1) range
---@param dimension number
function Flag:coordinateToAbsolute(dimension)
  if dimension
      -- and (self.key == Flag.VIDEO_X_KEY or self.key == Flag.VIDEO_Y_KEY)
      and self.value
      and self.value > 0
      and self.value < 1
  then
    self.value = self.value * dimension
  end
end

return Flag
