local config = require('config')
local Flag = require('flag')
local File = require('file')
local Command = require('command')
local log = require('log')
local utils = require('utils')

---Download original form upstream
---@param prefix string
---@param postfix string
---@param file table
local function downloadOriginals(prefix, postfix, file)
  local originalsUpstreamPath = config.getOriginalsUpstreamPath(prefix, postfix, file.name)
  log('Downloading original from ' .. originalsUpstreamPath)
  ngx.req.discard_body() -- Clear body

  log('Fetching')
  local originalReq = ngx.location.capture('/luamp-upstream',
    { vars = { luamp_original_file = originalsUpstreamPath } })
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
    ffmpegPreset = ''
  })

  -- Get URL params
  local mediaType = ngx.var.luamp_media_type
  local prefix = utils.cleanupPath(ngx.var.luamp_prefix)
  local luampFlags = ngx.var.luamp_flags
  local postfix = utils.cleanupPath(ngx.var.luamp_postfix)
  local mediaId = utils.cleanupPath(ngx.var.luamp_media_id)
  local mediaExtension = ngx.var.luamp_media_extension

  log('MediaType: ' .. mediaType)
  log('Prefix: ' .. prefix)
  log('Postfix: ' .. postfix)
  log('Flags: ' .. luampFlags)
  log('MediaId: ' .. mediaId)
  log('MediaExtension: ' .. mediaExtension)

  local flags = {}
  local flagMapper = {}
  local valueMapper = {}

  if mediaType == File.IMAGE_TYPE then
    if luampFlags ~= '' then
      flags = {
        [Flag.IMAGE_BACKGROUND_NAME] = Flag.new(config, Flag.IMAGE_BACKGROUND_NAME),
        [Flag.IMAGE_CROP_NAME] = Flag.new(config, Flag.IMAGE_CROP_NAME),
        [Flag.IMAGE_DPR_NAME] = Flag.new(config, Flag.IMAGE_DPR_NAME),
        [Flag.IMAGE_GRAVITY_NAME] = Flag.new(config, Flag.IMAGE_GRAVITY_NAME),
        [Flag.IMAGE_X_NAME] = Flag.new(config, Flag.IMAGE_X_NAME),
        [Flag.IMAGE_Y_NAME] = Flag.new(config, Flag.IMAGE_Y_NAME),
        [Flag.IMAGE_HEIGHT_NAME] = Flag.new(config, Flag.IMAGE_HEIGHT_NAME),
        [Flag.IMAGE_WIDTH_NAME] = Flag.new(config, Flag.IMAGE_WIDTH_NAME),
        [Flag.IMAGE_RADIUS_NAME] = Flag.new(config, Flag.IMAGE_RADIUS_NAME),
        [Flag.IMAGE_QUALITY_NAME] = Flag.new(config, Flag.IMAGE_QUALITY_NAME),
        [Flag.IMAGE_MINPAD_NAME] = Flag.new(config, Flag.IMAGE_MINPAD_NAME),
      }
      flagMapper = config.flagImageMap
      valueMapper = config.flagValueMap
    end
  elseif mediaType == File.VIDEO_TYPE then
    flags = {}
    flagMapper = config.flagMap
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

    local flag = flags[flagMapper[f]]
    -- Set value if flag exists
    if flag then
      flag:setValue(v, valueMapper)
    end
  end

  -- Scale dimensions with respect to limits
  local dpr = flags[Flag.IMAGE_DPR_NAME]
  if dpr and dpr.value then
    for flagName, _ in pairs(flags) do
      local flag = flags[flagName]
      if flag.isScalable then
        log('Scaling flag: ' .. flagName)
        flag:scale(dpr.value)
      end
    end
  end

  local file = File.new(config, prefix, postfix, mediaId, mediaExtension, mediaType, flags)

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
      downloadOriginals(prefix, postfix, file)
    else
      ngx.exit(ngx.HTTP_NOT_FOUND)
    end
  end

  -- Serve the cached file if it exists
  if file:isCached() then
    log('Serving cached file: ' .. file.cachedFilePath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.cachedFilePath })
  end

  log('Original is present on local FS. Transcoding to ' .. file.cachedFilePath)
  local cmd = Command.new(config, file, flags)
  log('Command: ' .. cmd.command)
  local executeSuccess = cmd:execute()

  if executeSuccess then
    log('Transcoded version is good, serving it')
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.cachedFilePath })
  end

  log('Transcode failed')

  if not cmd.isValid then
    log('Invalid command')
  end

  if config.serveOriginalOnTranscodeFailure == true then
    log('Serving original from: ' .. file.originalFilePath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.originalFilePath })
  end
end

main()
