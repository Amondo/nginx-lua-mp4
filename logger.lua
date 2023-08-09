local Logger = {}

-- Base class method new
function Logger.new(enabled, level)
  local self = {}
  self.enabled = enabled
  self.level = level
  setmetatable(self, { __index = Logger })
  return self
end

-- Log function
---@param ... any
function Logger:log(...)
  if self.enabled then
    ngx.log(self.level, ...)
  end
end

return Logger
