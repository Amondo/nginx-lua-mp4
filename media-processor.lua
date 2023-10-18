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
  local originalsUpstreamPath = config.getOriginalsUpstreamPath(prefix, postfix, file.filename)
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
    originalFile:write(originalReq.body)
    originalFile:close()
    log('Saved to ' .. file.originalFilePath)
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
  local luamp_flags = ngx.var.luamp_flags
  local postfix = utils.cleanupPath(ngx.var.luamp_postfix)
  local filename = utils.cleanupPath(ngx.var.luamp_filename)

  log('MediaType: ' .. mediaType)
  log('Prefix: ' .. prefix)
  log('Flags: ' .. luamp_flags)
  log('Postfix: ' .. postfix)
  log('Filename: ' .. filename)

  local flags = {}
  local flagMapper = {}
  local valueMapper = {}

  if mediaType == File.IMAGE_TYPE then
    flags = {
      [Flag.IMAGE_BACKGROUND_NAME] = Flag.new(Flag.IMAGE_BACKGROUND_NAME),
      [Flag.IMAGE_CROP_NAME] = Flag.new(Flag.IMAGE_CROP_NAME),
      [Flag.IMAGE_DPR_NAME] = Flag.new(Flag.IMAGE_DPR_NAME),
      [Flag.IMAGE_GRAVITY_NAME] = Flag.new(Flag.IMAGE_GRAVITY_NAME),
      [Flag.IMAGE_X_NAME] = Flag.new(Flag.IMAGE_X_NAME),
      [Flag.IMAGE_Y_NAME] = Flag.new(Flag.IMAGE_Y_NAME),
      [Flag.IMAGE_HEIGHT_NAME] = Flag.new(Flag.IMAGE_HEIGHT_NAME),
      [Flag.IMAGE_WIDTH_NAME] = Flag.new(Flag.IMAGE_WIDTH_NAME),
      [Flag.IMAGE_RADIUS_NAME] = Flag.new(Flag.IMAGE_RADIUS_NAME),
      [Flag.IMAGE_QUALITY_NAME] = Flag.new(Flag.IMAGE_QUALITY_NAME),
    }
    flagMapper = config.flagImageMap
    valueMapper = config.flagValueMap
  elseif mediaType == File.VIDEO_TYPE then
    flags = {}
    flagMapper = config.flagMap
    valueMapper = config.flagValueMap
  else
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  -- Parse flags into a table
  for f, v in string.gmatch(luamp_flags, '(%w+)' .. config.flagValueDelimiter .. '([^' .. config.flagsDelimiter .. '\\/]+)' .. config.flagsDelimiter .. '*') do
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
  local maxHeight = (mediaType == File.IMAGE_TYPE and config.maxImageHeight) or config.maxVideoHeight
  local maxWidth = (mediaType == File.IMAGE_TYPE and config.maxImageWidth) or config.maxVideoWidth
  flags[Flag.IMAGE_HEIGHT_NAME]:scaleDimension(flags[Flag.IMAGE_DPR_NAME].value, maxHeight)
  flags[Flag.IMAGE_WIDTH_NAME]:scaleDimension(flags[Flag.IMAGE_DPR_NAME].value, maxWidth)

  local file = File.new(config, prefix, postfix, filename, mediaType, flags)

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

  log('Original is present on local FS. Transcoding to ' .. file.cachedFilePath)
  local command = Command.new(config, file, flags)
  local executeSuccess
  if command.command then
    log('Command: ' .. command.command)
    executeSuccess = command:execute()
  end

  if executeSuccess == nil then
    log('Transcode failed')

    if config.serveOriginalOnTranscodeFailure == true then
      log('Serving original from: ' .. file.originalFilePath)
      ngx.exec('/luamp-cache', { luamp_cached_file_path = file.originalFilePath })
    end
  else
    log('Transcoded version is good, serving it')
    ngx.exec('/luamp-cache', { luamp_cached_file_path = file.cachedFilePath })
  end
end

main()
