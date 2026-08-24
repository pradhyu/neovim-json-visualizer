-- plugin/json_plot.lua
-- Registers :JsonPlot and :JsonPlotReload commands on Neovim startup.
-- This file is auto-loaded by Neovim's plugin system.

-- Guard against double-loading
if vim.g.loaded_json_plot then
  return
end
vim.g.loaded_json_plot = true

-- Handler function for JsonPlot command
local function open_plot(opts)
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
    vim.notify("Usage: :JsonPlot [data.json] [config.lua] (No active JSON buffer found)", vim.log.levels.ERROR)
    return
  end

  require("json_plot").open(data_path, config_path)
end

-- :JsonPlot [data.json] [config.lua]
-- Open a timeline/Gantt chart from a JSON data file.
vim.api.nvim_create_user_command("JsonPlot", open_plot, {
  nargs = "*",
  complete = "file",
  desc = "Open JSON timeline/Gantt chart",
})

-- Alias for backwards compatibility
vim.api.nvim_create_user_command("TsdbPlot", open_plot, {
  nargs = "*",
  complete = "file",
  desc = "Open JSON timeline/Gantt chart (alias for JsonPlot)",
})

-- Handler function for reload
local function reload_plugin()
  vim.g.loaded_json_plot = nil
  vim.g.loaded_json_tsdb_plot = nil
  require("json_plot").reload()
end

-- :JsonPlotReload
-- Hot-reload all plugin modules.
vim.api.nvim_create_user_command("JsonPlotReload", reload_plugin, {
  nargs = 0,
  desc = "Hot-reload json-plot plugin modules",
})

-- Alias for backwards compatibility
vim.api.nvim_create_user_command("TsdbPlotReload", reload_plugin, {
  nargs = 0,
  desc = "Hot-reload json-plot plugin modules (alias for JsonPlotReload)",
})
