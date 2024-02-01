local File = {}

File.IMAGE_TYPE = 'image'
File.VIDEO_TYPE = 'video'
File.TYPE_EXTENSION_MAP = {
  -- Video
  mp4 = File.VIDEO_TYPE,
  -- Image
  jpg = File.IMAGE_TYPE,
  jpeg = File.IMAGE_TYPE,
  png = File.IMAGE_TYPE,
  gif = File.IMAGE_TYPE,
  bmp = File.IMAGE_TYPE,
  tif = File.IMAGE_TYPE,
  tiff = File.IMAGE_TYPE,
  svg = File.IMAGE_TYPE,
  pdf = File.IMAGE_TYPE,
  webp = File.IMAGE_TYPE,
}

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
  local path = basePath
  local flagNamesOrdered = {}

  -- Add the flag name to the ordered list
  for flagName, _ in pairs(flags) do
    local flag = flags[flagName]
    if flag.makeDir then
      table.insert(flagNamesOrdered, flagName)
    end
  end
  -- Sort flags so path will be the same for `w_1280,h_960` and `h_960,w_1280`
  table.sort(flagNamesOrdered)

  -- Generate the options path
  for _, flagName in ipairs(flagNamesOrdered) do
    local pathFragment = coalesceFlag(flags[flagName])
    if pathFragment ~= '' then
      path = path .. pathFragment .. '/'
    end
  end

  return path
end

-- Base class method new
function File.new(config, prefix, postfix, id, extension)
  local self = {}
  self.config = config
  self.id = id
  self.type = File.TYPE_EXTENSION_MAP[extension]
  self.extension = extension
  self.name = id .. '.' .. extension
  self.originalDir = config.mediaBaseFilepath .. prefix .. postfix
  self.originalFilePath = self.originalDir .. self.name
  self.cacheDir = self.originalDir
  self.cachedFilePath = self.originalFilePath
  self.upstreamPath = nil
  if config.downloadOriginals then
    self.upstreamPath = config.getOriginalsUpstreamPath(prefix, postfix, self.name)
  end

  setmetatable(self, { __index = File })
  return self
end

---Sets cache dir path
function File:updateCacheDirPath(flags)
  self.cacheDir = buildCacheDirPath(self.originalDir, flags)
  self.cachedFilePath = self.cacheDir .. self.name
end

---Checks file is cached
---@return boolean
function File:isCached()
  return File.fileExists(self.cachedFilePath)
end

---Checks file has original
---@return boolean
function File:hasOriginal()
  return File.fileExists(self.originalFilePath)
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
