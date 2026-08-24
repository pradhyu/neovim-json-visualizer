# json-tsdb-plot.nvim

A Neovim plugin that reads JSON files with time-series data and renders interactive ASCII Gantt charts in a buffer. Define multiple plot series with a fluent Lua API config file — each with its own data source, field mappings, colors, and tags.

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)

## Features

- 📊 **ASCII Gantt chart** rendered with Unicode block characters and extmark colors
- 🔧 **Fluent config API** — define multiple series from different JSON paths
- 📅 **Computed end dates** — `end_computed("fillDate", "daysSupply")` for prescription data
- 🎨 **Color-coded** bars per series/tag via hex colors
- 🔍 **Interactive** — zoom, sort, filter by date range or tag, detail popup
- 🔄 **Hot-reloadable** — `:TsdbPlotReload` for development without restarting Neovim
- 📋 **Interactive fallback** — works without a config file via `vim.ui.select` prompts

## Installation

### lazy.nvim

```lua
{
  -- For development (local path):
  dir = "~/git/jaeger",
  config = function()
    require("json_tsdb_plot").setup()
  end,
}
```

```lua
-- Or from GitHub (once published):
{
  "yourusername/json-tsdb-plot.nvim",
  config = function()
    require("json_tsdb_plot").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "yourusername/json-tsdb-plot.nvim",
  config = function()
    require("json_tsdb_plot").setup()
  end,
}
```

### Manual / vim-plug

Add the plugin directory to your runtimepath:

```vim
set runtimepath+=~/git/jaeger
```

Then in your `init.lua`:

```lua
require("json_tsdb_plot").setup()
```

## Quick Start

### 1. Create a JSON data file

```json
{
  "medicalHistory": [
    {
      "facility": "General Hospital",
      "admitDate": "2024-01-15",
      "dischargeDate": "2024-01-22",
      "diagnosis": "Pneumonia"
    }
  ],
  "pharmacyHistory": [
    {
      "drugName": "Amoxicillin 500mg",
      "fillDate": "2024-01-16",
      "daysSupply": 10
    }
  ]
}
```

### 2. Create a config file (`.tsdb_plot.lua`)

```lua
local tl = require("json_tsdb_plot.builder")

tl.title("Patient Timeline")

tl.plot("medicalHistory")
  :label("facility")
  :start("admitDate")
  :end_date("dischargeDate")
  :tag("Admit")
  :color("#e06c75")

tl.plot("pharmacyHistory")
  :label("drugName")
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Rx Fill")
  :color("#98c379")

tl.sort("start")
```

### 3. Open the chart

```vim
:TsdbPlot data.json .tsdb_plot.lua
```

Or if `.tsdb_plot.lua` is in the same directory as the JSON file:

```vim
:TsdbPlot data.json
```

## Config API Reference

### Plot Definition

```lua
local tl = require("json_tsdb_plot.builder")

tl.plot("jsonPath")           -- Create series from JSON key (supports dot notation)
  :label("fieldName")         -- Label field (string or function)
  :label(function(e) return e.name .. " (" .. e.id .. ")" end)
  :sublabel("fieldName")      -- Secondary label appended in parens
  :start("fieldName")         -- Start date field
  :end_date("fieldName")      -- Explicit end date field
  :end_computed("startField", "durationField")  -- end = start + duration (days)
  :end_computed_expr(function(e) return e.weeks * 7 end)  -- Custom duration calc
  :tag("SeriesName")          -- Tag shown as [Tag] prefix + legend
  :color("#hex")              -- Hex color for bars
  :filter(function(e) return e.status == "active" end)  -- Predicate filter
```

### Global Settings

```lua
tl.title("Chart Title")       -- Chart title (displayed at top)
tl.sort("start")              -- Default sort: "start", "end", "duration", "label"
tl.date_format("%Y-%m-%d")    -- Date parsing format
```

## Keybindings (in chart buffer)

| Key | Action |
|-----|--------|
| `q` | Close the chart |
| `+` / `=` | Zoom in |
| `-` | Zoom out |
| `s` | Cycle sort order |
| `f` | Filter by date range |
| `F` | Filter by tag/series |
| `r` | Reset all filters & zoom |
| `Enter` | Show entry details |
| `?` | Show help |

## Commands

| Command | Description |
|---------|-------------|
| `:TsdbPlot <data.json> [config.lua]` | Open timeline chart |
| `:TsdbPlotReload` | Hot-reload plugin (for development) |

## Config File Discovery

The plugin looks for a config file in this order:

1. **Explicit argument**: `:TsdbPlot data.json my_config.lua`
2. `.tsdb_plot.lua` in the same directory as the JSON file
3. `tsdb_plot.config.lua` in the same directory
4. `.timeline.lua` in the same directory
5. **Fallback**: Interactive `vim.ui.select` field selection

## Development

### Hot Reload

During development, use `:TsdbPlotReload` to clear Lua module caches and re-require all plugin modules without restarting Neovim.

### Running Tests

```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Examples

See the `examples/` directory for complete config files:

- `patient_timeline.lua` — Medical admissions + pharmacy fills + active prescriptions
- `opioid_monitor.lua` — Opioid + benzodiazepine overlap monitoring
- `care_coordination.lua` — SNF → Home Health → Therapy continuum

Each has a matching JSON fixture in `tests/fixtures/`.

## License

MIT
