package = "gron-lua"
version = "0.0.1-1"
source = {
    url = "https://github.com/simbo1905/gron-lua.git",
    tag = "v0.0.1"
}
description = {
    summary = "Transform JSON into discrete assignments to make it greppable",
    detailed = [[
        gron-lua is a Lua/LuaJIT port of gron, a tool that transforms JSON into 
        discrete assignments to make it greppable. It supports flattening JSON 
        to gron format, unflattening gron back to JSON, streaming JSONL input,
        and colorized output.
    ]],
    homepage = "https://github.com/simbo1905/gron-lua",
    license = "MIT"
}
dependencies = {
    "lua >= 5.1"
}
build = {
    type = "builtin",
    modules = {
        ["gron.json"] = "lib/json.lua",
        ["gron.colors"] = "src/modules/colors.lua",
        ["gron.core"] = "src/modules/gron.lua",
        ["gron.json_wrapper"] = "src/modules/json.lua",
    },
    install = {
        bin = {
            ["gron"] = "bin/gron.lua"
        }
    }
}
