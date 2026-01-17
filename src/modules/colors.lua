local M = {}

local ESC = "\027["

M.codes = {
    reset = 0,
    bold = 1,
    dim = 2,
    underline = 4,
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
}

M.enabled = true

local function is_tty()
    local handle = io.output()
    if handle and handle.isatty then
        return handle:isatty()
    end
    local term = os.getenv("TERM")
    return term and term ~= "dumb"
end

function M.init(force_color)
    if force_color == true then
        M.enabled = true
    elseif force_color == false then
        M.enabled = false
    else
        M.enabled = is_tty()
    end
end

function M.apply(text, ...)
    if not M.enabled then
        return text
    end
    local codes = {...}
    if #codes == 0 then
        return text
    end
    local nums = {}
    for _, code in ipairs(codes) do
        if type(code) == "string" then
            table.insert(nums, M.codes[code] or 0)
        else
            table.insert(nums, code)
        end
    end
    return ESC .. table.concat(nums, ";") .. "m" .. text .. ESC .. "0m"
end

function M.red(text) return M.apply(text, "red") end
function M.green(text) return M.apply(text, "green") end
function M.yellow(text) return M.apply(text, "yellow") end
function M.blue(text) return M.apply(text, "blue") end
function M.magenta(text) return M.apply(text, "magenta") end
function M.cyan(text) return M.apply(text, "cyan") end
function M.bold(text) return M.apply(text, "bold") end
function M.bold_blue(text) return M.apply(text, "bold", "blue") end

return M
