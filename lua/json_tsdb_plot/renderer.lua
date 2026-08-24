-- lua/json_tsdb_plot/renderer.lua
-- ASCII Gantt chart renderer for json-tsdb-plot.
-- Renders entries as colored horizontal bars in a scratch buffer.
-- Supports gap collapsing, zoom, sort, filter, and detail view via buffer-local keymaps.

local M = {}

-- Namespace for extmark highlights
local ns = vim.api.nvim_create_namespace("tsdb_plot_bars")

-- Module-level state storage keyed by buffer handle.
M._buffer_states = {}

-- Counter for unique buffer names
M._buf_counter = 0

--------------------------------------------------------------------------------
-- Time Mapping with Gap Collapsing
--------------------------------------------------------------------------------

--- Build continuous or gap-collapsed time segments from active entries
--- @param filtered table List of active entries
--- @param state table Buffer state
--- @return table Map structure with conversion functions and segments
function M._build_time_map(filtered, state)
  local min_entry_ts = filtered[1].start_ts
  local max_entry_ts = filtered[1].end_ts
  for _, e in ipairs(filtered) do
    if e.start_ts < min_entry_ts then min_entry_ts = e.start_ts end
    if e.end_ts > max_entry_ts then max_entry_ts = e.end_ts end
  end

  local collapse = state.collapse_gaps
  if collapse == nil then
    collapse = (state.global_config and state.global_config.collapse_gaps ~= nil)
      and state.global_config.collapse_gaps
      or true
  end

  local gap_threshold = (state.global_config and state.global_config.collapse_gap_threshold_days) or 30
  local gap_threshold_sec = gap_threshold * 86400

  -- Standard linear mapping if gap collapsing is off
  if not collapse then
    local min_ts = min_entry_ts - 86400
    local max_ts = max_entry_ts + 86400
    local total_days = math.max(1, (max_ts - min_ts) / 86400)

    return {
      min_ts = min_ts,
      max_ts = max_ts,
      is_collapsed = false,
      total_units = total_days,
      ts_to_unit = function(ts)
        return math.max(0, (ts - min_ts) / 86400)
      end,
      unit_to_ts = function(unit)
        return min_ts + (unit * 86400)
      end,
      get_markers = function(units_per_marker)
        local markers = {}
        local u = 0
        while u <= total_days do
          table.insert(markers, {
            unit = u,
            label = os.date("%m/%d/%y", min_ts + (u * 86400)),
            is_break = false,
          })
          u = u + units_per_marker
        end
        return markers
      end,
    }
  end

  -- Detect intervals and gaps (sorted from most recent to oldest: descending)
  local intervals = {}
  for _, e in ipairs(filtered) do
    table.insert(intervals, { start_ts = e.start_ts - 86400, end_ts = e.end_ts + 86400 })
  end
  table.sort(intervals, function(a, b) return a.end_ts > b.end_ts end)

  local merged = {}
  local cur = { start_ts = intervals[1].start_ts, end_ts = intervals[1].end_ts }
  for i = 2, #intervals do
    local nxt = intervals[i]
    if nxt.end_ts >= cur.start_ts - gap_threshold_sec then
      if nxt.start_ts < cur.start_ts then
        cur.start_ts = nxt.start_ts
      end
    else
      table.insert(merged, cur)
      cur = { start_ts = nxt.start_ts, end_ts = nxt.end_ts }
    end
  end
  table.insert(merged, cur)

  -- Build segmented timeline units (Left = Most Recent, Right = Past)
  local segments = {}
  local current_unit = 0
  local break_size_units = 3 -- visual gap size for collapsed breaks

  for i, seg in ipairs(merged) do
    local seg_days = math.max(1, (seg.end_ts - seg.start_ts) / 86400)
    local s = {
      start_ts = seg.start_ts,
      end_ts = seg.end_ts,
      seg_days = seg_days,
      unit_start = current_unit,
      unit_end = current_unit + seg_days,
    }
    table.insert(segments, s)
    current_unit = current_unit + seg_days
    if i < #merged then
      current_unit = current_unit + break_size_units
    end
  end

  local total_units = math.max(1, current_unit)

  return {
    min_ts = min_entry_ts,
    max_ts = max_entry_ts,
    is_collapsed = (#segments > 1),
    segments = segments,
    total_units = total_units,
    ts_to_unit = function(ts)
      for _, s in ipairs(segments) do
        if ts >= s.start_ts and ts <= s.end_ts then
          local offset_days = (s.end_ts - ts) / 86400
          return math.max(0, s.unit_start + offset_days)
        elseif ts > s.end_ts then
          return math.max(0, s.unit_start)
        end
      end
      return total_units
    end,
    get_markers = function(units_per_marker)
      local markers = {}
      for i, s in ipairs(segments) do
        local u = 0
        while u <= s.seg_days do
          local ts = s.end_ts - (u * 86400)
          table.insert(markers, {
            unit = s.unit_start + u,
            label = os.date("%m/%d/%y", ts),
            is_break = false,
          })
          u = u + math.max(1, units_per_marker)
        end
        if i < #segments then
          table.insert(markers, {
            unit = s.unit_end + 1,
            label = "≈≈",
            is_break = true,
          })
        end
      end
      return markers
    end,
  }
end

--------------------------------------------------------------------------------
-- Header: build date markers along the time axis
--------------------------------------------------------------------------------
function M._build_header(time_map, chars_per_unit, chart_width, label_width, separator)
  local header = string.rep(" ", label_width) .. separator
  local current_col = 0

  local min_spacing_chars = 11 -- MM/DD/YY is 8 chars + spacing
  local units_per_marker = math.max(1, math.ceil(min_spacing_chars / math.max(chars_per_unit, 0.01)))

  local markers = time_map.get_markers(units_per_marker)
  local header_str = ""

  for _, m in ipairs(markers) do
    local target_col = math.floor(m.unit * chars_per_unit)
    if target_col >= current_col and target_col + #m.label <= chart_width then
      local padding = target_col - current_col
      header_str = header_str .. string.rep(" ", padding) .. m.label
      current_col = target_col + #m.label
    end
  end

  return header .. header_str
end

--------------------------------------------------------------------------------
-- Legend: show tag → color mapping at the bottom
--------------------------------------------------------------------------------
function M._build_legend(entries)
  local unique_tags = {}
  local tag_order = {}

  for _, e in ipairs(entries) do
    local tag_name = e.tag or "default"
    if e.color and not unique_tags[tag_name] then
      unique_tags[tag_name] = e.color
      table.insert(tag_order, tag_name)
    end
  end

  if #tag_order == 0 then return "", {} end

  local legend_str = "Legend: "
  local hls = {}
  local bar_char = "█"
  local bar_char_bytes = #bar_char

  for i, tag in ipairs(tag_order) do
    if i > 1 then legend_str = legend_str .. "  " end
    local start_idx = #legend_str
    legend_str = legend_str .. bar_char .. " " .. tag
    table.insert(hls, {
      start_col = start_idx,
      end_col = start_idx + bar_char_bytes,
      color = unique_tags[tag],
    })
  end

  return legend_str, hls
end

--------------------------------------------------------------------------------
-- Buffer management
--------------------------------------------------------------------------------
function M._open_buffer(buf, open_in)
  if open_in == "tab" then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, buf)
  elseif open_in == "split" then
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
  elseif open_in == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
  elseif open_in == "float" then
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.8)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = col,
      row = row,
      style = "minimal",
      border = "rounded",
    })
  else
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, buf)
  end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("winhighlight", "Normal:TsdbPlotCanvas,NormalNC:TsdbPlotCanvas,EndOfBuffer:TsdbPlotCanvas", { win = win })
end

--------------------------------------------------------------------------------
-- Detail popup: show full JSON for entry under cursor
--------------------------------------------------------------------------------
function M._show_detail(buf, line_0indexed)
  local state = M._buffer_states[buf]
  if not state then return end

  local entry = state.line_to_entry[line_0indexed]
  if not entry then return end

  local lines = {
    "┌─ Entry Details ─────────────────────────────┐",
    "  Label : " .. entry.label,
    "  Start : " .. os.date("%Y-%m-%d", entry.start_ts),
    "  End   : " .. os.date("%Y-%m-%d", entry.end_ts),
    "  Days  : " .. tostring(math.ceil((entry.end_ts - entry.start_ts) / 86400)),
  }
  if entry.tag then
    table.insert(lines, "  Tag   : " .. entry.tag)
  end
  table.insert(lines, "└─────────────────────────────────────────────┘")
  table.insert(lines, "")
  table.insert(lines, "Raw JSON:")

  local ok, raw_json = pcall(vim.fn.json_encode, entry.raw)
  if ok and raw_json then
    raw_json = raw_json:gsub(",", ",\n  ")
    raw_json = raw_json:gsub("^{", "{\n  ")
    raw_json = raw_json:gsub("}$", "\n}")
    for s in raw_json:gmatch("[^\r\n]+") do
      table.insert(lines, s)
    end
  end

  local detail_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, lines)
  vim.bo[detail_buf].modifiable = false
  vim.bo[detail_buf].bufhidden = "wipe"

  local width = 60
  local height = math.min(#lines + 2, 30)
  vim.api.nvim_open_win(detail_buf, true, {
    relative = "cursor",
    width = width,
    height = height,
    col = 2,
    row = 1,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = detail_buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = detail_buf, silent = true })
end

--------------------------------------------------------------------------------
-- Help popup
--------------------------------------------------------------------------------
function M._show_help(buf)
  local lines = {
    "╭─ json-tsdb-plot Keybindings ─╮",
    "│                              │",
    "│  q      Close chart          │",
    "│  + =    Zoom in              │",
    "│  -      Zoom out             │",
    "│  p      Toggle track packing │",
    "│  o      Toggle overlap panel │",
    "│  s      Cycle sort order     │",
    "│  c      Toggle gap collapse  │",
    "│  f      Filter by date range │",
    "│  F      Filter by tag/series │",
    "│  r      Reset filters & zoom │",
    "│  w      Export to Markdown   │",
    "│  Enter  Show entry details   │",
    "│  ?      Show this help       │",
    "│                              │",
    "╰──────────────────────────────╯",
  }

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].bufhidden = "wipe"

  vim.api.nvim_open_win(help_buf, true, {
    relative = "editor",
    width = 34,
    height = #lines,
    col = math.floor((vim.o.columns - 34) / 2),
    row = math.floor((vim.o.lines - #lines) / 2),
    style = "minimal",
    border = "none",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = help_buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = help_buf, silent = true })
  vim.keymap.set("n", "?", "<cmd>close<cr>", { buffer = help_buf, silent = true })
end

--------------------------------------------------------------------------------
-- Keymaps
--------------------------------------------------------------------------------
function M._set_keymaps(buf)
  local opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set("n", "q", "<cmd>close<cr>", opts)

  vim.keymap.set("n", "+", function() M._zoom(buf, 1.5) end, opts)
  vim.keymap.set("n", "=", function() M._zoom(buf, 1.5) end, opts)
  vim.keymap.set("n", "-", function() M._zoom(buf, 0.67) end, opts)

  vim.keymap.set("n", "p", function() M._toggle_packing(buf) end, opts)
  vim.keymap.set("n", "o", function() M._toggle_overlaps(buf) end, opts)
  vim.keymap.set("n", "s", function() M._cycle_sort(buf) end, opts)
  vim.keymap.set("n", "c", function() M._toggle_collapse(buf) end, opts)

  vim.keymap.set("n", "f", function() M._prompt_date_filter(buf) end, opts)
  vim.keymap.set("n", "F", function() M._prompt_tag_filter(buf) end, opts)
  vim.keymap.set("n", "r", function() M._reset_filters(buf) end, opts)
  vim.keymap.set("n", "w", function() M._export_markdown(buf) end, opts)

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    M._show_detail(buf, cursor[1] - 1)
  end, opts)

  vim.keymap.set("n", "?", function() M._show_help(buf) end, opts)
end

function M._export_markdown(buf)
  local state = M._buffer_states[buf]
  if not state then return end

  local orig_path = state.source_file
  local default_md_name = "tsdb_plot.md"
  if orig_path and orig_path ~= "" then
    default_md_name = orig_path:gsub("%.json$", "") .. ".md"
  end

  vim.ui.input({ prompt = "Export timeline to Markdown file:", default = default_md_name }, function(out_path)
    if not out_path or out_path == "" then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local md_content = {
      "# TSDB Timeline Visualization",
      "",
      "Source: `" .. (orig_path or "json-tsdb-plot") .. "`",
      "Generated on: `" .. os.date("%Y-%m-%d %H:%M:%S") .. "`",
      "",
      "```text",
    }
    for _, l in ipairs(lines) do
      table.insert(md_content, l)
    end
    table.insert(md_content, "```")
    table.insert(md_content, "")

    local ok, err = pcall(vim.fn.writefile, md_content, out_path)
    if ok then
      vim.notify("Timeline exported successfully to: " .. out_path, vim.log.levels.INFO)
    else
      vim.notify("Error exporting markdown: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

--------------------------------------------------------------------------------
-- Interactive actions
--------------------------------------------------------------------------------
function M._zoom(buf, factor)
  local state = M._buffer_states[buf]
  if not state then return end
  state.zoom_factor = (state.zoom_factor or 1.0) * factor
  state.zoom_factor = math.max(0.1, math.min(state.zoom_factor, 20.0))
  M._do_render(buf, state)
end

function M._toggle_packing(buf)
  local state = M._buffer_states[buf]
  if not state then return end
  if state.dense_packing == nil then
    state.dense_packing = false
  else
    state.dense_packing = not state.dense_packing
  end
  vim.notify("Multi-track density packing: " .. (state.dense_packing and "ENABLED" or "DISABLED"), vim.log.levels.INFO)
  M._do_render(buf, state)
end

function M._toggle_overlaps(buf)
  local state = M._buffer_states[buf]
  if not state then return end
  state.show_overlaps = not state.show_overlaps
  vim.notify("Clinical overlap & collision diagnostics: " .. (state.show_overlaps and "ENABLED" or "DISABLED"), vim.log.levels.INFO)
  M._do_render(buf, state)
end

function M._toggle_collapse(buf)
  local state = M._buffer_states[buf]
  if not state then return end
  state.collapse_gaps = not state.collapse_gaps
  vim.notify("Gap collapsing: " .. (state.collapse_gaps and "ENABLED" or "DISABLED"), vim.log.levels.INFO)
  M._do_render(buf, state)
end

function M._cycle_sort(buf)
  local state = M._buffer_states[buf]
  if not state then return end

  local orders = { "start_desc", "start_asc", "end_desc", "end_asc", "duration_desc", "label_asc" }
  local labels = {
    start_desc = "Sort: Start Date ↓ (Most Recent First)",
    start_asc = "Sort: Start Date ↑ (Oldest First)",
    end_desc = "Sort: End Date ↓",
    end_asc = "Sort: End Date ↑",
    duration_desc = "Sort: Duration ↓",
    label_asc = "Sort: Label A→Z",
  }
  state.sort_idx = ((state.sort_idx or 1) % #orders) + 1
  state.sort_order = orders[state.sort_idx]

  vim.notify(labels[state.sort_order] or state.sort_order, vim.log.levels.INFO)
  M._do_render(buf, state)
end

function M._prompt_date_filter(buf)
  vim.ui.input({ prompt = "Filter start date (YYYY-MM-DD): " }, function(start_str)
    if not start_str or start_str == "" then return end
    vim.ui.input({ prompt = "Filter end date (YYYY-MM-DD): " }, function(end_str)
      if not end_str or end_str == "" then return end

      local p = require("json_tsdb_plot.parser")
      local start_ts = p.parse_date(start_str)
      local end_ts = p.parse_date(end_str)

      if start_ts and end_ts then
        local state = M._buffer_states[buf]
        if not state then return end
        state.filters.start_ts = start_ts
        state.filters.end_ts = end_ts
        M._do_render(buf, state)
      else
        vim.notify("json-tsdb-plot: Invalid date format", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M._prompt_tag_filter(buf)
  local state = M._buffer_states[buf]
  if not state then return end

  local unique_tags = {}
  local tags_list = { "── Show all (reset) ──" }
  for _, e in ipairs(state.all_entries) do
    if e.tag and not unique_tags[e.tag] then
      unique_tags[e.tag] = true
      table.insert(tags_list, e.tag)
    end
  end

  if #tags_list <= 1 then
    vim.notify("No tags available to filter", vim.log.levels.INFO)
    return
  end

  vim.ui.select(tags_list, { prompt = "Filter by tag:" }, function(selected)
    if not selected then return end
    if selected == "── Show all (reset) ──" then
      state.filters.tag = nil
    else
      state.filters.tag = selected
    end
    M._do_render(buf, state)
  end)
end

function M._reset_filters(buf)
  local state = M._buffer_states[buf]
  if not state then return end
  state.filters = {}
  state.zoom_factor = 1.0
  state.sort_order = (state.global_config and state.global_config.default_sort) or "start_desc"
  state.sort_idx = 1
  state.collapse_gaps = true
  vim.notify("Filters and zoom reset", vim.log.levels.INFO)
  M._do_render(buf, state)
end

--------------------------------------------------------------------------------
-- Highlight group helper and Canvas Theme Setup
--------------------------------------------------------------------------------
local hl_cache = {}

local function setup_canvas_theme(cfg)
  local theme = (cfg and cfg.theme) or require("json_tsdb_plot.config").get().theme or {}
  local canvas_bg = theme.canvas_bg or "#181825"
  local canvas_fg = theme.canvas_fg or "#cdd6f4"
  local header_fg = theme.header_fg or "#89b4fa"
  local separator_fg = theme.separator_fg or "#45475a"
  local guide_fg = theme.guide_fg or "#fab387"

  vim.api.nvim_set_hl(0, "TsdbPlotCanvas", { bg = canvas_bg, fg = canvas_fg })
  vim.api.nvim_set_hl(0, "TsdbPlotHeader", { bg = canvas_bg, fg = header_fg, bold = true })
  vim.api.nvim_set_hl(0, "TsdbPlotSeparator", { bg = canvas_bg, fg = separator_fg })
  vim.api.nvim_set_hl(0, "TsdbPlotSwimlane", { bg = canvas_bg, fg = "#f5c2e7", bold = true })
  vim.api.nvim_set_hl(0, "TsdbPlotGuide", { bg = canvas_bg, fg = guide_fg, bold = true })
  vim.api.nvim_set_hl(0, "TsdbPlotConflict", { bg = canvas_bg, fg = "#f38ba8", bold = true })
  vim.api.nvim_set_hl(0, "TsdbPlotStatus", { bg = canvas_bg, fg = "#a6adc8", italic = true })
end

local function get_or_create_hl(hex)
  if not hex then return "TsdbPlotCanvas" end
  local hl_name = "TsdbPlot_" .. hex:gsub("#", "")
  if not hl_cache[hl_name] then
    -- Background colored block with contrasting text, plus standalone fg
    vim.api.nvim_set_hl(0, hl_name, { bg = hex, fg = "#11111b", bold = true })
    vim.api.nvim_set_hl(0, hl_name .. "_fg", { fg = hex, bold = true })
    hl_cache[hl_name] = true
  end
  return hl_name
end

--------------------------------------------------------------------------------
-- Core rendering: builds lines and applies extmark highlights
--------------------------------------------------------------------------------
function M._do_render(buf, state)
  -- Apply custom background & canvas theme
  setup_canvas_theme(state.global_config)

  -- Set buffer/window local highlights for full custom background coverage
  local wins = vim.fn.win_findbuf(buf)
  for _, w in ipairs(wins) do
    vim.api.nvim_set_option_value("winhighlight", "Normal:TsdbPlotCanvas,NormalNC:TsdbPlotCanvas,EndOfBuffer:TsdbPlotCanvas", { win = w })
  end

  -- Filter entries
  local filtered = {}
  for _, e in ipairs(state.all_entries) do
    local include = true
    if state.filters.tag and e.tag ~= state.filters.tag then
      include = false
    end
    if state.filters.start_ts and e.end_ts < state.filters.start_ts then
      include = false
    end
    if state.filters.end_ts and e.start_ts > state.filters.end_ts then
      include = false
    end
    if include then
      table.insert(filtered, e)
    end
  end

  -- Sort entries (defaults to start_desc = most recent to past)
  local sort_order = state.sort_order or "start_desc"
  table.sort(filtered, function(a, b)
    if sort_order == "start_desc" then
      return a.start_ts > b.start_ts
    elseif sort_order == "start_asc" then
      return a.start_ts < b.start_ts
    elseif sort_order == "end_desc" then
      return a.end_ts > b.end_ts
    elseif sort_order == "end_asc" then
      return a.end_ts < b.end_ts
    elseif sort_order == "duration_desc" then
      return (a.end_ts - a.start_ts) > (b.end_ts - b.start_ts)
    elseif sort_order == "label_asc" then
      return a.label < b.label
    end
    return a.start_ts > b.start_ts
  end)

  vim.bo[buf].modifiable = true

  if #filtered == 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "No entries to display.",
      "",
      "Press 'r' to reset filters, or 'q' to close.",
    })
    vim.bo[buf].modifiable = false
    return
  end

  -- Build gap-collapsed / linear time mapping
  local time_map = M._build_time_map(filtered, state)

  -- Chart dimensions
  local label_width = 40
  local separator = " │ "
  local sep_display_width = vim.fn.strdisplaywidth(separator)

  local win_width = vim.api.nvim_win_get_width(0)
  if win_width < 80 then win_width = 120 end

  local chart_width = win_width - label_width - sep_display_width
  if chart_width < 20 then chart_width = 20 end

  local base_chars_per_unit = chart_width / time_map.total_units
  local chars_per_unit = base_chars_per_unit * (state.zoom_factor or 1.0)

  -- Build output
  local lines = {}
  local extmarks = {}
  local line_to_entry = {}

  -- Title
  if state.global_config and state.global_config.title then
    table.insert(lines, state.global_config.title)
    table.insert(lines, "")
  end

  -- Header with date markers
  local header_str = M._build_header(time_map, chars_per_unit, chart_width, label_width, separator)
  table.insert(lines, header_str)

  -- Separator line
  local sep_line = string.rep("─", label_width) .. "┼" .. string.rep("─", chart_width + 2)
  table.insert(lines, sep_line)

  -- Group entries by swimlane/group if multiple groups exist
  local group_names = {}
  local group_entries = {}
  local has_multiple_groups = false

  for _, entry in ipairs(filtered) do
    local gname = entry.group or ""
    if not group_entries[gname] then
      group_entries[gname] = {}
      table.insert(group_names, gname)
    end
    table.insert(group_entries[gname], entry)
  end

  if #group_names > 1 or (group_names[1] and group_names[1] ~= "") then
    has_multiple_groups = true
  end

  -- Pre-compute all pairwise overlap intervals for vertical guide lines
  local overlap_regions = {}
  local overlaps = {}
  for i = 1, #filtered do
    local a = filtered[i]
    for j = i + 1, #filtered do
      local b = filtered[j]
      local overlap_start = math.max(a.start_ts, b.start_ts)
      local overlap_end = math.min(a.end_ts, b.end_ts)
      if overlap_start < overlap_end then
        local overlap_days = math.ceil((overlap_end - overlap_start) / 86400)
        local u1 = time_map.ts_to_unit(overlap_start)
        local u2 = time_map.ts_to_unit(overlap_end)
        local col1 = math.floor(u1 * chars_per_unit)
        local col2 = math.floor(u2 * chars_per_unit)
        local ov_c_start = math.max(0, math.min(col1, col2))
        local ov_c_end = math.max(col1, col2)

        -- Only draw full-height vertical guide lines for multi-day overlaps (> 1d) so single-day events stay uncluttered
        if overlap_days > 1 then
          table.insert(overlap_regions, {
            col_start = ov_c_start,
            col_end = ov_c_end,
            start_ts = overlap_start,
            end_ts = overlap_end,
          })
        end

        table.insert(overlaps, {
          entry_a = a,
          entry_b = b,
          start_ts = overlap_start,
          end_ts = overlap_end,
          days = overlap_days,
          col_start = ov_c_start,
          col_end = ov_c_end,
        })
      end
    end
  end

  -- Entry rows (with optional multi-track dense packing for high entry counts)
  local bar_char = "█"
  local bar_char_bytes = #bar_char
  local enable_dense_packing = (state.dense_packing ~= false)

  for _, gname in ipairs(group_names) do
    local entries_in_group = group_entries[gname]

    -- Sort entries chronologically for optimal track packing
    table.sort(entries_in_group, function(a, b)
      return a.start_ts < b.start_ts
    end)

    -- Pack non-overlapping entries into compact parallel tracks
    local tracks = {} -- array of track arrays: tracks[track_idx] = { {entry=e, start_col=c1, end_col=c2, bar=str}, ... }
    if enable_dense_packing and #entries_in_group > 8 then
      for _, entry in ipairs(entries_in_group) do
        local u1 = time_map.ts_to_unit(entry.start_ts)
        local u2 = time_map.ts_to_unit(entry.end_ts)
        local col1 = math.floor(u1 * chars_per_unit)
        local col2 = math.floor(u2 * chars_per_unit)
        local b_start = math.max(0, math.min(col1, col2))
        local b_end = math.max(col1, col2)
        local b_len = math.max(1, b_end - b_start)

        local days = math.max(1, math.ceil((entry.end_ts - entry.start_ts) / 86400))
        local days_label = tostring(days) .. "d"
        local short_label = entry.label
        if #short_label > 12 then short_label = short_label:sub(1, 10) .. "…" end
        local pill_text = short_label .. " (" .. days_label .. ")"

        local bar_content = " " .. pill_text .. " "
        if b_len >= #pill_text + 4 then
          local pad = b_len - #pill_text
          local pad_l = math.floor(pad / 2)
          local pad_r = pad - pad_l
          bar_content = string.rep(" ", pad_l) .. pill_text .. string.rep(" ", pad_r)
        end
        local bar_display_w = vim.fn.strdisplaywidth(bar_content)
        local item_end_col = b_start + bar_display_w + 1

        -- Check track collision taking direction into account
        local placed = false
        for t_idx, track in ipairs(tracks) do
          local collides = false
          for _, prev in ipairs(track) do
            -- Interval overlap check: [min_a, max_a] overlaps with [min_b, max_b]
            local a1, a2 = math.min(prev.start_col, prev.end_col), math.max(prev.start_col, prev.end_col)
            local b1, b2 = math.min(b_start, item_end_col), math.max(b_start, item_end_col)
            if not (b2 + 1 < a1 or b1 > a2 + 1) then
              collides = true
              break
            end
          end
          if not collides then
            table.insert(track, {
              entry = entry,
              start_col = b_start,
              end_col = item_end_col,
              bar = bar_content,
            })
            placed = true
            break
          end
        end

        if not placed then
          table.insert(tracks, {
            {
              entry = entry,
              start_col = b_start,
              end_col = item_end_col,
              bar = bar_content,
            }
          })
        end
      end
    end

    -- Render swimlane header
    if has_multiple_groups and gname ~= "" then
      local track_info = (#tracks > 0) and (" · " .. #tracks .. " packed tracks") or ""
      local swimlane_title = "─── " .. string.upper(gname) .. " (" .. #entries_in_group .. " entries" .. track_info .. ") "
      local swimlane_line = swimlane_title .. string.rep("─", math.max(0, (label_width + chart_width + sep_display_width + 2) - vim.fn.strdisplaywidth(swimlane_title)))
      table.insert(lines, swimlane_line)
      local sw_line_idx = #lines - 1
      table.insert(extmarks, {
        line = sw_line_idx,
        col_start = 0,
        col_end = #swimlane_line,
        hl_group = "TsdbPlotSwimlane",
      })
    end

    if #tracks > 0 then
      -- Render compact tracks
      for t_idx, track in ipairs(tracks) do
        local track_label = string.format("Track %d (%d items)", t_idx, #track)
        local pad_l = math.max(0, label_width - vim.fn.strdisplaywidth(track_label))
        local prefix = string.rep(" ", pad_l) .. track_label .. separator

        local chart_chars = {}
        for c = 0, chart_width + 20 do chart_chars[c + 1] = " " end

        -- Stamp track items
        for _, item in ipairs(track) do
          local bar_str = item.bar
          for c = 0, vim.fn.strdisplaywidth(bar_str) - 1 do
            local pos = item.start_col + c + 1
            if pos <= #chart_chars then
              chart_chars[pos] = bar_str:sub(c + 1, c + 1)
            end
          end
        end

        local full_line = prefix .. table.concat(chart_chars):gsub("%s+$", "")
        if full_line == prefix then full_line = prefix .. " " end
        table.insert(lines, full_line)
        local cur_l_idx = #lines - 1

        -- Highlight track label and separator
        table.insert(extmarks, {
          line = cur_l_idx,
          col_start = pad_l,
          col_end = pad_l + #track_label,
          hl_group = "TsdbPlotStatus",
        })
        table.insert(extmarks, {
          line = cur_l_idx,
          col_start = label_width,
          col_end = label_width + #separator,
          hl_group = "TsdbPlotSeparator",
        })

        -- Highlight each individual pill bar in this track
        for _, item in ipairs(track) do
          local hl_group = get_or_create_hl(item.entry.color)
          local hl_fg = hl_group .. "_fg"
          local bar_byte_start = #prefix + item.start_col
          local bar_byte_end = bar_byte_start + #item.bar

          table.insert(extmarks, {
            line = cur_l_idx,
            col_start = bar_byte_start,
            col_end = bar_byte_end,
            hl_group = hl_group,
          })
          line_to_entry[cur_l_idx] = item.entry
        end
      end
    else
      -- Standard flat single-row rendering (for smaller groups)
      for _, entry in ipairs(entries_in_group) do
        local label = entry.label or ""
        local label_display_width = vim.fn.strdisplaywidth(label)

        if label_display_width > label_width then
          label = vim.fn.strcharpart(label, 0, label_width - 1) .. "…"
          label_display_width = vim.fn.strdisplaywidth(label)
        end

        local label_padding = math.max(0, label_width - label_display_width)
        local padded_label = string.rep(" ", label_padding) .. label

        local u1 = time_map.ts_to_unit(entry.start_ts)
        local u2 = time_map.ts_to_unit(entry.end_ts)
        local col1 = math.floor(u1 * chars_per_unit)
        local col2 = math.floor(u2 * chars_per_unit)
        local bar_start_col = math.max(0, math.min(col1, col2))
        local bar_end_col = math.max(col1, col2)
        local bar_len = math.max(1, bar_end_col - bar_start_col)

        local days = math.max(1, math.ceil((entry.end_ts - entry.start_ts) / 86400))
        local days_label = tostring(days) .. "d"
        local start_str = os.date("%m/%d", entry.start_ts)
        local end_str = os.date("%m/%d", entry.end_ts)
        local range_str = start_str .. "→" .. end_str .. " (" .. days_label .. ")"

        local bar = ""
        if bar_len >= #range_str + 2 then
          local pad = bar_len - #range_str
          local pad_l = math.floor(pad / 2)
          local pad_r = pad - pad_l
          bar = string.rep(" ", pad_l) .. range_str .. string.rep(" ", pad_r)
        elseif bar_len >= #days_label + 2 then
          local pad = bar_len - #days_label
          local pad_l = math.floor(pad / 2)
          local pad_r = pad - pad_l
          bar = string.rep(" ", pad_l) .. days_label .. string.rep(" ", pad_r)
        else
          bar = " " .. range_str .. " "
        end

        local prefix = padded_label .. separator .. string.rep(" ", bar_start_col)
        local full_line = prefix .. bar

        table.insert(lines, full_line)
        local current_line_idx = #lines - 1
        line_to_entry[current_line_idx] = entry

        local hl_group = get_or_create_hl(entry.color)
        local hl_fg = hl_group .. "_fg"

        table.insert(extmarks, {
          line = current_line_idx,
          col_start = label_padding,
          col_end = label_padding + #label,
          hl_group = hl_fg,
        })
        table.insert(extmarks, {
          line = current_line_idx,
          col_start = label_width,
          col_end = label_width + #separator,
          hl_group = "TsdbPlotSeparator",
        })
        table.insert(extmarks, {
          line = current_line_idx,
          col_start = #prefix,
          col_end = #prefix + #bar,
          hl_group = hl_group,
        })
      end
    end
  end

  -- Bottom separator
  table.insert(lines, sep_line)

  -- On-demand Overlap Analysis Panel (toggled via 'o')
  if state.show_overlaps and #overlaps > 0 then
    local ov_header = "─── CLINICAL OVERLAPS & CONCURRENCIES (" .. #overlaps .. " detected) "
    local ov_line = ov_header .. string.rep("─", math.max(0, (label_width + chart_width + sep_display_width + 2) - vim.fn.strdisplaywidth(ov_header)))
    table.insert(lines, ov_line)
    local ov_hdr_idx = #lines - 1
    table.insert(extmarks, {
      line = ov_hdr_idx,
      col_start = 0,
      col_end = #ov_line,
      hl_group = "TsdbPlotConflict",
    })

    for _, ov in ipairs(overlaps) do
      local ov_len = math.max(1, ov.col_end - ov.col_start)
      local ov_lbl = string.format("⚡ %dd overlap", ov.days)
      local dotted_bar = "┆" .. string.rep("╌", math.max(0, ov_len - 2)) .. "┆"
      if ov_len < 2 then dotted_bar = "┆" end

      local item_desc = string.format("%s ↔ %s", ov.entry_a.label, ov.entry_b.label)
      if vim.fn.strdisplaywidth(item_desc) > label_width then
        item_desc = vim.fn.strcharpart(item_desc, 0, label_width - 1) .. "…"
      end
      local pad_left = math.max(0, label_width - vim.fn.strdisplaywidth(item_desc))
      local row_prefix = string.rep(" ", pad_left) .. item_desc .. separator .. string.rep(" ", ov.col_start)
      local row_full = row_prefix .. dotted_bar .. " " .. ov_lbl

      table.insert(lines, row_full)
      local ov_line_idx = #lines - 1

      table.insert(extmarks, {
        line = ov_line_idx,
        col_start = #row_prefix,
        col_end = #row_prefix + #dotted_bar + #ov_lbl + 1,
        hl_group = "TsdbPlotConflict",
      })
    end
    table.insert(lines, sep_line)
  end

  -- Legend
  local legend_str, legend_hls = M._build_legend(filtered)
  if legend_str ~= "" then
    table.insert(lines, legend_str)
    local legend_line_idx = #lines - 1
    for _, lhl in ipairs(legend_hls) do
      local hl_name = get_or_create_hl(lhl.color)
      table.insert(extmarks, {
        line = legend_line_idx,
        col_start = lhl.start_col,
        col_end = lhl.end_col,
        hl_group = hl_name .. "_fg",
      })
    end
  end

  -- Status line
  local status_parts = {}
  if state.filters.tag then
    table.insert(status_parts, "Tag: " .. state.filters.tag)
  end
  if state.filters.start_ts then
    table.insert(status_parts, "From: " .. os.date("%Y-%m-%d", state.filters.start_ts))
  end
  if state.filters.end_ts then
    table.insert(status_parts, "To: " .. os.date("%Y-%m-%d", state.filters.end_ts))
  end
  if time_map.is_collapsed then
    table.insert(status_parts, "Gaps: Collapsed (c to toggle)")
  end
  if state.zoom_factor and state.zoom_factor ~= 1.0 then
    table.insert(status_parts, string.format("Zoom: %.0f%%", state.zoom_factor * 100))
  end
  if #status_parts > 0 then
    table.insert(lines, "")
    local st_text = "Active: " .. table.concat(status_parts, " | ") .. "  (press r to reset, ? for help)"
    table.insert(lines, st_text)
    local st_idx = #lines - 1
    table.insert(extmarks, {
      line = st_idx,
      col_start = 0,
      col_end = #st_text,
      hl_group = "TsdbPlotStatus",
    })
  end

  state.line_to_entry = line_to_entry

  -- Write lines to buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Clear and re-apply highlights
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(extmarks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, mark.line, mark.col_start, {
      end_col = mark.col_end,
      hl_group = mark.hl_group,
      priority = 100,
    })
  end

  vim.bo[buf].modifiable = false
  M._buffer_states[buf] = state
end

--------------------------------------------------------------------------------
-- Main entry: create buffer, store state, render, and set keymaps
--------------------------------------------------------------------------------
function M.render(entries, global_config)
  if not entries or #entries == 0 then
    vim.notify("json-tsdb-plot: No entries to render", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  M._buf_counter = (M._buf_counter or 0) + 1
  pcall(vim.api.nvim_buf_set_name, buf, "tsdb-plot://" .. M._buf_counter .. "_" .. os.time())

  local cfg = global_config or {}
  local state = {
    all_entries = entries,
    global_config = cfg,
    source_file = cfg.data_path or (entries[1] and entries[1].source_file),
    zoom_factor = 1.0,
    sort_order = cfg.default_sort or "start_desc",
    sort_idx = 1,
    collapse_gaps = (cfg.collapse_gaps ~= nil) and cfg.collapse_gaps or true,
    filters = {},
    line_to_entry = {},
  }

  M._buffer_states[buf] = state

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      M._buffer_states[buf] = nil
    end,
  })

  M._open_buffer(buf, cfg.open_in or "tab")
  M._do_render(buf, state)
  M._set_keymaps(buf)

  return buf
end

return M
