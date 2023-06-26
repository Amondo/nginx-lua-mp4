local config = require('config')
local utils = require('utils')
local log = utils.log

log('luamp started')

-- Set missing config options to the defaults
config.setDefaults({
  minimumTranscodedImageSize = 1024,
  serveOriginalOnTranscodeFailure = true,
})

-- Get URL params
local prefix = utils.cleanupPath(ngx.var.luamp_prefix)
local luamp_flags = ngx.var.luamp_flags
local postfix = utils.cleanupPath(ngx.var.luamp_postfix)
local filename = utils.cleanupPath(ngx.var.luamp_filename)

log('prefix: ' .. prefix)
log('flags: ' .. luamp_flags)
log('postfix: ' .. postfix)
log('filename: ' .. filename)

-- Enabled flags with defaults
local flags = {
  background = {
    enabled = true,
    value = 'white'
  },
  crop = {
    enabled = true,
    value = nil
  },
  dpr = {
    enabled = true,
    value = 1
  },
  gravity = {
    enabled = true,
    value = 'center'
  },
  height = {
    enabled = true,
    value = nil
  },
  width = {
    enabled = true,
    value = nil
  },
  x = {
    enabled = true,
    value = 0
  },
  y = {
    enabled = true,
    value = 0
  }
}
local flagsOrdered = {}

-- Add the flag name to the ordered list
for flag, _ in pairs(flags) do
  table.insert(flagsOrdered, flag)
end
-- Sort flags so path will be the same for `w_1280,h_960` and `h_960,w_1280`
table.sort(flagsOrdered)

-- Parse flags into a table
for flag, value in string.gmatch(luamp_flags, '(%w+)' .. config.flagValueDelimiter .. '([^' .. config.flagsDelimiter .. '\\/]+)' .. config.flagsDelimiter .. '*') do
  local flagMapped = config.flagMap[flag]
  -- Check if the flag is enabled
  if value and flags[flagMapped] and flags[flagMapped].enabled then
    -- Preprocess the flag and value if necessary
    if config.flagPreprocessHook then
      flag, value = config.flagPreprocessHook(flag, value)
    end

    -- Check if it is an allowed text flag or cast to a number
    flags[flagMapped].value = config.flagValueMap[value] or tonumber(value)
  end
end

-- Apply limits to height and width if specified
local maxImageHeight = config.maxImageHeight
local maxImageWidth = config.maxImageWidth

if flags.height.value and maxImageHeight and flags.height.value > maxImageHeight then
  log('Resulting height exceeds configured limit, capping it at ' .. maxImageHeight)
  flags.height.value = maxImageHeight
end

if flags.width.value and maxImageWidth and flags.width.value > maxImageWidth then
  log('Resulting width exceeds configured limit, capping it at ' .. maxImageWidth)
  flags.width.value = maxImageWidth
end

-- Coalesce flag values. All flag values are set at this moment
local function coalesceFlag(option)
  local flag = flags[option]
  if flag and flag.value and flag.value ~= '' then
    return option .. '_' .. flag.value
  end
  return ''
end

-- Generate the options path
local optionsPath = ''

for _, option in ipairs(flagsOrdered) do
  local pathFragment = coalesceFlag(option)
  if pathFragment ~= '' then
    optionsPath = optionsPath .. pathFragment .. '/'
  end
end

-- Check if we already have a cached version of the file
local cacheDir = config.mediaBaseFilepath .. prefix .. optionsPath .. postfix
local cachedFilepath = cacheDir .. filename

-- Serve the cached file if it exists
if utils.fileExists(cachedFilepath) then
  log('Serving cached file: ' .. cachedFilepath)
  ngx.exec('/luamp-cache', { luamp_cached_file_path = cachedFilepath })
  return
end

log('Cached file not found: ' .. cachedFilepath)

-- If the cached file doesn't exist, process the original file
local originalDir = config.mediaBaseFilepath .. prefix .. postfix
local originalFilepath = originalDir .. filename

-- Check if the original file exists
if not utils.fileExists(originalFilepath) then
  log('Original file not found: ' .. originalFilepath)

  if config.downloadOriginals then
    -- Download original if upstream download is enabled
    local originalsUpstreamPath = config.getOriginalsUpstreamPath(prefix, postfix, filename)
    log('Downloading original from ' .. originalsUpstreamPath)
    ngx.req.discard_body() -- Clear body
    log('Fetching')
    local originalReq = ngx.location.capture('/luamp-upstream',
      { vars = { luamp_original_file = originalsUpstreamPath } })
    log('Upstream status: ' .. originalReq.status)

    if originalReq.status == ngx.HTTP_OK and originalReq.body:len() > 0 then
      log('Downloaded original, saving')
      os.execute('mkdir -p ' .. originalDir)
      local originalFile = io.open(originalFilepath, 'w')
      originalFile:write(originalReq.body)
      originalFile:close()
      log('Saved to ' .. originalFilepath)
    else
      ngx.exit(ngx.HTTP_NOT_FOUND)
    end
  else
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end
end

log('Original is present on local FS. Transcoding to ' .. cachedFilepath)

-- Create cached transcoded file
os.execute('mkdir -p ' .. cacheDir)

-- Build the convert command
local background = flags.background.value
local crop = flags.crop.value
local gravity = flags.gravity.value
local height = flags.height.value and math.ceil(flags.height.value * flags.dpr.value)
local width = flags.width.value and math.ceil(flags.width.value * flags.dpr.value)
local x = flags.x.value
local y = flags.y.value
local convertCommand = config.magick ..
    ' ' .. originalFilepath ..
    ' -background ' .. background ..
    ' -gravity ' .. gravity

if crop and width and height then
  if crop == 'fill' then
    convertCommand = convertCommand ..
        ' -resize ' .. width .. 'x' .. height .. '^' ..
        ' -crop ' .. width .. 'x' .. height .. '+' .. x .. '+' .. y
  end

  if crop == 'limited_padding' then
    convertCommand = convertCommand ..
        ' -resize ' .. '"' .. width .. 'x' .. height .. '>"' ..
        ' -extent ' .. width .. 'x' .. height
  end

  if crop == 'padding' then
    convertCommand = convertCommand ..
        ' -resize ' .. width .. 'x' .. height ..
        ' -extent ' .. width .. 'x' .. height
  end
elseif width and height then
  convertCommand = convertCommand .. ' -resize ' .. width .. 'x' .. height .. '!'
elseif width or height then
  convertCommand = convertCommand .. ' -resize ' .. (width or '') .. 'x' .. (height or '')
end

-- Append the output filepath to the convert command
convertCommand = convertCommand .. ' ' .. cachedFilepath

local executeSuccess

if convertCommand ~= nil then
  if config.logTime then
    convertCommand = 'time ' .. convertCommand
  end

  log('Command: ' .. convertCommand)
  executeSuccess = os.execute(convertCommand)
end

if executeSuccess == nil then
  log('Transcode failed')

  if config.serveOriginalOnTranscodeFailure == true then
    log('Serving original from: ' .. originalFilepath)
    ngx.exec('/luamp-cache', { luamp_cached_file_path = originalFilepath })
  end
else
  -- Check if transcoded file is > minimumTranscodedImageSize
  -- We do this inside the transcoding `if` block to not mess with other threads
  local transcodedFile = io.open(cachedFilepath, 'rb')
  local transcodedFileSize = transcodedFile:seek('end')
  transcodedFile:close()

  if transcodedFileSize > config.minimumTranscodedImageSize then
    log('Transcoded version is good, serving it')
    -- Serve it
    ngx.exec('/luamp-cache', { luamp_cached_file_path = cachedFilepath })
  else
    log('Transcoded version is corrupt')
    -- Delete corrupt one
    os.remove(cachedFilepath)

    -- Serve original
    if config.serveOriginalOnTranscodeFailure == true then
      log('Serving original')
      ngx.exec('/luamp-cache', { luamp_cached_file_path = originalFilepath })
    end
  end
end
