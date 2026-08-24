--- Utility functions for json-tsdb-plot
local M = {}

--- Parse date string to timestamp
-- Handles ISO 8601 (YYYY-MM-DD, YYYY-MM-DDTHH:MM:SS) and US format (MM/DD/YYYY)
function M.parse_date(date_str)
  if type(date_str) ~= "string" then return nil end
  -- YYYY-MM-DDTHH:MM:SS
  local y, m, d, h, min, s = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then
    -- YYYY-MM-DD
    y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    h, min, s = 0, 0, 0
  end
  if not y then
    -- MM/DD/YYYY
    m, d, y = date_str:match("^(%d%d)/(%d%d)/(%d%d%d%d)")
    h, min, s = 0, 0, 0
  end
  if not y then return nil end
  return os.time({year=y, month=m, day=d, hour=h, min=min, sec=s})
end

--- Add days to timestamp
function M.add_days(timestamp, days)
  if not timestamp or not days then return nil end
  return timestamp + (days * 86400)
end

--- Truncate string to max display width
function M.truncate(str, max_width)
  if type(str) ~= "string" then return "" end
  if vim.fn.strdisplaywidth(str) <= max_width then return str end
  local truncated = ""
  for i = 1, #str do
    local char = str:sub(i, i)
    if vim.fn.strdisplaywidth(truncated .. char .. "…") > max_width then
      break
    end
    truncated = truncated .. char
  end
  return truncated .. "…"
end

--- Pad string to width
function M.pad_right(str, width)
  if type(str) ~= "string" then str = tostring(str) end
  local len = vim.fn.strdisplaywidth(str)
  if len >= width then return str end
  return str .. string.rep(" ", width - len)
end

--- Format timestamp to date string
function M.format_date(timestamp, fmt)
  if not timestamp then return "" end
  return os.date(fmt or "%Y-%m-%d", timestamp)
end

--- Calculate days between two timestamps
function M.days_between(ts1, ts2)
  if not ts1 or not ts2 then return 0 end
  return math.floor(math.abs(os.difftime(ts1, ts2)) / 86400)
end

return M
