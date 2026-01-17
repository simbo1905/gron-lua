#!/usr/bin/env luajit

package.path = package.path .. ";./?.lua"

local json = require("src.modules.json")
local gron = require("src.modules.gron")
local colors = require("src.modules.colors")

local VERSION = "0.1.0"

local EXIT_OK = 0
local EXIT_OPEN_FILE = 1
local EXIT_READ_INPUT = 2
local EXIT_FORM_STATEMENTS = 3
local EXIT_FETCH_URL = 4
local EXIT_PARSE_STATEMENTS = 5
local EXIT_JSON_ENCODE = 6

local function print_usage()
    io.stderr:write([[
Transform JSON (from a file, URL, or stdin) into discrete assignments to make it greppable

Usage:
  gron [OPTIONS] [FILE|URL|-]

Options:
  -u, --ungron     Reverse the operation (turn assignments back into JSON)
  -v, --values     Print just the values of provided assignments
  -c, --colorize   Colorize output (default on tty)
  -m, --monochrome Monochrome (don't colorize output)
  -s, --stream     Treat each line of input as a separate JSON object
  -j, --json       Represent gron data as JSON stream
      --no-sort    Don't sort output (faster)
      --version    Print version information
      --help       Show this help message

Exit Codes:
  0     OK
  1     Failed to open file
  2     Failed to read input
  3     Failed to form statements
  4     Failed to fetch URL
  5     Failed to parse statements
  6     Failed to encode JSON

Examples:
  gron /tmp/apiresponse.json
  gron http://jsonplaceholder.typicode.com/users/1 
  curl -s http://jsonplaceholder.typicode.com/users/1 | gron
  gron http://jsonplaceholder.typicode.com/users/1 | grep company | gron --ungron
]])
end

local function parse_args(args)
    local opts = {
        ungron = false,
        values = false,
        stream = false,
        json_output = false,
        colorize = nil,
        monochrome = false,
        no_sort = false,
        version = false,
        help = false,
        input = nil
    }
    
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "-u" or a == "--ungron" then
            opts.ungron = true
        elseif a == "-v" or a == "--values" then
            opts.values = true
        elseif a == "-s" or a == "--stream" then
            opts.stream = true
        elseif a == "-j" or a == "--json" then
            opts.json_output = true
        elseif a == "-c" or a == "--colorize" then
            opts.colorize = true
        elseif a == "-m" or a == "--monochrome" then
            opts.monochrome = true
        elseif a == "--no-sort" then
            opts.no_sort = true
        elseif a == "--version" then
            opts.version = true
        elseif a == "--help" or a == "-h" then
            opts.help = true
        elseif a == "-" then
            opts.input = "-"
        elseif not a:match("^%-") then
            opts.input = a
        end
        i = i + 1
    end
    
    return opts
end

local function is_url(s)
    return s and (s:match("^https?://") ~= nil)
end

local function fetch_url(url)
    local handle = io.popen("curl -sL " .. string.format("%q", url) .. " 2>/dev/null")
    if not handle then
        return nil, "failed to fetch URL"
    end
    local content = handle:read("*a")
    local ok = handle:close()
    if not ok or not content or #content == 0 then
        return nil, "failed to fetch URL"
    end
    return content
end

local function read_input(input_path)
    if input_path == nil or input_path == "-" then
        local content = io.read("*a")
        if not content then
            return nil, EXIT_READ_INPUT
        end
        return content, EXIT_OK
    end
    
    if is_url(input_path) then
        local content, err = fetch_url(input_path)
        if not content then
            return nil, EXIT_FETCH_URL
        end
        return content, EXIT_OK
    end
    
    local f = io.open(input_path, "r")
    if not f then
        return nil, EXIT_OPEN_FILE
    end
    local content = f:read("*a")
    f:close()
    if not content then
        return nil, EXIT_READ_INPUT
    end
    return content, EXIT_OK
end

local function do_gron(content, opts)
    local ok, data = pcall(json.decode, content)
    if not ok or data == nil then
        io.stderr:write("failed to parse JSON: " .. tostring(data) .. "\n")
        return EXIT_FORM_STATEMENTS
    end
    
    local statements = gron.flatten("json", data, nil, opts.no_sort)
    
    if not opts.no_sort then
        table.sort(statements, function(a, b)
            return a.path < b.path
        end)
    end
    
    for _, stmt in ipairs(statements) do
        if opts.json_output then
            local keys = gron.path_to_keys(stmt.path)
            local val = stmt.raw_value
            if stmt.value_type == "array" or stmt.value_type == "object" then
                local marker = stmt.value_type == "array" and "[]" or "{}"
                io.write("[" .. json.encode(keys) .. "," .. marker .. "]\n")
            else
                print(json.encode({keys, val}))
            end
        else
            print(gron.format_statement(stmt, opts.use_color))
        end
    end
    
    return EXIT_OK
end

local function do_gron_stream(content, opts)
    print("json = [];")
    
    local index = 0
    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%s*$") then
            goto continue
        end
        
        local ok, data = pcall(json.decode, line)
        if not ok or data == nil then
            io.stderr:write("failed to parse JSON line: " .. line .. "\n")
            goto continue
        end
        
        local prefix = "json[" .. index .. "]"
        local statements = gron.flatten(prefix, data, nil, opts.no_sort)
        
        if not opts.no_sort then
            table.sort(statements, function(a, b)
                return a.path < b.path
            end)
        end
        
        for _, stmt in ipairs(statements) do
            if opts.json_output then
                local keys = gron.path_to_keys(stmt.path)
                local val = stmt.raw_value
                if stmt.value_type == "array" or stmt.value_type == "object" then
                    local marker = stmt.value_type == "array" and "[]" or "{}"
                    io.write("[" .. json.encode(keys) .. "," .. marker .. "]\n")
                else
                    print(json.encode({keys, val}))
                end
            else
                print(gron.format_statement(stmt, opts.use_color))
            end
        end
        
        index = index + 1
        ::continue::
    end
    
    return EXIT_OK
end

local function do_ungron(content, opts)
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local result = gron.unflatten(lines)
    
    local ok, output = pcall(json.encode, result)
    if not ok then
        io.stderr:write("failed to encode JSON\n")
        return EXIT_JSON_ENCODE
    end
    
    print(output)
    return EXIT_OK
end

local function do_values(content, opts)
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local values = gron.extract_values(lines)
    for _, v in ipairs(values) do
        print(v)
    end
    
    return EXIT_OK
end

local function main()
    local opts = parse_args(arg)
    
    if opts.version then
        print("gron version " .. VERSION)
        return EXIT_OK
    end
    
    if opts.help then
        print_usage()
        return EXIT_OK
    end
    
    if opts.monochrome then
        colors.init(false)
    elseif opts.colorize then
        colors.init(true)
    else
        colors.init()
    end
    opts.use_color = colors.enabled and not opts.monochrome
    
    local content, err = read_input(opts.input)
    if not content then
        io.stderr:write("failed to read input\n")
        return err
    end
    
    if opts.ungron then
        return do_ungron(content, opts)
    elseif opts.values then
        return do_values(content, opts)
    elseif opts.stream then
        return do_gron_stream(content, opts)
    else
        return do_gron(content, opts)
    end
end

os.exit(main())
