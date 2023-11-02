local utils = require('utils')
local File = {}

File.IMAGE_TYPE = 'image'
File.VIDEO_TYPE = 'video'

-- Coalesce flag values. All flag values are set at this moment
---@param flag table
---@return string
local function coalesceFlag(flag)
  if flag and flag.value and flag.value ~= '' then
    return flag.name .. '_' .. flag.value
  end
  return ''
end

---Build cache dir path
---@param basePath string
---@param prefix string
---@param postfix string
---@param flags table
---@param mediaType string
---@return string
local function buildCacheDirPath(basePath, prefix, postfix, flags, mediaType)
  local flagNamesOrdered = {}

  -- Add the flag name to the ordered list
  for flagName, _ in pairs(flags) do
    table.insert(flagNamesOrdered, flagName)
  end
  -- Sort flags so path will be the same for `w_1280,h_960` and `h_960,w_1280`
  table.sort(flagNamesOrdered)

  -- Generate the options path
  local optionsPath = mediaType .. '/'

  for _, flagName in ipairs(flagNamesOrdered) do
    local pathFragment = coalesceFlag(flags[flagName])
    if pathFragment ~= '' then
      optionsPath = optionsPath .. pathFragment .. '/'
    end
  end

  return basePath .. prefix .. optionsPath .. postfix
end

-- Base class method new
function File.new(config, prefix, postfix, publicId, extension, mediaType, flags)
  local self = {}
  self.config = config
  self.mediaType = mediaType
  self.publicId = publicId
  self.extension = extension
  self.filename = publicId .. '.' .. extension
  self.cacheDir = buildCacheDirPath(config.mediaBaseFilepath, prefix, postfix, flags, mediaType)
  self.cachedFilePath = self.cacheDir .. self.filename
  self.originalDir = config.mediaBaseFilepath .. mediaType .. '/originals/' .. prefix .. postfix
  self.originalFilePath = self.originalDir .. self.publicId .. '.*'
  setmetatable(self, { __index = File })
  return self
end

---Checks file is cached
---@return boolean
function File:isCached()
  return File.fileExists(self.cachedFilePath)
end

---Checks file has original
---@return boolean
function File:hasOriginal()
  local cmd = string.format("ls -1 %s | grep '%s'", self.originalDir, self.publicId .. '.*')
  local result = utils.captureCommandOutput(cmd)
  return (result and result ~= "") or false
end

-- Check if a file exists
---@param path string
---@return boolean
function File.fileExists(path)
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

return File
