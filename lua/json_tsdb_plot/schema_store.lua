-- lua/json_tsdb_plot/schema_store.lua
-- Persists and manages saved schema configurations for JSON files / structures.

local M = {}

local function get_store_path()
  local data_dir = vim.fn.stdpath("data") .. "/json_tsdb_plot"
  vim.fn.mkdir(data_dir, "p")
  return data_dir .. "/saved_schemas.json"
end

--- Load all saved schemas from disk
--- @return table<string, table>
function M.load_all()
  local path = get_store_path()
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return {}
  end

  local content = table.concat(lines, "\n")
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

--- Save all schemas to disk
--- @param schemas table<string, table>
function M.save_all(schemas)
  local path = get_store_path()
  local ok, encoded = pcall(vim.json.encode, schemas)
  if ok and encoded then
    vim.fn.writefile({ encoded }, path)
  end
end

--- Generate a schema fingerprint key from available field names (sorted)
--- @param fields string[]
--- @param array_key string|nil
--- @return string
function M.generate_key(fields, array_key)
  local sorted = vim.deepcopy(fields)
  table.sort(sorted)
  local prefix = (array_key and array_key ~= "") and (array_key .. ":") or ""
  return prefix .. table.concat(sorted, ",")
end

--- Retrieve saved schemas for a specific structure or filepath
--- @param fields string[]
--- @param array_key string|nil
--- @param file_path string|nil
--- @return table[] List of matching saved schemas
function M.get_matching_schemas(fields, array_key, file_path)
  local all = M.load_all()
  local key = M.generate_key(fields, array_key)
  local matches = {}

  for schema_id, entry in pairs(all) do
    if entry.key == key or (file_path and entry.file_path == file_path and entry.array_key == (array_key or "")) then
      table.insert(matches, entry)
    end
  end

  -- Sort latest used first
  table.sort(matches, function(a, b)
    return (a.updated_at or 0) > (b.updated_at or 0)
  end)

  return matches
end

--- Save or update a schema selection
--- @param opts { name: string|nil, fields: string[], array_key: string|nil, file_path: string|nil, selections: table }
function M.save_schema(opts)
  local all = M.load_all()
  local key = M.generate_key(opts.fields, opts.array_key)
  local id = opts.name or (opts.file_path and (vim.fn.fnamemodify(opts.file_path, ":t") .. " (" .. os.date("%Y-%m-%d %H:%M") .. ")")) or ("Schema (" .. os.date("%Y-%m-%d %H:%M") .. ")")

  all[id] = {
    id = id,
    name = id,
    key = key,
    array_key = opts.array_key or "",
    file_path = opts.file_path,
    selections = opts.selections,
    updated_at = os.time(),
  }

  M.save_all(all)
end

return M
