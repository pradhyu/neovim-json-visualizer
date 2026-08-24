--- Highlight group management for json-tsdb-plot
local M = {}

local hl_cache = {}

--- Define default highlight groups
function M.setup()
  vim.api.nvim_set_hl(0, "TimelineHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "TimelineSeparator", { link = "LineNr", default = true })
  vim.api.nvim_set_hl(0, "TimelineLabel", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "TimelineLegend", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "TimelineTitle", { link = "Directory", default = true })
end

--- Create highlight group from hex color
function M.ensure_hl_group(hex)
  if not hex or type(hex) ~= "string" then return nil end
  
  -- ensure leading #
  if not hex:match("^#") then
    hex = "#" .. hex
  end
  
  local name = "TsdbPlot_" .. hex:sub(2):upper()
  
  if hl_cache[name] then
    return name
  end
  
  vim.api.nvim_set_hl(0, name, { fg = hex, bold = true })
  hl_cache[name] = true
  
  return name
end

--- Assign colors to entries based on tags
function M.assign_colors(entries, color_map)
  if type(entries) ~= "table" or type(color_map) ~= "table" then return end
  
  for _, entry in ipairs(entries) do
    if type(entry) == "table" and entry.tag then
      local hex = color_map[entry.tag]
      if hex then
        entry.hl_group = M.ensure_hl_group(hex)
      end
    end
  end
end

--- Clear highlight cache
function M.clear_cache()
  hl_cache = {}
end

return M
