local config = require('config')
local utils = require('utils')
local log = utils.log

log('luamp started')

-- Set missing config options to the defaults
config.setDefaults({
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
    default = 'white',
    value = nil,
  },
  crop = {
    enabled = true,
    default = nil,
    value = nil,
  },
  dpr = {
    enabled = true,
    default = 1,
    value = nil,
  },
  gravity = {
    enabled = true,
    default = 'center',
    value = nil,
  },
  height = {
    enabled = true,
    default = nil,
    value = nil,
  },
  width = {
    enabled = true,
    default = nil,
    value = nil,
  },
  x = {
    enabled = true,
    default = 0,
    value = nil,
  },
  y = {
    enabled = true,
    default = 0,
    value = nil,
  },
}
-- Get flag value
---@param f string
---@return any?
local function getFlagValue(f)
  return flags[f].value or flags[f].default
end

-- Apply limits to a given dimension
---@param d string|number|nil
---@param dpr string|number|nil
---@param maxValue string|number|nil
---@return number?
local function limitDimension(d, dpr, maxValue)
  if d and dpr and maxValue then
    local dNum = tonumber(d)
    local dprNum = tonumber(dpr)
    local maxValueNum = tonumber(maxValue)
    local dimension = dNum and dprNum and math.ceil(dNum * dprNum)
    if dimension and maxValueNum and dimension > maxValueNum then
      log('Resulting dimension exceeds configured limit, capping it at ' .. maxValueNum)
      return maxValueNum
    end

    return dimension
  end

  log('limitDimension: invalid params')
  return nil
end

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
      if originalFile then
        originalFile:write(originalReq.body)
        originalFile:close()
        log('Saved to ' .. originalFilepath)
      else
        log('File not found ' .. originalFilepath)
      end
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

local background = getFlagValue('background')
local crop = getFlagValue('crop')
local gravity = getFlagValue('gravity')
local x = getFlagValue('x')
local y = getFlagValue('y')
local dpr = getFlagValue('dpr')
local width = limitDimension(getFlagValue('width'), dpr, config.maxImageHeight)
local height = limitDimension(getFlagValue('height'), dpr, config.maxImageHeight)

local convertCommand = config.magick

if gravity then
  convertCommand = convertCommand .. ' -gravity ' .. gravity
end

-- Create Canvas
convertCommand = convertCommand .. ' -size $(identify -ping -format "%wx%h" ' .. originalFilepath .. ')'
if background == 'auto' then
  -- Get 2 dominant colors in format 'x000000-x000000'
  local cmd = config.magick .. ' ' .. originalFilepath ..
      ' -resize 50x50 -colors 2 -format "%c" histogram:info: | awk \'{ORS=(NR%2? "-":""); print $3}\''

  local dominantColors = utils.captureCommandOutput(cmd)

  convertCommand = convertCommand .. ' gradient:' .. dominantColors
else
  convertCommand = convertCommand .. ' xc:' .. (background or '')
end

if width or height then
  local dimensions = (width or '') .. 'x' .. (height or '')
  local resizeFlag = (width and height and '!') or ''

  if crop == 'padding' then
    convertCommand = convertCommand ..
        ' -resize ' .. dimensions .. resizeFlag .. ' ' ..
        originalFilepath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions ..
        ' -composite'
  end

  if crop == 'limited_padding' then
    convertCommand = convertCommand ..
        ' -resize ' .. dimensions .. resizeFlag .. ' ' ..
        originalFilepath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions .. '\\>' ..
        ' -composite'
  end

  if crop == 'fill' then
    convertCommand = convertCommand .. ' ' ..
        originalFilepath .. ' -modulate 100,120,100' .. ' -resize ' .. dimensions .. '^' ..
        ' -composite' ..
        ' -crop ' .. dimensions .. '+' .. x .. '+' .. y
  end

  if crop == nil then
    convertCommand = convertCommand .. ' ' ..
        originalFilepath .. ' -modulate 100,120,100' ..
        ' -composite' ..
        ' -resize ' .. dimensions .. resizeFlag
  end
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
end
