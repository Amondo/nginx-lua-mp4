local config = require('config')
local utils = {}

-- Log helper function
---@param data any
function utils.log(data)
  if config.logEnabled then
    ngx.log(config.logLevel, data)
  end
end

-- Clean up path by allowing only specific characters
---@param path string
---@return string
---@return integer
function utils.cleanupPath(path)
  local allowedChars = '[%w_%-/.=]'       -- Allow alphanumeric + underscore + dash + slash + dot
  local retVal = path:gsub('[^' .. allowedChars .. ']', '')
  return retVal:gsub('([\\.][\\.]+)', '') -- Strip double+ dot
end

-- Check if a file exists
---@param filepath string
---@return boolean
function utils.fileExists(filepath)
  local file = io.open(filepath, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

return utils
