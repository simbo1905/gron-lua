#!/usr/bin/env luajit

package.path = package.path .. ";./?.lua"

local colors = require("src.modules.colors")

local passed = 0
local failed = 0
local tests = {}

local function test(name, fn)
    table.insert(tests, {name = name, fn = fn})
end

local function run_tests()
    print("Running colors module tests...")
    print(string.rep("=", 60))
    
    for _, t in ipairs(tests) do
        local ok, err = pcall(t.fn)
        if ok then
            passed = passed + 1
            print("[PASS] " .. t.name)
        else
            failed = failed + 1
            print("[FAIL] " .. t.name)
            print("       " .. tostring(err))
        end
    end
    
    print(string.rep("=", 60))
    print(string.format("Results: %d passed, %d failed", passed, failed))
    
    if failed > 0 then
        os.exit(1)
    end
end

test("colors disabled returns plain text", function()
    colors.init(false)
    local result = colors.red("hello")
    assert(result == "hello", "expected plain text when disabled")
end)

test("colors enabled returns escape codes", function()
    colors.init(true)
    local result = colors.red("hello")
    assert(result:match("\027%["), "expected escape code when enabled")
    assert(result:match("hello"), "expected text content")
end)

test("red applies correct code", function()
    colors.init(true)
    local result = colors.red("test")
    assert(result:match("31"), "expected red code (31)")
end)

test("green applies correct code", function()
    colors.init(true)
    local result = colors.green("test")
    assert(result:match("32"), "expected green code (32)")
end)

test("bold_blue combines codes", function()
    colors.init(true)
    local result = colors.bold_blue("test")
    assert(result:match("1"), "expected bold code (1)")
    assert(result:match("34"), "expected blue code (34)")
end)

test("apply with multiple codes", function()
    colors.init(true)
    local result = colors.apply("test", "bold", "red")
    assert(result:match("1"), "expected bold code")
    assert(result:match("31"), "expected red code")
end)

test("reset code at end", function()
    colors.init(true)
    local result = colors.red("test")
    assert(result:match("0m$"), "expected reset code at end")
end)

run_tests()
