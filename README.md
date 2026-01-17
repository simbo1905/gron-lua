# gron-lua

A LuaJIT port of [gron](https://github.com/tomnomnom/gron). Transform JSON into discrete assignments to make it greppable.

## Overview

`gron-lua` transforms JSON into discrete assignments to make it easier to grep for what you want and see the absolute 'path' to it. It eases the exploration of APIs or large JSONL data extracts. 

```json
▶ gron "https://api.github.com/repos/tomnomnom/gron/commits?per_page=1" | fgrep "commit.author"
json[0].commit.author = {};
json[0].commit.author.date = "2016-07-02T10:54:34Z";
json[0].commit.author.email = "mail@tomnomnom.com";
json[0].commit.author.name = "Tom Hudson";
```

## Installation

### Single-file Bundle (Recommended)

You can download the single-file bundle, which has no external dependencies (other than a Lua 5.1+ or LuaJIT interpreter):

```bash
# Build it yourself
just bundle
cp dist/gron.lua /usr/local/bin/gron
```

### From Source

```bash
git clone https://github.com/yourusername/gron-lua
cd gron-lua
./gron --help
```

### Via LuaRocks

```bash
luarocks install gron-lua
```

## Usage

```
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
```

### Examples

**Basic Usage**

```bash
gron testdata/one.json
```

**Filter and Ungron**

```bash
gron http://jsonplaceholder.typicode.com/users/1 | grep company | gron --ungron
```

**Stream Mode (JSONL)**

```bash
cat data.jsonl | gron --stream
```

**Extract Values**

```bash
gron data.json | grep "id" | gron --values
```

## Development

This project uses `just` for task management and `mise` for tool versioning.

### Prerequisites

- `mise` (or manually install `luajit` and `just`)
- `luajit` (available via `brew install luajit` on macOS)

### Setup

```bash
mise install
```

### Testing

```bash
just test
```

### Packaging

Create a single-file distribution:

```bash
just bundle
```

This creates `dist/gron.lua`.

## Benchmarking Against Go gron

Compare the performance and memory usage of this Lua implementation against the original Go version:

```bash
just benchmark
```

This will:
1. Automatically download the latest Go gron release from GitHub (cached in `.tmp/`)
2. Download sample data from [GH Archive](https://www.gharchive.org/) for large-file benchmarks
3. Remove macOS quarantine if needed
4. Run file-based benchmarks over the test suite with multiple iterations
5. Run streaming benchmarks (`gunzip | gron --stream`) for NDJSON processing
6. Report wall-clock time and peak memory (RSS) for Go, Lua, and LuaJIT
7. Calculate averages, standard deviation, and relative performance

The benchmark uses GH Archive data (GitHub public timeline events) as a stable, large JSONL dataset for realistic performance testing.

## Project Structure

```
gron-lua/
├── bin/              # LuaRocks entry point
├── dist/             # Generated bundles
├── lib/              # External dependencies (json.lua)
├── scripts/          # Build scripts
├── src/
│   ├── main.lua      # CLI entry point
│   └── modules/      # Internal modules
│       ├── colors.lua
│       ├── gron.lua
│       └── json.lua
├── testdata/         # Test fixtures
└── tests/            # Unit tests
```

## License

MIT

## Why Lua? Memory Footprint and Download Size

This port exists for environments where **memory footprint and binary size matter more than raw speed** - for example, when running many concurrent agents or in resource-constrained environments.

Run `just benchmark` to compare Go gron, LuaJIT, and plain Lua on your machine.

**Memory footprint (peak RSS):**

- **Small-to-medium files:** LuaJIT uses ~2 MB vs Go's ~9 MB baseline - roughly **4-5x less memory**.
- **Large files (~1 MB JSON):** LuaJIT uses ~15 MB vs Go's ~30 MB - about **2x less memory**.
- **Streaming mode:** Memory savings are smaller; Lua's parse tree can grow larger for high-throughput NDJSON.

**Download/binary size:**

- Go gron binary: ~5-8 MB (platform-dependent)
- gron-lua single-file bundle: ~40 KB (requires a Lua interpreter)
- LuaJIT interpreter: ~500 KB - 1 MB

If you already have LuaJIT available, the total footprint is dramatically smaller.

**Speed trade-offs:**

- LuaJIT is within 10-50% of Go speed depending on workload - often negligible for typical use.
- Plain Lua (5.x) is 2-3x slower than Go but still usable.
- For small files, Lua implementations are often *faster* due to lower startup overhead.

These results vary by machine and input. The benchmark uses GH Archive data for realistic JSONL workloads.
