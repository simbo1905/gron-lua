local json = require("lib.json")

local M = {}

M.null = json.null

function M.decode(str)
    return json.decode(str)
end

function M.encode(val)
    return json.encode(val)
end

return M
