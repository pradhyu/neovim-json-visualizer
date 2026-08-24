--- Fluent API builder with PlotDef class for json-plot.nvim
local M = {}

M._plots = {}
M._global = {}

--- PlotDef Class
local PlotDef = {}
PlotDef.__index = PlotDef

function PlotDef:new(source_path)
  local obj = {
    _source_path = source_path,
    _label = nil,
    _sublabel = nil,
    _start = nil,
    _end_date = nil,
    _end_computed_start = nil,
    _end_computed_duration = nil,
    _end_computed_expr = nil,
    _tag = nil,
    _category_field = nil,
    _group = nil,
    _color = nil,
    _filter = nil
  }
  setmetatable(obj, PlotDef)
  return obj
end

function PlotDef:label(field)
  self._label = field
  return self
end

function PlotDef:sublabel(field)
  self._sublabel = field
  return self
end

function PlotDef:start(field)
  self._start = field
  return self
end

function PlotDef:end_date(field)
  self._end_date = field
  return self
end

function PlotDef:end_computed(start_field, duration_field)
  self._end_computed_start = start_field
  self._end_computed_duration = duration_field
  return self
end

function PlotDef:end_computed_expr(fn)
  self._end_computed_expr = fn
  return self
end

function PlotDef:tag(name)
  self._tag = name
  return self
end

function PlotDef:category_field(field)
  self._category_field = field
  return self
end

function PlotDef:group(name)
  self._group = name
  return self
end

function PlotDef:swimlane(name)
  self._group = name
  return self
end

function PlotDef:color(hex)
  self._color = hex
  return self
end

function PlotDef:filter(fn)
  self._filter = fn
  return self
end

--- Builder Module Functions

--- Create and register a new PlotDef
function M.plot(source_path)
  local p = PlotDef:new(source_path)
  table.insert(M._plots, p)
  return p
end

--- Set chart title
function M.title(t)
  M._global.title = t
  return M
end

--- Set date format
function M.date_format(fmt)
  M._global.date_format = fmt
  return M
end

--- Set default sort
function M.sort(order)
  M._global.sort = order
  return M
end

--- Clear all plots and reset globals
function M.reset()
  M._plots = {}
  M._global = {}
  return M
end

--- Return array of PlotDef objects
function M.get_plots()
  return M._plots
end

--- Return global settings table
function M.get_global()
  return M._global
end

return M
