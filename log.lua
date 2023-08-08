-- Log function
---@param data any
local function log(data)
    if config.logEnabled then
        ngx.log(config.logLevel, data)
    end
end

return log
