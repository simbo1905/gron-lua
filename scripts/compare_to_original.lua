#!/usr/bin/env luajit
local GRON_REPO = "tomnomnom/gron"
local GRON_API_URL = "https://api.github.com/repos/" .. GRON_REPO .. "/releases/latest"
local TMP_DIR = ".tmp"
local WARMUP_RUNS = 2
local BENCHMARK_RUNS = 10

local GHARCHIVE_URL = "https://data.gharchive.org/2015-01-01-15.json.gz"
local GHARCHIVE_GZ = TMP_DIR .. "/gharchive-2015-01-01-15.json.gz"
local GHARCHIVE_JSON = TMP_DIR .. "/gharchive-sample.json"

local function exec(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local ok, _, code = handle:close()
    return result, (ok and code == 0) or (type(ok) == "boolean" and ok)
end

local function exec_silent(cmd)
    local ok = os.execute(cmd .. " >/dev/null 2>&1")
    return ok == true or ok == 0
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function get_file_size(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size
end

local function format_bytes(bytes)
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%d B", bytes)
    end
end

local function format_time(ms)
    if ms >= 1000 then
        return string.format("%.2f s", ms / 1000)
    else
        return string.format("%.1f ms", ms)
    end
end

local function get_arch()
    local result = exec("uname -m")
    result = result:gsub("%s+", "")
    if result == "arm64" or result == "aarch64" then
        return "arm64"
    else
        return "amd64"
    end
end

local function get_os()
    local result = exec("uname -s")
    result = result:gsub("%s+", ""):lower()
    if result == "darwin" then
        return "darwin"
    elseif result == "linux" then
        return "linux"
    else
        return result
    end
end

local function fetch_json(url)
    local result, ok = exec("curl -sL -H 'Accept: application/json' '" .. url .. "'")
    if not ok then
        return nil, "Failed to fetch: " .. url
    end
    return result
end

local function parse_release_info(json_str)
    local tag = json_str:match('"tag_name"%s*:%s*"([^"]+)"')
    local version = tag and tag:gsub("^v", "") or nil
    local assets = {}
    for asset_block in json_str:gmatch('"browser_download_url"%s*:%s*"([^"]+)"') do
        table.insert(assets, asset_block)
    end
    return {
        tag = tag,
        version = version,
        assets = assets
    }
end

local function find_asset_url(assets, os_name, arch)
    local pattern = "gron%-" .. os_name .. "%-" .. arch
    for _, url in ipairs(assets) do
        if url:find(pattern) then
            return url
        end
    end
    return nil
end

local function ensure_gron_binary()
    local gron_path = TMP_DIR .. "/gron"
    if file_exists(gron_path) then
        local version_out = exec(gron_path .. " --version 2>&1")
        if version_out and version_out:find("gron") then
            print("Using cached Go gron: " .. version_out:gsub("%s+$", ""))
            return gron_path
        end
    end
    
    print("Fetching latest gron release info...")
    local json_str, err = fetch_json(GRON_API_URL)
    if not json_str then
        return nil, err
    end
    
    local release = parse_release_info(json_str)
    if not release.tag then
        return nil, "Could not parse release info"
    end
    print("Latest release: " .. release.tag)
    
    local os_name = get_os()
    local arch = get_arch()
    print("Detecting platform: " .. os_name .. "-" .. arch)
    
    local asset_url = find_asset_url(release.assets, os_name, arch)
    if not asset_url then
        return nil, "No binary found for " .. os_name .. "-" .. arch
    end
    print("Downloading: " .. asset_url)
    
    exec_silent("mkdir -p " .. TMP_DIR)
    
    local archive_path = TMP_DIR .. "/gron.tgz"
    local ok = exec_silent("curl -sL -o '" .. archive_path .. "' '" .. asset_url .. "'")
    if not ok then
        return nil, "Failed to download gron"
    end
    
    ok = exec_silent("tar -xzf '" .. archive_path .. "' -C '" .. TMP_DIR .. "'")
    if not ok then
        return nil, "Failed to extract gron"
    end
    
    if os_name == "darwin" then
        print("Removing macOS quarantine attribute...")
        exec_silent("xattr -d com.apple.quarantine '" .. gron_path .. "' 2>/dev/null")
    end
    
    exec_silent("chmod +x '" .. gron_path .. "'")
    
    local version_out = exec(gron_path .. " --version 2>&1")
    if not version_out or not version_out:find("gron") then
        return nil, "Downloaded gron binary is not functional"
    end
    print("Installed: " .. version_out:gsub("%s+$", ""))
    
    return gron_path
end

local function ensure_gharchive_data()
    exec_silent("mkdir -p " .. TMP_DIR)
    
    if file_exists(GHARCHIVE_JSON) then
        local size = get_file_size(GHARCHIVE_JSON)
        if size > 1000000 then
            print("Using cached GH Archive data: " .. format_bytes(size))
            return GHARCHIVE_JSON, GHARCHIVE_GZ
        end
    end
    
    print("Downloading GH Archive sample data...")
    print("  URL: " .. GHARCHIVE_URL)
    
    local ok = exec_silent("curl -sL -o '" .. GHARCHIVE_GZ .. "' '" .. GHARCHIVE_URL .. "'")
    if not ok then
        print("  WARNING: Failed to download GH Archive data")
        return nil, nil
    end
    
    local gz_size = get_file_size(GHARCHIVE_GZ)
    print("  Downloaded: " .. format_bytes(gz_size) .. " (compressed)")
    
    print("  Decompressing...")
    ok = exec_silent("gunzip -k -f '" .. GHARCHIVE_GZ .. "'")
    if not ok then
        ok = exec_silent("gzip -d -k -f '" .. GHARCHIVE_GZ .. "'")
    end
    
    local json_path = GHARCHIVE_GZ:gsub("%.gz$", "")
    if file_exists(json_path) then
        if json_path ~= GHARCHIVE_JSON then
            exec_silent("mv '" .. json_path .. "' '" .. GHARCHIVE_JSON .. "'")
        end
    end
    
    if file_exists(GHARCHIVE_JSON) then
        local json_size = get_file_size(GHARCHIVE_JSON)
        print("  Decompressed: " .. format_bytes(json_size))
        return GHARCHIVE_JSON, GHARCHIVE_GZ
    else
        print("  WARNING: Decompression failed")
        return nil, nil
    end
end

local function find_interpreter(name)
    local result, ok = exec("which " .. name .. " 2>/dev/null")
    if ok and result and #result > 0 then
        return result:gsub("%s+$", "")
    end
    return nil
end

local function get_time_cmd()
    local handle = io.popen("which gdate 2>/dev/null")
    local result = handle:read("*a"):gsub("%s+$", "")
    handle:close()
    if result ~= "" then return "gdate +%s.%N" end
    
    handle = io.popen("date +%s.%N 2>/dev/null")
    result = handle:read("*a")
    handle:close()
    if result:match("^%d+%.%d+") then return "date +%s.%N" end
    
    return nil
end

local HIGH_RES_TIME_CMD = get_time_cmd()

local function run_timed(cmd)
    local time_ms, memory_bytes
    
    if HIGH_RES_TIME_CMD then
        local timing_script = string.format(
            "START=$(%s); /usr/bin/time -l %s >/dev/null 2>.tmp_time_out; END=$(%s); echo \"ELAPSED: $(echo \"$END - $START\" | bc)\"",
            HIGH_RES_TIME_CMD, cmd, HIGH_RES_TIME_CMD
        )
        local handle = io.popen(timing_script .. " 2>&1")
        local output = handle:read("*a")
        handle:close()
        
        local elapsed = output:match("ELAPSED:%s*([%d%.]+)")
        time_ms = elapsed and (tonumber(elapsed) * 1000) or nil
        
        local time_output_handle = io.open(".tmp_time_out", "r")
        if time_output_handle then
            local time_output = time_output_handle:read("*a")
            time_output_handle:close()
            memory_bytes = tonumber(time_output:match("(%d+)%s+maximum resident set size"))
        end
    else
        local handle = io.popen("/usr/bin/time -l " .. cmd .. " 2>&1 >/dev/null")
        local output = handle:read("*a")
        handle:close()
        
        local real_time = output:match("([%d%.]+)%s+real")
        time_ms = real_time and (tonumber(real_time) * 1000) or nil
        memory_bytes = tonumber(output:match("(%d+)%s+maximum resident set size"))
    end
    
    return {
        time_ms = time_ms,
        memory_bytes = memory_bytes
    }
end

local function calculate_stats(values)
    if #values == 0 then return nil end
    
    local sum = 0
    for _, v in ipairs(values) do
        sum = sum + v
    end
    local avg = sum / #values
    
    local variance = 0
    for _, v in ipairs(values) do
        variance = variance + (v - avg)^2
    end
    local stddev = math.sqrt(variance / #values)
    
    table.sort(values)
    local min_val = values[1]
    local max_val = values[#values]
    
    return {
        avg = avg,
        stddev = stddev,
        min = min_val,
        max = max_val
    }
end

local function benchmark_command(cmd, warmup, iterations)
    for _ = 1, warmup do
        run_timed(cmd)
    end
    
    local times = {}
    local memories = {}
    
    for _ = 1, iterations do
        local result = run_timed(cmd)
        if result.time_ms then
            table.insert(times, result.time_ms)
        end
        if result.memory_bytes then
            table.insert(memories, result.memory_bytes)
        end
    end
    
    return {
        time = calculate_stats(times),
        memory = calculate_stats(memories)
    }
end

local function print_separator(char, width)
    print(string.rep(char or "-", width or 80))
end

local function print_header(text)
    print()
    print_separator("=")
    print(text)
    print_separator("=")
end

local function run_benchmarks(gron_path, test_files)
    local luajit_path = find_interpreter("luajit")
    local lua_path = find_interpreter("lua") or find_interpreter("lua5.4") or find_interpreter("lua5.3") or find_interpreter("lua5.1")
    
    local interpreters = {}
    table.insert(interpreters, { name = "Go", cmd = gron_path })
    if luajit_path then
        table.insert(interpreters, { name = "LuaJIT", cmd = luajit_path .. " src/main.lua" })
    end
    if lua_path then
        table.insert(interpreters, { name = "Lua", cmd = lua_path .. " src/main.lua" })
    end
    
    print_header("Benchmark Configuration")
    print(string.format("Warmup runs:     %d", WARMUP_RUNS))
    print(string.format("Benchmark runs:  %d", BENCHMARK_RUNS))
    print(string.format("Interpreters:    %d", #interpreters))
    for _, interp in ipairs(interpreters) do
        print(string.format("  - %s: %s", interp.name, interp.cmd:match("^%S+")))
    end
    
    local all_results = {}
    
    for _, test_file in ipairs(test_files) do
        local file_size = get_file_size(test_file)
        print_header(string.format("Benchmarking: %s (%s)", test_file, format_bytes(file_size)))
        
        local file_results = {
            file = test_file,
            size = file_size,
            results = {}
        }
        
        for _, interp in ipairs(interpreters) do
            io.write(string.format("  Running %s... ", interp.name))
            io.flush()
            
            local cmd = interp.cmd .. " '" .. test_file .. "'"
            local stats = benchmark_command(cmd, WARMUP_RUNS, BENCHMARK_RUNS)
            
            file_results.results[interp.name] = stats
            
            if stats.time and stats.memory then
                print(string.format("%.1f ms (±%.1f), %s RSS", 
                    stats.time.avg, 
                    stats.time.stddev,
                    format_bytes(stats.memory.avg)))
            else
                print("FAILED")
            end
        end
        
        table.insert(all_results, file_results)
    end
    
    return all_results, interpreters
end

local function print_summary(all_results, interpreters)
    print_header("Summary Results")
    
    local col_width = 18
    local name_width = 30
    
    local header = string.format("%-" .. name_width .. "s", "File")
    for _, interp in ipairs(interpreters) do
        header = header .. string.format("%" .. col_width .. "s", interp.name .. " (ms)")
    end
    print(header)
    print_separator("-", name_width + col_width * #interpreters)
    
    for _, file_result in ipairs(all_results) do
        local short_name = file_result.file:match("[^/]+$") or file_result.file
        local row = string.format("%-" .. name_width .. "s", short_name)
        
        for _, interp in ipairs(interpreters) do
            local stats = file_result.results[interp.name]
            if stats and stats.time then
                row = row .. string.format("%" .. col_width .. "s", 
                    string.format("%.1f ±%.1f", stats.time.avg, stats.time.stddev))
            else
                row = row .. string.format("%" .. col_width .. "s", "N/A")
            end
        end
        print(row)
    end
    
    print()
    print("Memory Usage (Peak RSS):")
    print_separator("-", name_width + col_width * #interpreters)
    
    header = string.format("%-" .. name_width .. "s", "File")
    for _, interp in ipairs(interpreters) do
        header = header .. string.format("%" .. col_width .. "s", interp.name)
    end
    print(header)
    print_separator("-", name_width + col_width * #interpreters)
    
    for _, file_result in ipairs(all_results) do
        local short_name = file_result.file:match("[^/]+$") or file_result.file
        local row = string.format("%-" .. name_width .. "s", short_name)
        
        for _, interp in ipairs(interpreters) do
            local stats = file_result.results[interp.name]
            if stats and stats.memory then
                row = row .. string.format("%" .. col_width .. "s", format_bytes(stats.memory.avg))
            else
                row = row .. string.format("%" .. col_width .. "s", "N/A")
            end
        end
        print(row)
    end
    
    local go_results = {}
    for _, file_result in ipairs(all_results) do
        if file_result.results["Go"] and file_result.results["Go"].time then
            table.insert(go_results, file_result)
        end
    end
    
    if #go_results > 0 then
        print()
        print("Relative Performance (vs Go):")
        print_separator("-", name_width + col_width * (#interpreters - 1))
        
        header = string.format("%-" .. name_width .. "s", "File")
        for _, interp in ipairs(interpreters) do
            if interp.name ~= "Go" then
                header = header .. string.format("%" .. col_width .. "s", interp.name)
            end
        end
        print(header)
        print_separator("-", name_width + col_width * (#interpreters - 1))
        
        for _, file_result in ipairs(go_results) do
            local short_name = file_result.file:match("[^/]+$") or file_result.file
            local row = string.format("%-" .. name_width .. "s", short_name)
            local go_time = file_result.results["Go"].time.avg
            
            for _, interp in ipairs(interpreters) do
                if interp.name ~= "Go" then
                    local stats = file_result.results[interp.name]
                    if stats and stats.time and go_time > 0.001 then
                        local ratio = stats.time.avg / go_time
                        local label
                        if ratio >= 1 then
                            label = string.format("%.2fx slower", ratio)
                        elseif ratio > 0 then
                            label = string.format("%.2fx faster", 1/ratio)
                        else
                            label = "~same"
                        end
                        row = row .. string.format("%" .. col_width .. "s", label)
                    elseif stats and stats.time then
                        row = row .. string.format("%" .. col_width .. "s", "~same")
                    else
                        row = row .. string.format("%" .. col_width .. "s", "N/A")
                    end
                end
            end
            print(row)
        end
    end
end

local function run_streaming_benchmarks(gron_path, gz_file, interpreters)
    if not gz_file or not file_exists(gz_file) then
        print("\nSkipping streaming benchmarks (no compressed data available)")
        return nil
    end
    
    print_header("Streaming Benchmarks (gunzip | gron --stream)")
    
    local gz_size = get_file_size(gz_file)
    print(string.format("Source: %s (%s compressed)", gz_file, format_bytes(gz_size)))
    print()
    
    local streaming_results = {}
    
    for _, interp in ipairs(interpreters) do
        io.write(string.format("  Running %s... ", interp.name))
        io.flush()
        
        local gron_cmd
        if interp.name == "Go" then
            gron_cmd = interp.cmd .. " --stream"
        else
            gron_cmd = interp.cmd .. " --stream"
        end
        
        local times = {}
        local memories = {}
        
        for _ = 1, 1 do
            local timing_script = string.format(
                "START=$(%s); gunzip -c '%s' | /usr/bin/time -l %s >/dev/null 2>.tmp_stream_time; END=$(%s); echo \"ELAPSED: $(echo \"$END - $START\" | bc)\"",
                HIGH_RES_TIME_CMD, gz_file, gron_cmd, HIGH_RES_TIME_CMD
            )
            local handle = io.popen(timing_script .. " 2>/dev/null")
            local output = handle:read("*a")
            handle:close()
        end
        
        for _ = 1, 5 do
            local timing_script = string.format(
                "START=$(%s); gunzip -c '%s' | /usr/bin/time -l %s >/dev/null 2>.tmp_stream_time; END=$(%s); echo \"ELAPSED: $(echo \"$END - $START\" | bc)\"; cat .tmp_stream_time",
                HIGH_RES_TIME_CMD, gz_file, gron_cmd, HIGH_RES_TIME_CMD
            )
            local handle = io.popen(timing_script .. " 2>/dev/null")
            local output = handle:read("*a")
            handle:close()
            
            local elapsed = output:match("ELAPSED:%s*([%d%.]+)")
            local max_rss = output:match("(%d+)%s+maximum resident set size")
            
            if elapsed then
                table.insert(times, tonumber(elapsed) * 1000)
            end
            if max_rss then
                table.insert(memories, tonumber(max_rss))
            end
        end
        
        local stats = {
            time = calculate_stats(times),
            memory = calculate_stats(memories)
        }
        streaming_results[interp.name] = stats
        
        if stats.time then
            local mem_str = stats.memory and format_bytes(stats.memory.avg) or "N/A"
            print(string.format("%.0f ms (±%.0f), %s RSS", 
                stats.time.avg, 
                stats.time.stddev,
                mem_str))
        else
            print("FAILED")
        end
    end
    
    os.remove(".tmp_stream_time")
    
    return streaming_results
end

local function print_streaming_summary(streaming_results, interpreters)
    if not streaming_results then return end
    
    print_header("Streaming Benchmark Summary")
    
    local col_width = 20
    local name_width = 15
    
    local header = string.format("%-" .. name_width .. "s", "Interpreter")
    header = header .. string.format("%" .. col_width .. "s", "Time (ms)")
    header = header .. string.format("%" .. col_width .. "s", "Memory (RSS)")
    header = header .. string.format("%" .. col_width .. "s", "vs Go")
    print(header)
    print_separator("-", name_width + col_width * 3)
    
    local go_time = streaming_results["Go"] and streaming_results["Go"].time and streaming_results["Go"].time.avg
    
    for _, interp in ipairs(interpreters) do
        local stats = streaming_results[interp.name]
        if stats and stats.time then
            local row = string.format("%-" .. name_width .. "s", interp.name)
            row = row .. string.format("%" .. col_width .. "s", 
                string.format("%.1f ±%.1f", stats.time.avg, stats.time.stddev))
            row = row .. string.format("%" .. col_width .. "s", 
                stats.memory and format_bytes(stats.memory.avg) or "N/A")
            
            if interp.name == "Go" then
                row = row .. string.format("%" .. col_width .. "s", "-")
            elseif go_time and go_time > 0.001 then
                local ratio = stats.time.avg / go_time
                local label = ratio >= 1 and string.format("%.2fx slower", ratio) or string.format("%.2fx faster", 1/ratio)
                row = row .. string.format("%" .. col_width .. "s", label)
            else
                row = row .. string.format("%" .. col_width .. "s", "N/A")
            end
            
            print(row)
        end
    end
end

local function find_test_files(gharchive_json)
    local files = {}
    local handle = io.popen("ls testdata/*.json 2>/dev/null")
    if handle then
        for line in handle:lines() do
            if not line:match("big%.json$") or file_exists(line) then
                table.insert(files, line)
            end
        end
        handle:close()
    end
    
    if gharchive_json and file_exists(gharchive_json) then
        table.insert(files, gharchive_json)
    end
    
    table.sort(files, function(a, b)
        return get_file_size(a) < get_file_size(b)
    end)
    
    return files
end

local function main()
    print("gron-lua Benchmark Tool")
    print("Comparing Go gron vs Lua implementations")
    print()
    
    local gron_path, err = ensure_gron_binary()
    if not gron_path then
        print("ERROR: " .. (err or "Failed to get gron binary"))
        os.exit(1)
    end
    
    local gharchive_json, gharchive_gz = ensure_gharchive_data()
    
    local test_files = find_test_files(gharchive_json)
    if #test_files == 0 then
        print("ERROR: No test files found in testdata/")
        os.exit(1)
    end
    
    print(string.format("\nFound %d test files", #test_files))
    
    local all_results, interpreters = run_benchmarks(gron_path, test_files)
    print_summary(all_results, interpreters)
    
    local streaming_results = run_streaming_benchmarks(gron_path, gharchive_gz, interpreters)
    print_streaming_summary(streaming_results, interpreters)
    
    os.remove(".tmp_time_out")
    
    print()
    print("Benchmark complete.")
end

main()
