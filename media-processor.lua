local config = require('config')
local Flag = require('flag')
local File = require('file')
local Command = require('command')
local log = require('log')
local utils = require('utils')

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

  local flags = {}
  local flagMapper = {}
  local valueMapper = {}

  if file.type == File.IMAGE_TYPE then
    flags = {
      [Flag.IMAGE_BACKGROUND_NAME] = Flag.new(config, Flag.IMAGE_BACKGROUND_NAME, 'white'),
      [Flag.IMAGE_GRAVITY_NAME] = Flag.new(config, Flag.IMAGE_GRAVITY_NAME, 'center'),
      [Flag.IMAGE_X_NAME] = Flag.new(config, Flag.IMAGE_X_NAME, 0),
      [Flag.IMAGE_Y_NAME] = Flag.new(config, Flag.IMAGE_Y_NAME, 0),
      [Flag.IMAGE_QUALITY_NAME] = Flag.new(config, Flag.IMAGE_QUALITY_NAME, 80),
    }
    flagMapper = config.flagImageMap
    valueMapper = config.flagValueMap
  elseif file.type == File.VIDEO_TYPE then
    flagMapper = config.flagVideoMap
    valueMapper = config.flagValueMap
  else
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  -- Parse flags into a table
  for f, v in string.gmatch(luampFlags, '(%w+)' .. config.flagValueDelimiter .. '([^' .. config.flagsDelimiter .. '\\/]+)' .. config.flagsDelimiter .. '*') do
    -- Preprocess the flag and value if necessary
    if config.flagPreprocessHook then
      f, v = config.flagPreprocessHook(f, v)
    end

    local flagName = flagMapper[f]
    if flagName then
      flags[flagName] = Flag.new(config, flagName)
      flags[flagName]:setValue(v, valueMapper)
    end
  end

  -- Scale dimensions with respect to limits
  local dpr = flags[Flag.IMAGE_DPR_NAME] or flags[Flag.VIDEO_DPR_NAME]
  for flagName, _ in pairs(flags) do
    local flag = flags[flagName]
    if flag.isScalable and dpr and dpr.value then
      log('Scaling a flag: ' .. flagName)
      flag:scale(dpr.value)
    end
  end

  -- Calculate absolute x/y for values in (0, 1) range
  if file.type == File.VIDEO_TYPE then
    local videoX = flags[Flag.VIDEO_X_NAME]
    local videoY = flags[Flag.VIDEO_Y_NAME]
    local videoWidth = flags[Flag.VIDEO_WIDTH_NAME]
    local videoHeight = flags[Flag.VIDEO_HEIGHT_NAME]
    if videoX and videoWidth then
      videoX.coordinateToAbsolute(videoWidth.value)
      log('Absolute x: ' .. videoX.value)
    end
    if videoY and videoWidth then
      videoY.coordinateToAbsolute(videoHeight.value)
      log('Absolute y: ' .. videoY.value)
    end
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
