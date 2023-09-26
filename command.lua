local File = require('file')
local utils = require('utils')

local Command = {}

-- Build image processing command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildImageProcessingCommand(config, file, flags)
  local cacheDir = file.cacheDir
  local cachedFilePath = file.cachedFilePath
  local originalFilePath = file.originalFilePath

  local background = flags.background.value
  local crop = flags.crop.value
  local gravity = flags.gravity.value
  local x = flags.x.value
  local y = flags.y.value
  local width = flags.width.value
  local height = flags.height.value

  -- Construct a command
  local command
  if width or height then
    -- Create cached transcoded file
    os.execute('mkdir -p ' .. cacheDir)

    --- Init with processor
    command = config.magick .. ' -define png:exclude-chunks=date,time -quality 80'

    if gravity then
      command = command .. ' -gravity ' .. gravity
    end

    -- Create Canvas
    command = command .. ' -size $(' .. config.identify .. ' -ping -format "%wx%h" ' .. originalFilePath .. ')'
    if background == 'auto' then
      -- Get 2 dominant colors in format 'x000000-x000000'
      local cmd = config.magick .. ' ' .. originalFilePath ..
          ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

      local dominantColors = utils.captureCommandOutput(cmd)

      command = command .. ' gradient:' .. dominantColors
    else
      command = command .. ' xc:' .. (background or '')
    end

    -- Crop and resize
    local dimensions = (width or '') .. 'x' .. (height or '')
    local resizeFlag = (width and height and '!') or ''

    if crop == 'padding' then
      command = command ..
          ' -resize ' .. dimensions .. resizeFlag .. ' ' ..
          originalFilePath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions ..
          ' -composite'
    end

    if crop == 'limited_padding' then
      command = command ..
          ' -resize ' .. dimensions .. resizeFlag .. ' ' ..
          originalFilePath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions .. '\\>' ..
          ' -composite'
    end

    if crop == 'fill' then
      command = command .. ' ' ..
          originalFilePath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions .. '^' ..
          ' -composite' ..
          ' -crop ' .. dimensions .. '+' .. x .. '+' .. y
    end

    if crop == nil then
      command = command .. ' ' ..
          originalFilePath .. ' -modulate 100,120,100' ..
          ' -composite' ..
          ' -resize ' .. dimensions .. resizeFlag
    end

    -- Remove color profiles
    if config.stripColorProfile then
      command = command .. ' -strip'
    end

    -- Apply selected color profile
    if config.colorProfilePath ~= '' and File.fileExists(config.colorProfilePath) then
      command = command .. ' -profile /home/nginx/sRGB.icc'
    end

    -- Append the output filepath to the convert command
    command = command .. ' ' .. cachedFilePath
  end

  if command and config.logTime then
    command = 'time ' .. command
  end

  return command
end

-- Build video processing command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildVideoProcessingCommand(config, file, flags)
  return ''
end

-- Build command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildCommand(config, file, flags)
  if file.mediaType == File.IMAGE_TYPE then
    return buildImageProcessingCommand(config, file, flags)
  end

  if file.mediaType == File.VIDEO_TYPE then
    return buildVideoProcessingCommand(config, file, flags)
  end

  return ''
end

-- Base class method new
---@param config table
---@param file table
---@param flags table
function Command.new(config, file, flags)
  local self = {
    command = buildCommand(config, file, flags),
  }
  setmetatable(self, { __index = Command })
  return self
end

-- Execute command
---@return boolean?
function Command:execute()
  if self.command and self.command ~= '' then
    return os.execute(self.command)
  end
end

return Command
