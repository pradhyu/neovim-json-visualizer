--- JSON parsing and field detection for json-plot.nvim
local M = {}

local utils = require("json_plot.utils")

--- Read and parse JSON file
function M.read_file(path)
  if not path or path == "" then return nil, "Invalid path" end
  if vim.fn.filereadable(path) ~= 1 then return nil, "File not readable" end
  
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then return nil, "Empty file" end
  
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then return nil, "Failed to parse JSON: " .. tostring(data) end
  
  return data
end

--- Read and parse JSON from buffer
function M.read_buffer(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then return nil, "Invalid buffer" end
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not lines or #lines == 0 then return nil, "Empty buffer" end
  
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then return nil, "Failed to parse JSON: " .. tostring(data) end
  
  return data
end

--- Scan array and return sorted unique field names
function M.detect_fields(data)
  if type(data) ~= "table" then return {} end
  
  local fields = {}
  local seen = {}
  
  for _, entry in ipairs(data) do
    if type(entry) == "table" then
      for k, _ in pairs(entry) do
        if type(k) == "string" and not seen[k] then
          seen[k] = true
          table.insert(fields, k)
        end
      end
    end
  end
  
  table.sort(fields)
  return fields
end

--- Try to parse date string in multiple formats
function M.parse_date(date_str)
  return utils.parse_date(date_str)
end

--- Resolve dot-separated path in a table
function M.resolve_path(data, path)
  if type(data) ~= "table" or type(path) ~= "string" then return nil end
  if path == "" then return data end
  
  local current = data
  for segment in path:gmatch("[^%.]+") do
    if type(current) ~= "table" then return nil end
    current = current[segment]
  end
  
  return current
end

return M
