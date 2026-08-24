-- lua/json_tsdb_plot/ui.lua
-- Interactive UI fallbacks and multi-selection menus for json-tsdb-plot.

local M = {}

--- Format a schema selection preview for menu display
local function format_schema_label(entry)
  local sel = entry.selections or {}
  local parts = { "Label: " .. (sel.label or "?"), "Start: " .. (sel.start or "?") }
  if sel.end_date then
    table.insert(parts, "End: " .. sel.end_date)
  elseif sel.duration then
    table.insert(parts, "Duration: " .. sel.duration)
  end
  if sel.category then
    table.insert(parts, "Cat: " .. sel.category)
  end
  return string.format("%s  [%s]", entry.name or "Saved Schema", table.concat(parts, ", "))
end

--- Multi-select arrays / data sources with toggle checkboxes
--- @param array_keys string[]
--- @param callback fun(selected_sources: string[]|nil)
function M.select_multiple_sources(array_keys, callback)
  if #array_keys == 1 then
    return callback({ array_keys[1] })
  end

  local selected = {}
  -- Select all by default
  for _, k in ipairs(array_keys) do
    selected[k] = true
  end

  local function show_menu()
    local items = {}
    for _, k in ipairs(array_keys) do
      local check = selected[k] and "[✔]" or "[ ]"
      table.insert(items, {
        id = k,
        type = "toggle",
        label = string.format("%s  %s", check, k),
      })
    end
    table.insert(items, {
      id = "__done__",
      type = "done",
      label = "── ▶ Proceed with selected arrays ──",
    })
    table.insert(items, {
      id = "__all__",
      type = "all",
      label = "── ⟳ Select All / None ──",
    })

    vim.ui.select(items, {
      prompt = "Select data sources / swimlanes to plot:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if not choice then
        return callback(nil)
      end

      if choice.type == "done" then
        local result = {}
        for _, k in ipairs(array_keys) do
          if selected[k] then
            table.insert(result, k)
          end
        end
        if #result == 0 then
          vim.notify("json-tsdb-plot: Please select at least one array", vim.log.levels.WARN)
          return show_menu()
        end
        return callback(result)
      elseif choice.type == "all" then
        local any_unselected = false
        for _, k in ipairs(array_keys) do
          if not selected[k] then any_unselected = true break end
        end
        for _, k in ipairs(array_keys) do
          selected[k] = any_unselected
        end
        return show_menu()
      elseif choice.type == "toggle" then
        selected[choice.id] = not selected[choice.id]
        return show_menu()
      end
    end)
  end

  show_menu()
end

--- Select fields with saved schema check
--- @param fields string[] Available field names
--- @param opts { array_key: string|nil, file_path: string|nil }|nil
--- @param callback fun(selections: table|nil)
function M.select_fields(fields, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  local schema_store = require("json_tsdb_plot.schema_store")
  local saved_schemas = schema_store.get_matching_schemas(fields, opts.array_key, opts.file_path)

  if #saved_schemas > 0 then
    local menu_items = {}
    for _, s in ipairs(saved_schemas) do
      table.insert(menu_items, {
        label = "Use saved: " .. format_schema_label(s),
        schema = s,
      })
    end
    table.insert(menu_items, {
      label = "── Configure new field mapping ──",
      schema = nil,
    })

    local prompt_text = opts.array_key and ("Saved schema for [" .. opts.array_key .. "]:") or "Saved schema found:"
    vim.ui.select(menu_items, {
      prompt = prompt_text,
      format_item = function(item)
        return item.label
      end,
    }, function(selected)
      if not selected then
        return callback(nil)
      end

      if selected.schema then
        schema_store.save_schema({
          name = selected.schema.name,
          fields = fields,
          array_key = opts.array_key,
          file_path = opts.file_path,
          selections = selected.schema.selections,
        })
        return callback(selected.schema.selections)
      end

      M.prompt_fields_wizard(fields, opts, callback)
    end)
    return
  end

  M.prompt_fields_wizard(fields, opts, callback)
end

--- Step-by-step wizard to choose fields
function M.prompt_fields_wizard(fields, opts, callback)
  local schema_store = require("json_tsdb_plot.schema_store")
  local selections = {}
  local p_prefix = (opts.array_key and opts.array_key ~= "") and ("[" .. opts.array_key .. "] ") or ""

  vim.ui.select(fields, { prompt = p_prefix .. "Select LABEL field:" }, function(label)
    if not label then return callback(nil) end
    selections.label = label

    vim.ui.select(fields, { prompt = p_prefix .. "Select START DATE field:" }, function(start_date)
      if not start_date then return callback(nil) end
      selections.start = start_date

      local end_opts = vim.deepcopy(fields)
      table.insert(end_opts, 1, "── Use duration field instead ──")

      vim.ui.select(end_opts, { prompt = p_prefix .. "Select END DATE field:" }, function(end_date)
        if not end_date then return callback(nil) end

        local function proceed_with_category()
          local cat_opts = vim.deepcopy(fields)
          table.insert(cat_opts, 1, "── None (skip) ──")

          vim.ui.select(cat_opts, { prompt = p_prefix .. "Select CATEGORY field:" }, function(category)
            if not category then return callback(nil) end
            if category ~= "── None (skip) ──" then
              selections.category = category
            end

            schema_store.save_schema({
              fields = fields,
              array_key = opts.array_key,
              file_path = opts.file_path,
              selections = selections,
            })

            callback(selections)
          end)
        end

        if end_date == "── Use duration field instead ──" then
          vim.ui.select(fields, { prompt = p_prefix .. "Select DURATION field:" }, function(duration)
            if not duration then return callback(nil) end
            selections.duration = duration
            proceed_with_category()
          end)
        else
          selections.end_date = end_date
          proceed_with_category()
        end
      end)
    end)
  end)
end

function M.filter_date_range(callback)
  vim.ui.input({ prompt = "Start Date (YYYY-MM-DD) or empty:" }, function(start_str)
    if start_str == nil then return end
    vim.ui.input({ prompt = "End Date (YYYY-MM-DD) or empty:" }, function(end_str)
      if end_str == nil then return end
      callback(start_str, end_str)
    end)
  end)
end

function M.filter_category(categories, callback)
  vim.ui.select(categories, { prompt = "Filter by category:" }, function(category)
    if not category then return end
    callback(category)
  end)
end

return M
