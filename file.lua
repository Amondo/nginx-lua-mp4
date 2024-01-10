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
---@param flags table
---@return string
local function buildCacheDirPath(basePath, flags)
  if utils.isTableEmpty(flags) then
    return basePath
  end

  local flagNamesOrdered = {}

  -- Add the flag name to the ordered list
  for flagName, _ in pairs(flags) do
    table.insert(flagNamesOrdered, flagName)
  end
  -- Sort flags so path will be the same for `w_1280,h_960` and `h_960,w_1280`
  table.sort(flagNamesOrdered)

  -- Generate the options path
  local optionsPath = ''

  for _, flagName in ipairs(flagNamesOrdered) do
    local pathFragment = coalesceFlag(flags[flagName])
    if pathFragment ~= '' then
      optionsPath = optionsPath .. pathFragment .. '/'
    end
  end

  return basePath .. optionsPath
end

-- Base class method new
function File.new(config, prefix, postfix, id, extension, type, flags)
  local self = {}
  self.config = config
  self.id = id
  self.type = type
  self.extension = extension
  self.name = id .. '.' .. extension
  self.originalDir = config.mediaBaseFilepath .. prefix .. postfix
  self.originalFilePath = self.originalDir .. self.name
  self.originalFileIdPath = self.originalDir .. id .. '.*'
  self.cacheDir = buildCacheDirPath(self.originalDir, flags)
  self.cachedFilePath = self.cacheDir .. self.name
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
  local cmd = string.format("ls -1 %s | grep '%s'", self.originalDir, self.id .. '.*')
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
