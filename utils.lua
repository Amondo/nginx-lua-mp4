local utils = {}

-- Clean up path by allowing only specific characters
---@param path string
---@return string
---@return integer
function utils.cleanupPath(path)
  local allowedChars = '[%w_%-/.=]'       -- Allow alphanumeric + underscore + dash + slash + dot
  local retVal = path:gsub('[^' .. allowedChars .. ']', '')
  return retVal:gsub('([\\.][\\.]+)', '') -- Strip double+ dot
end

-- Function to capture command output
---@param cmd string
---@return any
function utils.captureCommandOutput(cmd)
  local handle = io.popen(cmd)
  if handle then
    local output = handle:read('*a')
    handle:close()
    return output
  end
end

return utils
