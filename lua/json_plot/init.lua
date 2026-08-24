-- lua/json_plot/init.lua
-- Main entry point for json-plot.nvim
-- Orchestrates: config loading → JSON parsing → processing → rendering
-- Supports hot-reloading for development via :JsonPlotReload

local M = {}

--- Setup the plugin with user options
--- @param opts table|nil  User configuration overrides
function M.setup(opts)
  local config = require("json_plot.config")
  config.setup(opts)

  local highlights = require("json_plot.highlights")
  highlights.setup()
end

--- Main entry point: open a timeline chart
--- @param data_path string       Path to the JSON data file
--- @param config_path string|nil Path to the Lua config file (optional)
function M.open(data_path, config_path)
  local builder = require("json_plot.builder")
  local parser = require("json_plot.parser")
  local processor = require("json_plot.processor")
  local renderer = require("json_plot.renderer")
  local ui = require("json_plot.ui")

  -- Expand paths
  data_path = vim.fn.expand(data_path)

  -- 1. Reset builder state from any previous config load
  builder.reset()

  -- 2. Find and load config file
  config_path = config_path and vim.fn.expand(config_path) or M._find_config(data_path)

  if config_path then
    local ok, err = pcall(dofile, config_path)
    if not ok then
      vim.notify(
        "json-plot: Error loading config '" .. config_path .. "': " .. tostring(err),
        vim.log.levels.ERROR
      )
      return
    end
  end

  -- 3. Parse JSON data
  local json_data, parse_err = parser.read_file(data_path)
  if not json_data then
    vim.notify(
      "json-plot: " .. tostring(parse_err),
      vim.log.levels.ERROR
    )
    return
  end

  -- 4. Check if we have plot definitions from the config
  local plots = builder.get_plots()
  local global = builder.get_global()

  if #plots > 0 then
    -- Config-driven mode: process and render
    M._process_and_render(json_data, plots, global, data_path)
  else
    -- Interactive fallback: detect fields and prompt
    M._interactive_open(json_data, global, data_path)
  end
end

--- Process entries through plot definitions and render
--- @param json_data table        Parsed JSON data
--- @param plots table            Array of PlotDef objects
--- @param global table           Global builder settings
--- @param data_path string|nil   Data file path
function M._process_and_render(json_data, plots, global, data_path)
  local processor = require("json_plot.processor")
  local renderer = require("json_plot.renderer")

  local entries = processor.process(json_data, plots, global)

  if #entries == 0 then
    vim.notify("json-plot: No entries produced. Check your config field mappings.", vim.log.levels.WARN)
    return
  end

  -- Attach data_path to global settings for renderer/exporter
  global = vim.deepcopy(global or {})
  if data_path and not global.data_path then
    global.data_path = data_path
  end

  -- Sort entries by default sort order
  local cfg = require("json_plot.config").get()
  local sort_order = global.sort or cfg.default_sort or "start_desc"
  table.sort(entries, function(a, b)
    if sort_order == "start_desc" then
      return a.start_ts > b.start_ts
    elseif sort_order == "start" or sort_order == "start_asc" then
      return a.start_ts < b.start_ts
    elseif sort_order == "end_desc" then
      return a.end_ts > b.end_ts
    elseif sort_order == "end" or sort_order == "end_asc" then
      return a.end_ts < b.end_ts
    elseif sort_order == "duration" or sort_order == "duration_desc" then
      return (a.end_ts - a.start_ts) > (b.end_ts - b.start_ts)
    elseif sort_order == "label" or sort_order == "label_asc" then
      return a.label < b.label
    end
    return a.start_ts > b.start_ts
  end)

  return renderer.render(entries, global)
end

--- Interactive mode: detect fields and use vim.ui.select prompts
--- @param json_data table        Parsed JSON data
--- @param global table           Global builder settings
--- @param data_path string|nil   Data file path
function M._interactive_open(json_data, global, data_path)
  local parser = require("json_plot.parser")
  local processor = require("json_plot.processor")
  local renderer = require("json_plot.renderer")
  local ui = require("json_plot.ui")
  local builder = require("json_plot.builder")

  -- If root is a flat array, use it directly
  if vim.islist(json_data) then
    local fields = parser.detect_fields(json_data)
    ui.select_fields(fields, { array_key = "", file_path = data_path }, function(selections)
      if not selections then return end

      -- Create a plot definition from selections
      builder.reset()
      local plot = builder.plot("")  -- empty path = use root array
      plot:label(selections.label)
      plot:start(selections.start)
      if selections.end_date then
        plot:end_date(selections.end_date)
      elseif selections.duration then
        plot:end_computed(selections.start, selections.duration)
      end
      if selections.category then
        plot:category_field(selections.category)
      end

      -- Process the root array directly
      local wrapped = { [""] = json_data }
      M._process_and_render(wrapped, builder.get_plots(), global, data_path)
    end)
    return
  end

  -- If root is an object, let user pick which array to plot
  if type(json_data) == "table" then
    local array_keys = {}
    for key, value in pairs(json_data) do
      if type(value) == "table" and vim.islist(value) then
        table.insert(array_keys, key)
      end
    end
    table.sort(array_keys)

    if #array_keys == 0 then
      vim.notify("json-plot: No arrays found in JSON root", vim.log.levels.ERROR)
      return
    end

    ui.select_multiple_sources(array_keys, function(selected_sources)
      if not selected_sources or #selected_sources == 0 then return end

      builder.reset()

      local function configure_source(idx)
        if idx > #selected_sources then
          -- All sources configured; process and render swimlanes
          return M._process_and_render(json_data, builder.get_plots(), global, data_path)
        end

        local source = selected_sources[idx]
        local fields = parser.detect_fields(json_data[source])

        ui.select_fields(fields, { array_key = source, file_path = data_path }, function(selections)
          if not selections then return end

          local plot = builder.plot(source)
          plot:group(source) -- Assign swimlane
          plot:label(selections.label)
          plot:start(selections.start)
          if selections.end_date then
            plot:end_date(selections.end_date)
          elseif selections.duration then
            plot:end_computed(selections.start, selections.duration)
          end
          if selections.category then
            plot:category_field(selections.category)
          end

          configure_source(idx + 1)
        end)
      end

      configure_source(1)
    end)
  end
end

--- Auto-detect config file in the same directory as the data file
--- Looks for .json_plot.lua, json_plot.config.lua, etc.
--- @param data_path string  Path to the JSON data file
--- @return string|nil       Path to the config file, or nil
function M._find_config(data_path)
  local dir = vim.fn.fnamemodify(data_path, ":h")
  local candidates = {
    ".json_plot.lua",
    "json_plot.config.lua",
    ".tsdb_plot.lua",
    "tsdb_plot.config.lua",
    ".timeline.lua",
    "timeline.config.lua",
  }
  for _, name in ipairs(candidates) do
    local path = dir .. "/" .. name
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

--- Hot-reload: clear all cached modules and re-require
--- Use this during development to pick up code changes without restarting Neovim
function M.reload()
  -- Clear all json_plot modules from Lua's package cache
  local cleared = {}
  for name, _ in pairs(package.loaded) do
    if name:match("^json_plot") or name:match("^json_tsdb_plot") then
      package.loaded[name] = nil
      table.insert(cleared, name)
    end
  end

  -- Re-require the main module
  local plugin = require("json_plot")

  -- Re-setup highlights
  require("json_plot.highlights").setup()

  vim.notify(
    "json-plot: Reloaded " .. #cleared .. " module(s)",
    vim.log.levels.INFO
  )

  return plugin
end

return M
