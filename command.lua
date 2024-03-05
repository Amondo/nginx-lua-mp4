local File = require('file')
local Flag = require('flag')
local utils = require('utils')

local Command = {}

local function getCanvas(config, file, flags)
  local background = flags[Flag.IMAGE_BACKGROUND_KEY] and flags[Flag.IMAGE_BACKGROUND_KEY].value
  local canvas

  if background == 'auto' then
    -- Get 2 dominant colors in format 'x000000-x000000'
    local cmd = config.magick .. ' ' .. file.originalFilePath
        .. ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

    local dominantColors = utils.captureCommandOutput(cmd)

    canvas = file.originalFilePath .. ' -size %wx%h gradient:' .. dominantColors .. ' -delete 0 '
  elseif background == 'blurred' then
    canvas = file.originalFilePath .. ' -crop 80%x80% +repage -scale 10% -blur 0x2.5 -resize 1000% '
  else
    canvas = file.originalFilePath .. ' -size %wx%h xc:' .. (background or '') .. ' -delete 0 '
  end

  return canvas or ''
end

local function getMask(radius)
  local mask = ' -size %[origwidth]x%[origheight]  xc:black -fill white'

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
    command = executorWithPreset
        .. canvas
        .. ' -resize ' .. dimensions .. '^'
        .. ' -crop ' .. dimensions .. '+' .. x .. '+' .. y
        .. ' \\( '
        .. image
        .. ' -resize ' .. dimensions .. '^'
        .. ' -crop ' .. dimensions .. '+' .. x .. '+' .. y
        .. ' -set option:origwidth %w'
        .. ' -set option:origheight %h'
        .. ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite'
        .. ' \\) -compose over -composite'
  elseif crop == 'limited_padding' and (width or height) then
    local imageWidth = width and (width - 2 * (minpad or 0))
    local imageHeight = height and (height - 2 * (minpad or 0))
    command = executorWithPreset
        .. canvas
        .. ' -resize ' .. dimensions .. '^'
        .. ' -crop ' .. dimensions .. '+0+0 '
        .. ' \\( '
        .. image
        .. ' -resize ' .. (imageWidth or '') .. 'x' .. (imageHeight or '') .. '\\>'
        .. ' -set option:origwidth %w'
        .. ' -set option:origheight %h'
        .. ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite'
        .. ' \\) -compose over -composite'
  elseif crop == 'padding' and (width or height) then
    local imageWidth = width and (width - 2 * (minpad or 0))
    local imageHeight = height and (height - 2 * (minpad or 0))
    command = executorWithPreset
        .. canvas
        .. ' -resize ' .. dimensions .. '^'
        .. ' -crop ' .. dimensions .. '+0+0 '
        .. ' \\( '
        .. image
        .. ' -resize ' .. (imageWidth or '') .. 'x' .. (imageHeight or '')
        .. ' -set option:origwidth %w'
        .. ' -set option:origheight %h'
        .. ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite'
        .. ' \\) -compose over -composite'
  elseif width or height then
    local forceResizeFlag = (width and height and '! ') or ''

    command = executorWithPreset
        .. canvas
        .. ' -resize ' .. dimensions .. forceResizeFlag
        .. ' \\( '
        .. image
        .. ' -resize ' .. dimensions .. forceResizeFlag
        .. ' -set option:origwidth %w'
        .. ' -set option:origheight %h'
        .. ' \\( ' .. mask .. ' \\) -compose CopyOpacity -composite'
        .. ' \\) -compose over -composite'
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
    if config.colorProfilePath and config.colorProfilePath ~= '' and File.fileExists(config.colorProfilePath) then
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
  local radius = flags[Flag.VIDEO_RADIUS_KEY] and flags[Flag.VIDEO_RADIUS_KEY].value
  local minpad = flags[Flag.VIDEO_MINPAD_KEY] and flags[Flag.VIDEO_MINPAD_KEY].value

  -- Construct a command
  local filter = ''

  local videoWidth = width and (width - 2 * (minpad or 0))
  local videoHeight = height and (height - 2 * (minpad or 0))

  if background == 'blurred' and crop == 'limited_padding' and width and height then
    -- scale + padded (no upscale) + blurred bg
    filter = '[0]split [first][second];'
        -- prepare background
        .. '[first]'
        .. 'hue=b=-1,boxblur=20'
        .. ',scale=max(' .. width .. '\\,iw*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':max(' .. height .. '\\,ih*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':force_original_aspect_ratio=increase'
        .. ':force_divisible_by=2'
        .. ',crop=' .. width .. ':' .. height
        .. ',setsar=1'
        .. '[bg];'
        -- prepare foreground
        .. '[second]'
        .. 'scale=min(' .. videoWidth .. '\\,iw):min(' .. videoHeight .. '\\,ih)'
        .. ':force_original_aspect_ratio=decrease'
        .. ':force_divisible_by=2'
        .. ',setsar=1'
    if radius then
      filter = filter
          -- prepare mask
          .. '[v];'
          .. '[1][v]scale2ref[image out][v out];'
          .. '[image out]'
          .. 'format=yuva420p'
          .. ",geq=lum='p(X,Y)'"
          .. ":a='if(gt(abs(W/2-X),W/2-" .. radius .. ")*gt(abs(H/2-Y),H/2-" .. radius .. ")"
          .. ",if(lte(hypot(" ..
          radius .. "-(W/2-abs(W/2-X))," .. radius .. "-(H/2-abs(H/2-Y)))," .. radius .. "),255,0),255)'"
          .. '[a];'
          .. '[a]alphaextract[mask];'
          .. '[v out][mask]alphamerge'
    end
    -- compose
    filter = filter .. '[fg];[bg][fg]overlay=y=' .. (y or '(H-h)/2') .. ':x=' .. (x or '(W-w)/2')
  elseif background == 'blurred' and crop == 'padding' and width and height then
    -- scale + padded (with upscale) + blurred bg
    filter = '[0]split [first][second];'
        -- prepare background
        .. '[first]'
        .. 'hue=b=-1,boxblur=20'
        .. ',scale=max(' .. width .. '\\,iw*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':max(' .. height .. '\\,ih*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':force_original_aspect_ratio=increase'
        .. ':force_divisible_by=2'
        .. ',crop=' .. width .. ':' .. height
        .. ',setsar=1'
        .. '[bg];'
        -- prepare foreground
        .. '[second]'
        .. 'scale=min(' .. videoWidth .. '\\,iw*(min(' .. videoWidth .. '/iw\\,' .. videoHeight .. '/ih)))'
        .. ':min(' .. videoHeight .. '\\,ih*(min(' .. videoWidth .. '/iw\\,' .. videoHeight .. '/ih)))'
        .. ':force_original_aspect_ratio=increase'
        .. ':force_divisible_by=2'
        .. ',setsar=1'
    if radius then
      filter = filter
          -- prepare mask
          .. '[v];'
          .. '[1][v]scale2ref[image out][v out];'
          .. '[image out]'
          .. 'format=yuva420p'
          .. ",geq=lum='p(X,Y)'"
          .. ":a='if(gt(abs(W/2-X),W/2-" .. radius .. ")*gt(abs(H/2-Y),H/2-" .. radius .. ")"
          .. ",if(lte(hypot(" ..
          radius .. "-(W/2-abs(W/2-X))," .. radius .. "-(H/2-abs(H/2-Y)))," .. radius .. "),255,0),255)'"
          .. '[a];'
          .. '[a]alphaextract[mask];'
          .. '[v out][mask]alphamerge'
    end
    -- compose
    filter = filter .. '[fg];[bg][fg]overlay=y=' .. (y or '(H-h)/2') .. ':x=' .. (x or '(W-w)/2')
  elseif crop == 'limited_padding' and width and height then
    -- scale (no upscale) with padding (blackbox)
    filter =
    -- prepare background
        '[1]scale=' .. width .. ':' .. height
        .. ',setsar=1'
        .. '[bg];'
        -- prepare foreground
        .. '[0]scale=min(' .. videoWidth .. '\\,iw):min(' .. videoHeight .. '\\,ih)'
        .. ':force_original_aspect_ratio=decrease'
        .. ':force_divisible_by=2'
        .. ',setsar=1'
    if radius then
      filter = filter
          -- prepare mask
          .. '[v];'
          .. '[1][v]scale2ref[bg out][v out];'
          .. '[bg out]'
          .. 'format=yuva420p'
          .. ",geq=lum='p(X,Y)'"
          .. ":a='if(gt(abs(W/2-X),W/2-" .. radius .. ")*gt(abs(H/2-Y),H/2-" .. radius .. ")"
          .. ",if(lte(hypot(" ..
          radius .. "-(W/2-abs(W/2-X))," .. radius .. "-(H/2-abs(H/2-Y)))," .. radius .. "),255,0),255)'"
          .. '[a];'
          .. '[a]alphaextract[mask];'
          .. '[v out][mask]alphamerge'
    end
    -- compose
    filter = filter .. '[fg];[bg][fg]overlay=y=' .. (y or '(H-h)/2') .. ':x=' .. (x or '(W-w)/2')
  elseif crop == 'padding' and width and height then
    -- scale (with upscale) with padding (blackbox)
    filter =
    -- prepare background
        '[1]scale=' .. width .. ':' .. height
        .. ',setsar=1'
        .. '[bg];'
        -- prepare foreground
        .. '[0]scale=min(' .. videoWidth .. '\\,iw*(min(' .. videoWidth .. '/iw\\,' .. videoHeight .. '/ih)))'
        .. ':min(' .. videoHeight .. '\\,ih*(min(' .. videoWidth .. '/iw\\,' .. videoHeight .. '/ih)))'
        .. ':force_original_aspect_ratio=increase'
        .. ':force_divisible_by=2'
        .. ',setsar=1'
    if radius then
      filter = filter
          -- prepare mask
          .. '[v];'
          .. '[1][v]scale2ref[bg out][v out];'
          .. '[bg out]'
          .. 'format=yuva420p'
          .. ",geq=lum='p(X,Y)'"
          .. ":a='if(gt(abs(W/2-X),W/2-" .. radius .. ")*gt(abs(H/2-Y),H/2-" .. radius .. ")"
          .. ",if(lte(hypot(" ..
          radius .. "-(W/2-abs(W/2-X))," .. radius .. "-(H/2-abs(H/2-Y)))," .. radius .. "),255,0),255)'"
          .. '[a];'
          .. '[a]alphaextract[mask];'
          .. '[v out][mask]alphamerge'
    end
    -- compose
    filter = filter .. '[fg];[bg][fg]overlay=y=' .. (y or '(H-h)/2') .. ':x=' .. (x or '(W-w)/2')
  elseif crop == 'fill' and width and height then
    filter =
        '[0]scale=max(' .. width .. '\\,iw*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':max(' .. height .. '\\,ih*(max(' .. width .. '/iw\\,' .. height .. '/ih)))'
        .. ':force_original_aspect_ratio=increase'
        .. ':force_divisible_by=2'
        .. ',crop=' .. width .. ':' .. height
        .. ',setsar=1'
  elseif width or height then
    -- simple scale
    local ratio = 'decrease'

    if width and height then
      ratio = 'disable'
    end

    filter =
    -- prepare foreground
        '[0]scale=' .. (width or '-1') .. ':' .. (height or '-1')
        .. ':force_original_aspect_ratio=' .. ratio
        .. ':force_divisible_by=2'
        .. ',setsar=1'
  end

  if filter and filter ~= '' then
    if background == 'blurred' then
      background = 'black'
    end
    local command = config.ffmpeg ..
        ' -i ' .. file.originalFilePath .. ' -f lavfi -i color=c=' .. background .. ':s=10x10:d=1 '
        .. ' -filter_complex "' .. filter
        .. '" -c:a copy'
        .. ' -movflags +faststart'

    -- setting x264 preset
    if config.ffmpegPreset and config.ffmpegPreset ~= '' then
      command = command .. ' -preset ' .. config.ffmpegPreset
    end

    command = command .. ' ' .. file.cachedFilePath

    -- Set pre-command
    if config.logTime then
      command = 'time ' .. command
    end

    -- Set post-command
    if config.logFfmpegOutput == false then
      command = command .. ' ' .. config.ffmpegDevNull
    end

    return command
  end

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
