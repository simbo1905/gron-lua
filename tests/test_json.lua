#!/usr/bin/env luajit

package.path = package.path .. ";./?.lua"

local json = require("src.modules.json")

local passed = 0
local failed = 0
local tests = {}

local function test(name, fn)
    table.insert(tests, {name = name, fn = fn})
end

local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not eq(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if not eq(v, a[k]) then return false end
    end
    return true
end

local function run_tests()
    print("Running JSON module tests...")
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

test("json decode simple object", function()
    local obj = json.decode('{"name": "Simon", "age": 30}')
    assert(obj.name == "Simon")
    assert(obj.age == 30)
end)

test("json decode nested object", function()
    local obj = json.decode('{"user": {"name": "Simon", "tags": ["lua", "jit"]}}')
    assert(obj.user.name == "Simon")
    assert(obj.user.tags[1] == "lua")
    assert(obj.user.tags[2] == "jit")
end)

test("json encode simple object", function()
    local str = json.encode({name = "Simon", age = 30})
    local decoded = json.decode(str)
    assert(decoded.name == "Simon")
    assert(decoded.age == 30)
end)

test("json roundtrip array", function()
    local original = {1, 2, 3, "four", true, false}
    local str = json.encode(original)
    local decoded = json.decode(str)
    assert(eq(original, decoded))
end)

test("json roundtrip nested", function()
    local original = {
        users = {
            {id = 1, name = "Alice"},
            {id = 2, name = "Bob"}
        },
        count = 2
    }
    local str = json.encode(original)
    local decoded = json.decode(str)
    assert(decoded.users[1].name == "Alice")
    assert(decoded.users[2].name == "Bob")
    assert(decoded.count == 2)
end)

test("json handles null", function()
    local obj = json.decode('{"value": null}')
    assert(obj.value == json.null)
end)

test("json encodes null", function()
    local str = json.encode({value = json.null})
    assert(str:match("null"))
end)

test("json handles empty object", function()
    local obj = json.decode('{}')
    assert(type(obj) == "table")
end)

test("json handles empty array", function()
    local arr = json.decode('[]')
    assert(type(arr) == "table")
    assert(#arr == 0)
end)

test("json handles unicode escapes", function()
    local obj = json.decode('{"emoji": "\\u0048\\u0065\\u006c\\u006c\\u006f"}')
    assert(obj.emoji == "Hello")
end)

test("json handles special characters", function()
    local obj = json.decode('{"text": "line1\\nline2\\ttabbed"}')
    assert(obj.text == "line1\nline2\ttabbed")
end)

run_tests()
