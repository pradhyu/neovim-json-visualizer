--- Default configuration and merge logic for json-plot.nvim
local M = {}

M.defaults = {
  date_formats = { "%Y-%m-%d", "%Y-%m-%dT%H:%M:%S", "%m/%d/%Y" },
  bar_char = "█",
  bar_half_char = "▌",
  empty_char = " ",
  label_width = 40,
  separator = " │ ",
  header_date_format = "%m/%d",
  default_sort = "start_desc",
  collapse_gaps = true,
  collapse_gap_threshold_days = 30,
  open_in = "tab",  -- "tab", "split", "vsplit", "float"
  fields = { label = nil, start = nil, end_date = nil, duration = nil, category = nil },
  theme = {
    canvas_bg = "#181825",      -- Dark Slate / Catppuccin Mocha canvas background
    canvas_fg = "#cdd6f4",      -- Crisp contrast text foreground
    header_fg = "#89b4fa",      -- Header dates & columns
    separator_fg = "#45475a",   -- Axis and swimlane divider lines
    guide_fg = "#fab387",       -- Overlap collision guide line
    warning_bg = "#f38ba8",     -- Warning highlight
    bar_text_dark = "#11111b",  -- Text printed on light/vibrant bar blocks
  },
  palette = {
    "#89b4fa", -- sky blue
    "#a6e3a1", -- mint green
    "#f9e2af", -- amber gold
    "#fab387", -- peach orange
    "#f38ba8", -- soft red
    "#cba6f7", -- lavender purple
    "#94e2d5", -- teal
    "#74c7ec", -- sapphire
    "#b4befe", -- light periwinkle
    "#eba0ac", -- flamingo
  },
}

M.options = {}

--- Deep merge with defaults
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

--- Return current options
function M.get()
  -- If setup was not called, return a copy of defaults
  if next(M.options) == nil then
    return vim.deepcopy(M.defaults)
  end
  return M.options
end

return M
