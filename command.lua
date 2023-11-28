local File = require('file')
local Flag = require('flag')
local utils = require('utils')

local Command = {}

local function getCanvas(config, file, flags)
  local background = flags[Flag.IMAGE_BACKGROUND_NAME].value
  local canvas = ''

  if background == 'auto' then
    -- Get 2 dominant colors in format 'x000000-x000000'
    local cmd = config.magick .. ' ' .. file.originalFilePath ..
        ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

    local dominantColors = utils.captureCommandOutput(cmd)

    canvas = file.originalFilePath .. ' -size %wx%h gradient:' .. dominantColors .. ' -delete 0 '
  elseif background == 'blurred' then
    canvas = file.originalFilePath .. ' -crop 80%x80% +repage -blur 0x8 '
  else
    canvas = file.originalFilePath .. ' -size %wx%h xc:' .. (background or '') .. ' -delete 0 '
  end

  return canvas
end

-- Build image processing command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildImageProcessingCommand(config, file, flags)
  local crop = flags[Flag.IMAGE_CROP_NAME].value
  local gravity = flags[Flag.IMAGE_GRAVITY_NAME].value
  local x = flags[Flag.IMAGE_X_NAME].value
  local y = flags[Flag.IMAGE_Y_NAME].value
  local width = flags[Flag.IMAGE_WIDTH_NAME].value
  local height = flags[Flag.IMAGE_HEIGHT_NAME].value
  local radius = flags[Flag.IMAGE_RADIUS_NAME].value
  local quality = flags[Flag.IMAGE_QUALITY_NAME].value

  -- Construct a command
  local command = ''
  local executorWithPreset = config.magick ..
      ' -define png:exclude-chunks=date,time' ..
      ' -quality ' .. quality ..
      ' -gravity ' .. gravity .. ' '
  local canvas = getCanvas(config, file, flags)
  local image = file.originalFilePath .. ' -modulate 100,120,100 '
  local mask =
      '-size %[origwidth]x%[origheight]' ..
      ' xc:black' ..
      ' -fill white' ..
      ' -draw "roundrectangle 0,0,%[origwidth],%[origheight],' .. radius .. ',' .. radius .. '"' ..
      ' -alpha Copy'
  local dimensions = (width or '') .. 'x' .. (height or '')

  if crop == 'fill' and (width or height) then
    command = executorWithPreset ..
        canvas ..
        ' -resize ' .. dimensions .. '^' ..
        ' -crop ' .. dimensions .. '+' .. x .. '+' .. y ..
        ' \\( ' ..
        image ..
        ' -resize ' .. dimensions .. '^' ..
        ' -crop ' .. dimensions .. '+' .. x .. '+' .. y ..
        ' -set option:origwidth %w' ..
        ' -set option:origheight %h' ..
        ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite' ..
        ' \\) -compose over -composite'
  elseif crop == 'limited_padding' and (width or height) then
    command = executorWithPreset ..
        canvas ..
        ' -resize ' .. dimensions .. '^' ..
        ' -crop ' .. dimensions .. '+0+0 ' ..
        ' \\( ' ..
        image ..
        ' -resize ' .. dimensions .. '\\>' ..
        ' -set option:origwidth %w' ..
        ' -set option:origheight %h' ..
        ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite' ..
        ' \\) -compose over -composite'
  elseif crop == 'padding' and (width or height) then
    command = executorWithPreset ..
        canvas ..
        ' -resize ' .. dimensions .. '^' ..
        ' -crop ' .. dimensions .. '+0+0 ' ..
        ' \\( ' ..
        image ..
        ' -resize ' .. dimensions ..
        ' -set option:origwidth %w' ..
        ' -set option:origheight %h' ..
        ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite' ..
        ' \\) -compose over -composite'
  elseif width or height then
    local forceResizeFlag = (width and height and '! ') or ''

    command = executorWithPreset ..
        canvas ..
        ' -resize ' .. dimensions .. forceResizeFlag ..
        ' \\( ' ..
        image ..
        ' -resize ' .. dimensions .. forceResizeFlag ..
        ' -set option:origwidth %w' ..
        ' -set option:origheight %h' ..
        ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite' ..
        ' \\) -compose over -composite'
  end

  if command and command ~= '' then
    os.execute('mkdir -p ' .. file.cacheDir)

    if config.logTime then
      command = 'time ' .. command
    end

    -- Remove color profiles
    if config.stripColorProfile then
      command = command .. ' -strip'
    end

    -- Apply selected color profile
    if config.colorProfilePath ~= '' and File.fileExists(config.colorProfilePath) then
      command = command .. ' -profile ' .. config.colorProfilePath
    end

    command = command .. ' ' .. file.cachedFilePath
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
  if file.type == File.IMAGE_TYPE then
    return buildImageProcessingCommand(config, file, flags)
  end

  if file.type == File.VIDEO_TYPE then
    return buildVideoProcessingCommand(config, file, flags)
  end

  return ''
end

-- Base class method new
---@param config table
---@param file table
---@param flags table
function Command.new(config, file, flags)
  local self = {}

  self.command = buildCommand(config, file, flags)
  self.isValid = self.command ~= nil

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
