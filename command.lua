local File = require('file')
local Flag = require('flag')
local utils = require('utils')

local Command = {}

local function getCanvas(config, file, flags)
  local background = flags[Flag.IMAGE_BACKGROUND_KEY] and flags[Flag.IMAGE_BACKGROUND_KEY].value
  local canvas = ''

  if background == 'auto' then
    -- Get 2 dominant colors in format 'x000000-x000000'
    local cmd = config.magick .. ' ' .. file.originalFilePath ..
        ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

    local dominantColors = utils.captureCommandOutput(cmd)

    canvas = file.originalFilePath .. ' -size %wx%h gradient:' .. dominantColors .. ' -delete 0 '
  elseif background == 'blurred' then
    canvas = file.originalFilePath .. ' -crop 80%x80% +repage -scale 10% -blur 0x2.5 -resize 1000% '
  else
    canvas = file.originalFilePath .. ' -size %wx%h xc:' .. (background or '') .. ' -delete 0 '
  end

  return canvas
end

local function getMask(radius)
  local mask =
      ' -size %[origwidth]x%[origheight]' ..
      ' xc:black' ..
      ' -fill white'

  if radius then
    mask = mask .. ' -draw "roundrectangle 0,0,%[origwidth],%[origheight],' .. radius .. ',' .. radius .. '"'
  else
    mask = mask .. ' -draw "rectangle 0,0,%[origwidth],%[origheight]"'
  end

  return mask .. ' -alpha Copy'
end

-- Build image processing command
---@param config table
---@param file table
---@param flags table
---@return string
local function buildImageProcessingCommand(config, file, flags)
  local crop = flags[Flag.IMAGE_CROP_KEY] and flags[Flag.IMAGE_CROP_KEY].value
  local gravity = flags[Flag.IMAGE_GRAVITY_KEY] and flags[Flag.IMAGE_GRAVITY_KEY].value
  local x = flags[Flag.IMAGE_X_KEY] and flags[Flag.IMAGE_X_KEY].value
  local y = flags[Flag.IMAGE_Y_KEY] and flags[Flag.IMAGE_Y_KEY].value
  local width = flags[Flag.IMAGE_WIDTH_KEY] and flags[Flag.IMAGE_WIDTH_KEY].value
  local height = flags[Flag.IMAGE_HEIGHT_KEY] and flags[Flag.IMAGE_HEIGHT_KEY].value
  local radius = flags[Flag.IMAGE_RADIUS_KEY] and flags[Flag.IMAGE_RADIUS_KEY].value
  local quality = flags[Flag.IMAGE_QUALITY_KEY] and flags[Flag.IMAGE_QUALITY_KEY].value
  local minpad = flags[Flag.IMAGE_MINPAD_KEY] and flags[Flag.IMAGE_MINPAD_KEY].value

  -- Construct a command
  local command = ''
  local executorWithPreset = config.magick .. ' -define png:exclude-chunks=date,time'
  local canvas = getCanvas(config, file, flags)
  local image = file.originalFilePath .. ' -modulate 100,120,100'
  local mask = getMask(radius)
  local dimensions = (width or '') .. 'x' .. (height or '')

  if quality then
    executorWithPreset = executorWithPreset .. ' -quality ' .. quality .. ' '
  end

  if gravity then
    executorWithPreset = executorWithPreset .. ' -gravity ' .. gravity .. ' '
  end

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
        ' -resize ' .. (width - 2 * (minpad or 0)) .. 'x' .. (height - 2 * (minpad or 0)) .. '\\>' ..
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
  local crop = flags[Flag.VIDEO_CROP_KEY] and flags[Flag.VIDEO_CROP_KEY].value
  local background = flags[Flag.VIDEO_BACKGROUND_KEY] and flags[Flag.VIDEO_BACKGROUND_KEY].value
  local x = flags[Flag.VIDEO_X_KEY] and flags[Flag.VIDEO_X_KEY].value
  local y = flags[Flag.VIDEO_Y_KEY] and flags[Flag.VIDEO_Y_KEY].value
  local width = flags[Flag.VIDEO_WIDTH_KEY] and flags[Flag.VIDEO_WIDTH_KEY].value
  local height = flags[Flag.VIDEO_HEIGHT_KEY] and flags[Flag.VIDEO_HEIGHT_KEY].value
  local preset = ''

  -- setting x264 preset
  if config.ffmpegPreset ~= '' then
    preset = ' -preset ' .. config.ffmpegPreset .. ' '
  end

  local command = ''

  if background == 'blur' and crop == 'limited_padding' and width and height then
    -- scale + padded (no upscale) + blurred bg
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "split [first][second];[first]hue=b=-1,boxblur=20, scale=max(' ..
        width ..
        '\\,iw*(max(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):max(' ..
        height ..
        '\\,ih*(max(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2, crop=' ..
        width ..
        ':' ..
        height ..
        ', setsar=1[background];[second]scale=min(' ..
        width ..
        '\\,iw):min(' ..
        height ..
        '\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[foreground];[background][foreground]overlay=y=' ..
        (y or '(H-h)/2') ..
        ':x=' .. (x or '(W-w)/2') .. '" -c:a copy ' .. preset .. file.cachedFilePath
  elseif background == 'blur' and crop == 'padding' and width and height then
    -- scale + padded (with upscale) + blurred bg
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "split [first][second];[first]hue=b=-1,boxblur=20, scale=max(' ..
        width ..
        '\\,iw*(max(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):max(' ..
        height ..
        '\\,ih*(max(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2, crop=' ..
        width ..
        ':' ..
        height ..
        ', setsar=1[background];[second]scale=min(' ..
        width ..
        '\\,iw*(min(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):min(' ..
        height ..
        '\\,ih*(min(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2,setsar=1[foreground];[background][foreground]overlay=y=' ..
        (y or '(H-h)/2') ..
        ':x=' .. (x or '(W-w)/2') .. '" -c:a copy ' .. preset .. file.cachedFilePath
  elseif crop == 'limited_padding' and width and height then
    -- scale (no upscale) with padding (blackbox)
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "scale=min(' ..
        width ..
        '\\,iw):min(' ..
        height ..
        '\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1,pad=' ..
        width ..
        ':' ..
        height ..
        ':y=' ..
        (y or '-1') ..
        ':x=' .. (x or '-1') .. ':color=black" -c:a copy ' .. preset .. file.cachedFilePath
  elseif crop == 'padding' and width and height then
    -- scale (with upscale) with padding (blackbox)
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "scale=min(' ..
        width ..
        '\\,iw*(min(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):min(' ..
        height ..
        '\\,ih*(min(' ..
        width ..
        '/iw\\,' ..
        height ..
        '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2,setsar=1,pad=' ..
        width ..
        ':' ..
        height ..
        ':y=' ..
        (y or '-1') ..
        ':x=' .. (x or '-1') .. ':color=black" -c:a copy ' .. preset .. file.cachedFilePath
  elseif width and height then
    -- simple scale (no aspect ratio)
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "scale=' ..
        width ..
        ':' ..
        height ..
        ':force_divisible_by=2:force_original_aspect_ratio=disable,setsar=1" -c:a copy ' ..
        preset .. file.cachedFilePath
  elseif height then
    -- simple one-side scale (h)
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "scale=-1:' ..
        height ..
        ':force_divisible_by=2:force_original_aspect_ratio=decrease,setsar=1" -c:a copy ' ..
        preset .. file.cachedFilePath
  elseif width then
    -- simple one-side scale (w)
    command = config.ffmpeg ..
        ' -i ' ..
        file.originalFilePath ..
        ' -filter_complex "scale=' ..
        width ..
        ':-1:force_divisible_by=2:force_original_aspect_ratio=decrease,setsar=1" -c:a copy ' ..
        preset .. file.cachedFilePath
  end

  if command and command ~= '' then
    if config.logFfmpegOutput == false then
      command = command .. ' ' .. config.ffmpegDevNull
    end
    if config.logTime then
      command = 'time ' .. command
    end
  end

  return command
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
  self.isValid = self.command and self.command ~= ''

  setmetatable(self, { __index = Command })
  return self
end

-- Execute command
---@return boolean?
function Command:execute()
  if self.isValid then
    return os.execute(self.command)
  end
  return false
end

return Command
