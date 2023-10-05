local File = require('file')
local utils = require('utils')

local Command = {}

local function getBackgroundImage(config, file, flags)
  local background = flags.background.value
  local inputFilePath = file.originalFilePath
  local backgroundImage = ''

  if background == 'auto' then
    -- Get 2 dominant colors in format 'x000000-x000000'
    local cmd = config.magick .. ' ' .. inputFilePath ..
        ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

    local dominantColors = utils.captureCommandOutput(cmd)

    backgroundImage = inputFilePath .. ' -size 100% gradient:' .. dominantColors .. ' -delete 0 '
  elseif background == 'blurred' then
    backgroundImage = inputFilePath .. ' -gravity center -crop 80%x80% +repage -blur 0x8 '
  else
    backgroundImage = inputFilePath .. ' -size 100% xc:' .. (background or '') .. ' -delete 0 '
  end

  return backgroundImage
end

-- Build image processing command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildImageProcessingCommand(config, file, flags)
  local crop = flags.crop.value
  local gravity = flags.gravity.value
  local x = flags.x.value
  local y = flags.y.value
  local width = flags.width.value
  local height = flags.height.value

  -- Construct a command
  local inputFilePath = file.originalFilePath
  local outputDir = file.cacheDir
  local outputFilePath = file.cachedFilePath

  local executorWithPreset = config.magick .. ' -define png:exclude-chunks=date,time -quality 80 '
  local gravityCommand = (gravity and ' -gravity ' .. gravity .. ' ') or ''
  local backgroundImage = getBackgroundImage(config, file, flags)
  local foregroundImage = inputFilePath .. ' -modulate 100,120,100 '
  local dimensions = (width or '') .. 'x' .. (height or '')

  local command = ''

  -- Gravity is optional only for 'fill', 'lpad' and 'pad' cropping
  -- Background is optional only for 'lpad' and 'pad' cropping
  if crop == 'fill' and (width or height) then
    command =
        executorWithPreset .. gravityCommand ..
        foregroundImage .. ' -resize ' .. dimensions .. '^' .. ' -crop ' .. dimensions .. '+' .. x .. '+' .. y
  elseif crop == 'limited_padding' and (width or height) then
    command =
        executorWithPreset .. gravityCommand ..
        backgroundImage .. ' -resize ' .. dimensions .. '^' .. ' -crop ' .. dimensions .. '+0+0 ' ..
        foregroundImage .. ' -resize ' .. dimensions .. '\\>' ..
        ' -composite'
  elseif crop == 'padding' and (width or height) then
    command =
        executorWithPreset .. gravityCommand ..
        backgroundImage .. ' -resize ' .. dimensions .. '^' .. ' -crop ' .. dimensions .. '+0+0 ' ..
        foregroundImage .. ' -resize ' .. dimensions ..
        ' -composite'
  elseif width or height then
    local forceResizeFlag = (width and height and '! ') or ' '
    command =
        executorWithPreset ..
        foregroundImage .. ' -resize ' .. dimensions .. forceResizeFlag
  end

  if command and command ~= '' then
    os.execute('mkdir -p ' .. outputDir)

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

    command = command .. ' ' .. outputFilePath
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
