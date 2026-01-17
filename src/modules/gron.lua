local json = require("src.modules.json")
local colors = require("src.modules.colors")

local M = {}

local function is_valid_identifier(s)
    if type(s) ~= "string" or #s == 0 then return false end
    local first = s:sub(1, 1)
    if not (first:match("[a-zA-Z_$]")) then
        return false
    end
    for i = 2, #s do
        local c = s:sub(i, i)
        if not (c:match("[a-zA-Z0-9_$]")) then
            return false
        end
    end
    return true
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
    end
    return count == #t
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta == "number"
        end
        return a < b
    end)
    return keys
end

function M.flatten(prefix, value, statements, no_sort)
    statements = statements or {}
    
    local value_str
    local value_type
    if value == json.null then
        value_str = "null"
        value_type = "null"
    elseif type(value) == "table" then
        if is_array(value) then
            value_str = "[]"
            value_type = "array"
        else
            value_str = "{}"
            value_type = "object"
        end
    elseif type(value) == "string" then
        value_str = json.encode(value)
        value_type = "string"
    elseif type(value) == "boolean" then
        value_str = value and "true" or "false"
        value_type = "boolean"
    elseif value == nil then
        value_str = "null"
        value_type = "null"
    else
        value_str = tostring(value)
        value_type = "number"
    end
    
    table.insert(statements, {
        path = prefix,
        value = value_str,
        raw_value = value,
        value_type = value_type
    })
    
    if type(value) == "table" and value ~= json.null then
        local keys
        if no_sort then
            keys = {}
            for k in pairs(value) do
                table.insert(keys, k)
            end
        else
            keys = sorted_keys(value)
        end
        
        for _, k in ipairs(keys) do
            local v = value[k]
            local new_prefix
            if type(k) == "number" then
                new_prefix = prefix .. "[" .. (k - 1) .. "]"
            elseif is_valid_identifier(k) then
                new_prefix = prefix .. "." .. k
            else
                new_prefix = prefix .. "[" .. json.encode(k) .. "]"
            end
            M.flatten(new_prefix, v, statements, no_sort)
        end
    end
    
    return statements
end

local function parse_path(path)
    local keys = {}
    local remaining = path
    
    local root_key = remaining:match("^([a-zA-Z_$][a-zA-Z0-9_$]*)")
    if root_key then
        table.insert(keys, root_key)
        remaining = remaining:sub(#root_key + 1)
    end
    
    while #remaining > 0 do
        local dot_key = remaining:match("^%.([a-zA-Z_$][a-zA-Z0-9_$]*)")
        if dot_key then
            table.insert(keys, dot_key)
            remaining = remaining:sub(#dot_key + 2)
        else
            local bracket_num = remaining:match("^%[(%d+)%]")
            if bracket_num then
                table.insert(keys, tonumber(bracket_num) + 1)
                remaining = remaining:sub(#bracket_num + 3)
            else
                local bracket_str = remaining:match("^%[(\".-\")%]")
                if bracket_str then
                    local ok, decoded = pcall(json.decode, bracket_str)
                    if ok then
                        table.insert(keys, decoded)
                    end
                    remaining = remaining:sub(#bracket_str + 3)
                else
                    break
                end
            end
        end
    end
    
    return keys
end

local function parse_value(value_str)
    value_str = value_str:gsub(";%s*$", "")
    
    if value_str == "[]" then
        return {}, "array"
    elseif value_str == "{}" then
        return {}, "object"
    elseif value_str == "true" then
        return true, "boolean"
    elseif value_str == "false" then
        return false, "boolean"
    elseif value_str == "null" then
        return json.null, "null"
    elseif value_str:match("^\"") then
        local ok, decoded = pcall(json.decode, value_str)
        if ok then
            return decoded, "string"
        end
        return value_str, "string"
    elseif value_str:match("^%-?%d") then
        local num = tonumber(value_str)
        if num then
            return num, "number"
        end
        return value_str, "unknown"
    else
        return value_str, "unknown"
    end
end

local function set_nested(root, keys, value, value_type)
    if #keys == 0 then return end
    
    local current = root
    for i = 1, #keys - 1 do
        local k = keys[i]
        local next_k = keys[i + 1]
        
        if current[k] == nil then
            current[k] = {}
        end
        current = current[k]
    end
    
    local final_key = keys[#keys]
    if value_type == "array" or value_type == "object" then
        if current[final_key] == nil then
            current[final_key] = value
        end
    else
        current[final_key] = value
    end
end

function M.unflatten(lines)
    local root = {}
    
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            line = line.line or line[1]
        end
        
        if not line or line:match("^%-%-") or line:match("^%s*$") then
            goto continue
        end
        
        local path, value_str = line:match("^(.-)%s*=%s*(.-)%s*;?%s*$")
        if not path then goto continue end
        
        local keys = parse_path(path)
        if #keys == 0 then goto continue end
        
        local value, value_type = parse_value(value_str)
        set_nested(root, keys, value, value_type)
        
        ::continue::
    end
    
    if root.json ~= nil then
        return root.json
    end
    return root
end

function M.format_statement(stmt, use_color)
    if use_color then
        local path_parts = {}
        local remaining = stmt.path
        
        local root = remaining:match("^([a-zA-Z_$][a-zA-Z0-9_$]*)")
        if root then
            table.insert(path_parts, colors.bold_blue(root))
            remaining = remaining:sub(#root + 1)
        end
        
        while #remaining > 0 do
            local dot_key = remaining:match("^(%.([a-zA-Z_$][a-zA-Z0-9_$]*))")
            if dot_key then
                local key = remaining:match("^%.([a-zA-Z_$][a-zA-Z0-9_$]*)")
                table.insert(path_parts, "." .. colors.bold_blue(key))
                remaining = remaining:sub(#dot_key + 1)
            else
                local bracket = remaining:match("^(%[.-%])")
                if bracket then
                    local inner = bracket:sub(2, -2)
                    if inner:match("^%d+$") then
                        table.insert(path_parts, colors.magenta("[") .. colors.red(inner) .. colors.magenta("]"))
                    else
                        table.insert(path_parts, colors.magenta("[") .. colors.yellow(inner) .. colors.magenta("]"))
                    end
                    remaining = remaining:sub(#bracket + 1)
                else
                    break
                end
            end
        end
        
        local colored_path = table.concat(path_parts, "")
        local colored_value
        if stmt.value_type == "string" then
            colored_value = colors.yellow(stmt.value)
        elseif stmt.value_type == "number" then
            colored_value = colors.red(stmt.value)
        elseif stmt.value_type == "boolean" or stmt.value_type == "null" then
            colored_value = colors.cyan(stmt.value)
        elseif stmt.value_type == "array" or stmt.value_type == "object" then
            colored_value = colors.magenta(stmt.value)
        else
            colored_value = stmt.value
        end
        
        return colored_path .. " = " .. colored_value .. ";"
    else
        return stmt.path .. " = " .. stmt.value .. ";"
    end
end

function M.extract_values(lines)
    local values = {}
    
    for _, line in ipairs(lines) do
        if line:match("^%-%-") or line:match("^%s*$") then
            goto continue
        end
        
        local path, value_str = line:match("^(.-)%s*=%s*(.-)%s*;?%s*$")
        if not path or not value_str then
            goto continue
        end
        
        value_str = value_str:gsub(";%s*$", "")
        
        if value_str == "[]" or value_str == "{}" then
            goto continue
        end
        
        if value_str:match("^\"") then
            local ok, decoded = pcall(json.decode, value_str)
            if ok then
                table.insert(values, decoded)
            else
                table.insert(values, value_str)
            end
        elseif value_str == "true" or value_str == "false" or value_str == "null" then
            goto continue
        else
            table.insert(values, value_str)
        end
        
        ::continue::
    end
    
    return values
end

function M.path_to_keys(path)
    local keys = {}
    local remaining = path
    
    local root_key = remaining:match("^([a-zA-Z_$][a-zA-Z0-9_$]*)")
    if root_key then
        remaining = remaining:sub(#root_key + 1)
    end
    
    while #remaining > 0 do
        local dot_key = remaining:match("^%.([a-zA-Z_$][a-zA-Z0-9_$]*)")
        if dot_key then
            table.insert(keys, dot_key)
            remaining = remaining:sub(#dot_key + 2)
        else
            local bracket_num = remaining:match("^%[(%d+)%]")
            if bracket_num then
                table.insert(keys, tonumber(bracket_num))
                remaining = remaining:sub(#bracket_num + 3)
            else
                local bracket_str = remaining:match("^%[(\".-\")%]")
                if bracket_str then
                    local ok, decoded = pcall(json.decode, bracket_str)
                    if ok then
                        table.insert(keys, decoded)
                    end
                    remaining = remaining:sub(#bracket_str + 3)
                else
                    break
                end
            end
        end
    end
    
    return keys
end

return M
