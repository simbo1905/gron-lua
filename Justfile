set shell := ["bash", "-cu"]

default:
    @just --list

install:
    mise install

test: test-json test-gron test-colors
    @echo "All tests passed!"

test-json:
    @echo "Running JSON module tests..."
    luajit tests/test_json.lua

test-gron:
    @echo "Running gron module tests..."
    luajit tests/test_gron.lua

test-colors:
    @echo "Running colors module tests..."
    luajit tests/test_colors.lua

run *ARGS:
    luajit src/main.lua {{ARGS}}

gron FILE:
    luajit src/main.lua {{FILE}}

ungron:
    luajit src/main.lua --ungron

compare FILE:
    @echo "=== Go gron output ==="
    @.tmp/gron {{FILE}} | head -20
    @echo ""
    @echo "=== Lua gron output ==="
    @luajit src/main.lua {{FILE}} | head -20

compare-full FILE:
    @echo "Comparing Lua gron with Go gron..."
    @.tmp/gron {{FILE}} > /tmp/go_gron.txt
    @luajit src/main.lua {{FILE}} > /tmp/lua_gron.txt
    @echo "Go gron lines: $$(wc -l < /tmp/go_gron.txt)"
    @echo "Lua gron lines: $$(wc -l < /tmp/lua_gron.txt)"
    @diff /tmp/go_gron.txt /tmp/lua_gron.txt && echo "Output matches!" || echo "Differences found"

roundtrip FILE:
    @echo "Testing roundtrip: JSON -> gron -> ungron -> JSON"
    @luajit src/main.lua {{FILE}} | luajit src/main.lua --ungron

lib-size:
    @echo "Library file sizes:"
    @wc -c lib/json.lua src/modules/*.lua
    @echo ""
    @echo "Total source lines:"
    @wc -l lib/json.lua src/modules/*.lua src/main.lua

bundle:
    @echo "Creating single-file bundle..."
    luajit scripts/bundle.lua
    @echo ""
    @echo "Testing bundle..."
    @luajit dist/gron.lua --version
    @luajit dist/gron.lua testdata/one.json | head -5

bundle-test:
    @echo "Testing bundle against Go gron..."
    @.tmp/gron testdata/one.json > /tmp/go_gron.txt
    @luajit dist/gron.lua testdata/one.json > /tmp/lua_bundle.txt
    @diff /tmp/go_gron.txt /tmp/lua_bundle.txt && echo "Bundle output matches Go gron!" || echo "Differences found"

rocks-install:
    @echo "Installing via LuaRocks (local)..."
    luarocks make gron-lua-0.1.0-1.rockspec --local

rocks-remove:
    @echo "Removing LuaRocks installation..."
    luarocks remove gron-lua --local || true

dist: bundle
    @echo ""
    @echo "Distribution files created in dist/"
    @ls -la dist/

all: test bundle lib-size
    @echo ""
    @echo "Project structure:"
    @echo "  src/main.lua        - CLI entry point"
    @echo "  src/modules/        - Core modules"
    @echo "  lib/                - External libraries (json.lua)"
    @echo "  tests/              - Unit tests"
    @echo "  testdata/           - Test JSON files"
    @echo "  dist/               - Distribution bundles"
    @echo ""
    @echo "Distribution:"
    @echo "  just bundle         - Create single-file dist/gron.lua"
    @echo "  just rocks-install  - Install via LuaRocks"

benchmark:
    @echo "Running benchmark comparison against Go gron..."
    luajit scripts/compare_to_original.lua

clean:
    rm -rf dist/
    rm -rf .tmp/
    rm -f .tmp_time_out
