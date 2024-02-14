local config = require('config')
local Flag = require('flag')
local File = require('file')
local Command = require('command')
local log = require('log')
local utils = require('utils')
local ngx = ngx

---Download original form upstream
---@param file table
local function downloadOriginals(file)
  log('Downloading original from ' .. file.upstreamPath)
  ngx.req.discard_body() -- Clear body

  log('Fetching')
  local originalReq = ngx.location.capture('/luamp-upstream', {
    vars = { luamp_original_file = file.upstreamPath }
  })
  log('Upstream status: ' .. originalReq.status)

  if originalReq.status == ngx.HTTP_OK and originalReq.body:len() > 0 then
    log('Downloaded original, saving')
    os.execute('mkdir -p ' .. file.originalDir)

    local originalFile = io.open(file.originalFilePath, 'w')
    if originalFile then
      originalFile:write(originalReq.body)
      originalFile:close()
      log('Saved to ' .. file.originalFilePath)
    else
      log('Something went wrong on saving original to ' .. file.originalFilePath)
    end
  else
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end
end

local function main()
  log('Luamp started')

  -- Set missing config options to the defaults
  config.setDefaults({
    minimumTranscodedVideoSize = 1024,
    serveOriginalOnTranscodeFailure = true,
    ffmpegPreset = '',
  })

  -- Get URL params
  local prefix = utils.cleanupPath(ngx.var.luamp_prefix)
  local luampFlags = ngx.var.luamp_flags
  local postfix = utils.cleanupPath(ngx.var.luamp_postfix)
  local mediaId = utils.cleanupPath(ngx.var.luamp_media_id)
  local mediaExtension = ngx.var.luamp_media_extension
  local file = File.new(config, prefix, postfix, mediaId, mediaExtension)

  log('Prefix: ' .. prefix)
  log('Postfix: ' .. postfix)
  log('Flags: ' .. luampFlags)
  log('MediaId: ' .. mediaId)
  log('MediaExtension: ' .. mediaExtension)
  log('MediaType: ' .. file.type)

  local flags = {}
  local flagMapper = {}
  local valueMapper = config.flagValueMap

  if file.type == File.IMAGE_TYPE then
    flagMapper = config.flagImageMap
  elseif file.type == File.VIDEO_TYPE then
    flagMapper = config.flagVideoMap
  else
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  -- Serve original if there are no flags
  if luampFlags == '' then
    -- Check if the original file exists
    if not file:hasOriginal() then
      log('Original file not found: ' .. file.originalFilePath)

      if config.downloadOriginals then
        -- Download original if upstream download is enabled
        downloadOriginals(file)
      else
        ngx.exit(ngx.HTTP_NOT_FOUND)
      end
    end

    log('Serving original from: ' .. file.originalFilePath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.originalFilePath })
  end

  -- Fill flags with defaults
  for _, flagKey in pairs(flagMapper) do
    local flag = Flag.new(flagKey)
    if flag.value then
      flags[flagKey] = flag
    end
  end

  -- Parse flags into a table
  for f, v in string.gmatch(luampFlags,
    '(%w+)' .. config.flagValueDelimiter
    .. '([^' .. config.flagsDelimiter
    .. '\\/]+)' .. config.flagsDelimiter
    .. '*'
  ) do
    -- Preprocess the flag and value if necessary
    if config.flagPreprocessHook then
      f, v = config.flagPreprocessHook(f, v)
    end

    local flagKey = flagMapper[f]
    if flagKey then
      if not flags[flagKey] then
        flags[flagKey] = Flag.new(flagKey)
      end
      flags[flagKey]:setValue(v, valueMapper)
    end
  end

  -- Scale dimensions with dpr
  local dprFlag = flags[Flag.IMAGE_DPR_KEY] or flags[Flag.VIDEO_DPR_KEY]
  local dpr = dprFlag and dprFlag.value or 1
  for flagName in pairs(flags) do
    local flag = flags[flagName]
    if flag.isScalable then
      log('Scaling a flag: ' .. flagName)
      flag:scale(dpr)
    end
  end

  -- Apply limits and scale
  local widthFlag = flags[Flag.IMAGE_WIDTH_KEY] or flags[Flag.VIDEO_WIDTH_KEY]
  local heightFlag = flags[Flag.IMAGE_HEIGHT_KEY] or flags[Flag.VIDEO_HEIGHT_KEY]
  local xFlag = flags[Flag.IMAGE_X_KEY] or flags[Flag.VIDEO_X_KEY]
  local yFlag = flags[Flag.IMAGE_Y_KEY] or flags[Flag.VIDEO_Y_KEY]
  local width = widthFlag and widthFlag.value or 0
  local height = heightFlag and heightFlag.value or 0
  local x = xFlag and xFlag.value
  local y = yFlag and yFlag.value
  local aspectRatio = 1
  local maxWidth = (file.type == File.VIDEO_TYPE and config.maxVideoWidth) or config.maxImageWidth or 0
  local maxHeight = (file.type == File.VIDEO_TYPE and config.maxVideoHeight) or config.maxImageHeight or 0
  local wAr = maxWidth / width
  local hAr = maxHeight / height

  if wAr < 1 then
    if hAr < 1 then
      aspectRatio = math.min(wAr, hAr)
    else
      aspectRatio = wAr
    end
  elseif hAr < 1 then
    aspectRatio = hAr
  end

  for flagName in pairs(flags) do
    local flag = flags[flagName]
    if flag.isScalable then
      log('Applying AR ' .. aspectRatio .. ' to a flag: ' .. flagName)
      flag:scale(aspectRatio)
    end
  end

  -- Calculate absolute x/y for values in (0, 1) range
  if x and 0 < x and x < 1 and width then
    xFlag:coordinateToAbsolute(width)
    log('Absolute x: ' .. xFlag.value)
  end

  if y and 0 < y and y < 1 and height then
    yFlag:coordinateToAbsolute(height)
    log('Absolute x: ' .. yFlag.value)
  end

  -- Recalculate cache dir path
  file:updateCacheDirPath(flags)

  -- Serve the cached file if it exists
  if file:isCached() then
    log('Serving cached file: ' .. file.cachedFilePath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.cachedFilePath })
  end

  -- If the cached file doesn't exist, process the original file
  log('Cached file not found: ' .. file.cachedFilePath)

  -- Check if the original file exists
  if not file:hasOriginal() then
    log('Original file not found: ' .. file.originalFilePath)

    if config.downloadOriginals then
      -- Download original if upstream download is enabled
      downloadOriginals(file)
    else
      ngx.exit(ngx.HTTP_NOT_FOUND)
    end
  end

  log('Original is present on local FS. Transcoding to ' .. file.cachedFilePath)
  local cmd = Command.new(config, file, flags)
  local executeSuccess

  if cmd.isValid then
    os.execute('mkdir -p ' .. file.cacheDir)
    log('Command: ' .. cmd.command)
    executeSuccess = cmd:execute()
  else
    log('Invalid command')
  end

  if executeSuccess then
    log('Transcoded version is good, serving it')
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.cachedFilePath })
  end

  log('Transcode failed')

  if config.serveOriginalOnTranscodeFailure == true then
    log('Serving original from: ' .. file.originalFilePath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.originalFilePath })
  end
end

main()
