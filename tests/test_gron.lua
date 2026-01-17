#!/usr/bin/env luajit

package.path = package.path .. ";./?.lua"

local json = require("src.modules.json")
local gron = require("src.modules.gron")

local passed = 0
local failed = 0
local tests = {}

local function test(name, fn)
    table.insert(tests, {name = name, fn = fn})
end

local function eq(a, b)
    if a == json.null and b == json.null then return true end
    if a == json.null or b == json.null then return false end
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
    print("Running gron module tests...")
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

test("flatten simple object", function()
    local obj = {name = "Simon", age = 30}
    local stmts = gron.flatten("json", obj)
    assert(#stmts == 3)
    local has_obj = false
    local has_name = false
    local has_age = false
    for _, s in ipairs(stmts) do
        if s.path == "json" and s.value == "{}" then has_obj = true end
        if s.path == "json.name" and s.value == '"Simon"' then has_name = true end
        if s.path == "json.age" and s.value == "30" then has_age = true end
    end
    assert(has_obj, "missing json = {}")
    assert(has_name, "missing json.name")
    assert(has_age, "missing json.age")
end)

test("flatten array", function()
    local arr = {"one", "two", "three"}
    local stmts = gron.flatten("json", arr)
    assert(#stmts == 4)
    local has_arr = false
    for _, s in ipairs(stmts) do
        if s.path == "json" and s.value == "[]" then has_arr = true end
    end
    assert(has_arr, "missing json = []")
end)

test("flatten nested object", function()
    local obj = {user = {name = "Simon"}}
    local stmts = gron.flatten("json", obj)
    local found_nested = false
    for _, s in ipairs(stmts) do
        if s.path == "json.user.name" and s.value == '"Simon"' then
            found_nested = true
        end
    end
    assert(found_nested, "missing nested path")
end)

test("flatten special key", function()
    local obj = {["foo bar"] = "value"}
    local stmts = gron.flatten("json", obj)
    local found = false
    for _, s in ipairs(stmts) do
        if s.path:match('%["foo bar"%]') then
            found = true
        end
    end
    assert(found, "missing quoted key for 'foo bar'")
end)

test("flatten null value", function()
    local obj = {value = json.null}
    local stmts = gron.flatten("json", obj)
    local found = false
    for _, s in ipairs(stmts) do
        if s.path == "json.value" and s.value == "null" then
            found = true
        end
    end
    assert(found, "missing null value")
end)

test("unflatten simple statements", function()
    local lines = {
        'json = {};',
        'json.name = "Simon";',
        'json.age = 30;'
    }
    local obj = gron.unflatten(lines)
    assert(obj.name == "Simon")
    assert(obj.age == 30)
end)

test("unflatten array statements", function()
    local lines = {
        'json = [];',
        'json[0] = "one";',
        'json[1] = "two";'
    }
    local obj = gron.unflatten(lines)
    assert(obj[1] == "one")
    assert(obj[2] == "two")
end)

test("unflatten nested statements", function()
    local lines = {
        'json = {};',
        'json.user = {};',
        'json.user.name = "Simon";'
    }
    local obj = gron.unflatten(lines)
    assert(obj.user.name == "Simon")
end)

test("unflatten null value", function()
    local lines = {
        'json = {};',
        'json.value = null;'
    }
    local obj = gron.unflatten(lines)
    assert(obj.value == json.null)
end)

test("roundtrip simple object", function()
    local original = {name = "Simon", age = 30}
    local stmts = gron.flatten("json", original)
    local lines = {}
    for _, s in ipairs(stmts) do
        table.insert(lines, s.path .. " = " .. s.value .. ";")
    end
    local restored = gron.unflatten(lines)
    assert(eq(original, restored))
end)

test("roundtrip nested object", function()
    local original = {
        user = {
            name = "Simon",
            tags = {"lua", "jit"}
        }
    }
    local stmts = gron.flatten("json", original)
    local lines = {}
    for _, s in ipairs(stmts) do
        table.insert(lines, s.path .. " = " .. s.value .. ";")
    end
    local restored = gron.unflatten(lines)
    assert(restored.user.name == "Simon")
    assert(restored.user.tags[1] == "lua")
    assert(restored.user.tags[2] == "jit")
end)

test("roundtrip with null", function()
    local original = {value = json.null, name = "test"}
    local stmts = gron.flatten("json", original)
    local lines = {}
    for _, s in ipairs(stmts) do
        table.insert(lines, s.path .. " = " .. s.value .. ";")
    end
    local restored = gron.unflatten(lines)
    assert(restored.value == json.null)
    assert(restored.name == "test")
end)

test("extract values", function()
    local lines = {
        'json = {};',
        'json.name = "Simon";',
        'json.age = 30;',
        'json.active = true;'
    }
    local values = gron.extract_values(lines)
    assert(#values == 2)
    local has_name = false
    local has_age = false
    for _, v in ipairs(values) do
        if v == "Simon" then has_name = true end
        if v == "30" then has_age = true end
    end
    assert(has_name)
    assert(has_age)
end)

test("format statement without color", function()
    local stmt = {path = "json.name", value = '"Simon"', value_type = "string"}
    local formatted = gron.format_statement(stmt, false)
    assert(formatted == 'json.name = "Simon";')
end)

test("compare with real json file", function()
    local f = io.open("testdata/one.json", "r")
    if not f then
        print("  (skipping - testdata not found)")
        return
    end
    local content = f:read("*a")
    f:close()
    
    local obj = json.decode(content)
    local stmts = gron.flatten("json", obj)
    
    assert(#stmts > 0, "should produce statements")
    
    local lines = {}
    for _, s in ipairs(stmts) do
        table.insert(lines, s.path .. " = " .. s.value .. ";")
    end
    local restored = gron.unflatten(lines)
    assert(eq(obj, restored), "roundtrip should preserve data")
end)

run_tests()
