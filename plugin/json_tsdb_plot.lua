-- plugin/json_tsdb_plot.lua
-- Registers :TsdbPlot and :TsdbPlotReload commands on Neovim startup.
-- This file is auto-loaded by Neovim's plugin system.

-- Guard against double-loading
if vim.g.loaded_json_tsdb_plot then
  return
end
vim.g.loaded_json_tsdb_plot = true

-- :TsdbPlot [data.json] [config.lua]
-- Open a timeline/Gantt chart from a JSON data file.
-- If no data.json is specified, uses the current buffer file if it's a JSON file.
-- If a config.lua is not provided, looks for .tsdb_plot.lua in the same
-- directory as the data file, or falls back to interactive field selection.
vim.api.nvim_create_user_command("TsdbPlot", function(opts)
  local args = vim.split(vim.trim(opts.args or ""), "%s+")
  local data_path = args[1]
  local config_path = args[2]

  if not data_path or data_path == "" then
    local current_buf_name = vim.api.nvim_buf_get_name(0)
    if current_buf_name ~= "" and current_buf_name:match("%.json$") then
      data_path = current_buf_name
    else
      -- Search for first open JSON buffer if current buffer is terminal/helper
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          local bname = vim.api.nvim_buf_get_name(buf)
          if bname:match("%.json$") then
            data_path = bname
            break
          end
        end
      end
    end
  end

  if not data_path or data_path == "" then
    vim.notify("Usage: :TsdbPlot [data.json] [config.lua] (No active JSON buffer found)", vim.log.levels.ERROR)
    return
  end

  require("json_tsdb_plot").open(data_path, config_path)
end, {
  nargs = "*",
  complete = "file",
  desc = "Open JSON timeline/Gantt chart",
})

-- :TsdbPlotReload
-- Hot-reload all plugin modules. Use during development to pick up
-- code changes without restarting Neovim.
vim.api.nvim_create_user_command("TsdbPlotReload", function()
  -- Clear and re-require (must clear this file's guard too)
  vim.g.loaded_json_tsdb_plot = nil
  require("json_tsdb_plot").reload()
end, {
  nargs = 0,
  desc = "Hot-reload json-tsdb-plot plugin modules",
})
