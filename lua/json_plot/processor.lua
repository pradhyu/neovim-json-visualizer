-- lua/json_plot/processor.lua
-- Bridges parsed JSON + PlotDef objects into renderable entries.
-- Reads PlotDef fields as set by builder.lua and converts JSON data
-- into a flat array of { label, start_ts, end_ts, tag, color, raw } entries.

local parser = require("json_plot.parser")
local config_mod = require("json_plot.config")

local M = {}

--- Resolve a dot-separated path in a table (e.g., "patient.history")
--- @param data table  The root data table
--- @param path string Dot-separated path
--- @return any|nil    The resolved value, or nil if not found
local function resolve_path(data, path)
  if not path then return nil end
  if path == "" then return data end
  local current = data
  for part in string.gmatch(path, "[^%.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

--- Build the display label from an entry and its PlotDef
--- @param item table    The raw JSON entry
--- @param plot table    The PlotDef object
--- @return string       The formatted label
local function build_label(item, plot)
  local label = ""

  -- Label field: can be a string (field name) or function
  if type(plot._label) == "function" then
    local ok, result = pcall(plot._label, item)
    label = ok and tostring(result or "") or ""
  elseif type(plot._label) == "string" then
    label = tostring(item[plot._label] or "?")
  end

  -- Sublabel: appended in parentheses
  if plot._sublabel then
    local sub = item[plot._sublabel]
    if sub ~= nil then
      label = label .. " (" .. tostring(sub) .. ")"
    end
  end

  -- Tag prefix: prepended in brackets if tag is explicitly set on PlotDef
  if plot._tag and plot._tag ~= "" then
    label = "[" .. plot._tag .. "] " .. label
  end

  return label
end

--- Process all plot definitions against parsed JSON data
--- @param json_data table  The parsed root JSON object
--- @param plots table      Array of PlotDef objects from builder
--- @param global table     Global settings from builder
--- @return table           Array of renderable entries
function M.process(json_data, plots, global)
  local entries = {}
  local cfg = config_mod.get()
  local palette = cfg.palette or {
    "#5e81ac", "#a3be8c", "#ebcb8b", "#d08770", "#bf616a",
    "#b48ead", "#88c0d0", "#81a1c1", "#8fbcbb", "#e5e9f0"
  }

  local tag_color_map = {}
  local next_palette_idx = 1

  local function get_color_for_tag(tag)
    if not tag or tag == "" then return nil end
    if not tag_color_map[tag] then
      tag_color_map[tag] = palette[((next_palette_idx - 1) % #palette) + 1]
      next_palette_idx = next_palette_idx + 1
    end
    return tag_color_map[tag]
  end

  for _, plot in ipairs(plots) do
    local source = plot._source_path or ""
    local items = resolve_path(json_data, source)

    if type(items) ~= "table" or not vim.islist(items) then
      vim.notify(
        "json-plot: Source '" .. source .. "' not found or not an array",
        vim.log.levels.WARN
      )
      goto continue
    end

    for _, item in ipairs(items) do
      -- Apply filter if present
      if plot._filter then
        local ok, include = pcall(plot._filter, item)
        if not ok or not include then
          goto next_item
        end
      end

      -- Build label
      local label = build_label(item, plot)

      -- Parse start date
      local start_str = item[plot._start]
      if start_str == nil then
        goto next_item
      end
      local start_ts = parser.parse_date(tostring(start_str))
      if not start_ts then
        goto next_item
      end

      -- Determine end date (3 strategies)
      local end_ts = nil

      if plot._end_date and item[plot._end_date] then
        -- Strategy 1: Explicit end date field
        end_ts = parser.parse_date(tostring(item[plot._end_date]))

      elseif plot._end_computed_start and plot._end_computed_duration then
        -- Strategy 2: Computed from start_field + duration_field (days or hours)
        local base_str = item[plot._end_computed_start]
        local base_ts = base_str and parser.parse_date(tostring(base_str)) or start_ts
        local dur = tonumber(item[plot._end_computed_duration]) or 0
        end_ts = base_ts + (dur * 86400)

      elseif plot._end_computed_expr then
        -- Strategy 3: Custom expression function returning duration in days
        local ok, dur = pcall(plot._end_computed_expr, item)
        if ok and dur then
          end_ts = start_ts + (tonumber(dur) or 0) * 86400
        end
      end

      -- Fallback: if no end date resolved, default to start + 1 day
      if not end_ts then
        end_ts = start_ts + 86400
      end

      -- Ensure end >= start and at least 1 day width
      if end_ts < start_ts then
        end_ts = start_ts + 86400
      end
      if end_ts == start_ts then
        end_ts = start_ts + 86400
      end

      -- Determine tag/category:
      -- 1. If plot has explicit tag name
      -- 2. If plot has category_field specified from JSON item
      -- 3. If item has "category" or "tag" or "type" or "reason" field
      local entry_tag = plot._tag
      if plot._category_field and item[plot._category_field] ~= nil then
        entry_tag = tostring(item[plot._category_field])
      elseif (not entry_tag or entry_tag == "") and item.category then
        entry_tag = tostring(item.category)
      elseif (not entry_tag or entry_tag == "") and item.tag then
        entry_tag = tostring(item.tag)
      elseif (not entry_tag or entry_tag == "") and item.type then
        entry_tag = tostring(item.type)
      elseif (not entry_tag or entry_tag == "") and item.reason then
        entry_tag = tostring(item.reason)
      elseif (not entry_tag or entry_tag == "") and source ~= "" then
        entry_tag = source
      end

      -- Determine color:
      -- 1. Plot explicit color
      -- 2. Color mapped from tag/category
      -- 3. Fallback to palette[1]
      local entry_color = plot._color or get_color_for_tag(entry_tag) or palette[1]

      -- Determine group / swimlane:
      -- 1. Plot explicit group/swimlane
      -- 2. Fall back to source array name (if non-empty)
      local entry_group = plot._group or (source ~= "" and source or nil)

      table.insert(entries, {
        label = label,
        start_ts = start_ts,
        end_ts = end_ts,
        tag = entry_tag,
        color = entry_color,
        group = entry_group,
        source = source,
        raw = item,
      })

      ::next_item::
    end

    ::continue::
  end

  return entries
end

return M
