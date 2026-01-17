#!/usr/bin/env luajit
-- Bundle all gron-lua source files into a single distributable file

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        error("Cannot read file: " .. path)
    end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then
        error("Cannot write file: " .. path)
    end
    f:write(content)
    f:close()
end

local function indent(code, spaces)
    spaces = spaces or 4
    local prefix = string.rep(" ", spaces)
    return prefix .. code:gsub("\n", "\n" .. prefix):gsub(prefix .. "$", "")
end

local function strip_shebang(code)
    return code:gsub("^#![^\n]*\n", "")
end

local function strip_requires(code, modules_to_strip)
    for _, mod in ipairs(modules_to_strip) do
        code = code:gsub('local%s+%w+%s*=%s*require%s*%(%s*["\']' .. mod:gsub("%.", "%%.") .. '["\']%s*%)', "")
    end
    return code
end

local base_dir = arg[0]:match("(.*/)")
if base_dir then
    base_dir = base_dir .. "../"
else
    base_dir = "./"
end

local json_lua = read_file(base_dir .. "lib/json.lua")
local colors_lua = read_file(base_dir .. "src/modules/colors.lua")
local gron_lua = read_file(base_dir .. "src/modules/gron.lua")
local main_lua = read_file(base_dir .. "src/main.lua")

json_lua = strip_shebang(json_lua)
colors_lua = strip_shebang(colors_lua)
gron_lua = strip_shebang(gron_lua)
main_lua = strip_shebang(main_lua)

gron_lua = gron_lua:gsub('require%s*%(%s*["\']src%.modules%.json["\']%s*%)', "_json")
gron_lua = gron_lua:gsub('require%s*%(%s*["\']src%.modules%.colors["\']%s*%)', "_colors")

main_lua = main_lua:gsub('package%.path.-";./%.%.lua"', "")
main_lua = main_lua:gsub('local json = require%s*%(%s*["\']src%.modules%.json["\']%s*%)', "local json = _json")
main_lua = main_lua:gsub('local gron = require%s*%(%s*["\']src%.modules%.gron["\']%s*%)', "local gron = _gron")
main_lua = main_lua:gsub('local colors = require%s*%(%s*["\']src%.modules%.colors["\']%s*%)', "local colors = _colors")

local bundle = [[#!/usr/bin/env luajit
-- gron-lua - Transform JSON into discrete assignments to make it greppable
-- Single-file bundle - no external dependencies required
-- Version: 0.1.0
-- License: MIT
-- https://github.com/user/gron-lua

-- ============================================================================
-- Embedded json.lua (rxi/json.lua)
-- ============================================================================
local _json = (function()
]] .. indent(json_lua) .. [[

end)()

-- ============================================================================
-- Embedded colors module
-- ============================================================================
local _colors = (function()
]] .. indent(colors_lua) .. [[

end)()

-- ============================================================================
-- Embedded gron module
-- ============================================================================
local _gron = (function()
    local json = _json
    local colors = _colors
]] .. indent(gron_lua) .. [[

end)()

-- ============================================================================
-- Main CLI
-- ============================================================================
local json = _json
local gron = _gron
local colors = _colors

]] .. main_lua:gsub("^package%.path.-\n", "")

local dist_dir = base_dir .. "dist"
os.execute("mkdir -p " .. dist_dir)

local output_path = dist_dir .. "/gron.lua"
write_file(output_path, bundle)
os.execute("chmod +x " .. output_path)

print("Bundle created: " .. output_path)
local handle = io.popen("wc -l < " .. output_path)
local lines = handle:read("*a"):gsub("%s+", "")
handle:close()
print("Total lines: " .. lines)

handle = io.popen("wc -c < " .. output_path)
local bytes = handle:read("*a"):gsub("%s+", "")
handle:close()
print("Total size: " .. bytes .. " bytes (" .. math.floor(tonumber(bytes)/1024) .. " KB)")
