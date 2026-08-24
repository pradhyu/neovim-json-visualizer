-- tests/builder_spec.lua
-- Tests for json_tsdb_plot.builder module

describe("builder", function()
  local builder

  before_each(function()
    -- Hot-reload builder for clean state
    package.loaded["json_tsdb_plot.builder"] = nil
    builder = require("json_tsdb_plot.builder")
    builder.reset()
  end)

  describe("plot", function()
    it("creates a plot definition", function()
      local p = builder.plot("medicalHistory")
      assert.is_not_nil(p)
      assert.are.equal("medicalHistory", p._source_path)
    end)

    it("registers the plot in the collection", function()
      builder.plot("a")
      builder.plot("b")
      assert.are.equal(2, #builder.get_plots())
    end)
  end)

  describe("fluent chaining", function()
    it("chains all methods and returns self", function()
      local p = builder.plot("source")
        :label("name")
        :sublabel("detail")
        :start("startDate")
        :end_date("endDate")
        :tag("MyTag")
        :color("#ff0000")

      assert.are.equal("name", p._label)
      assert.are.equal("detail", p._sublabel)
      assert.are.equal("startDate", p._start)
      assert.are.equal("endDate", p._end_date)
      assert.are.equal("MyTag", p._tag)
      assert.are.equal("#ff0000", p._color)
    end)

    it("supports end_computed", function()
      local p = builder.plot("rx")
        :start("fillDate")
        :end_computed("fillDate", "daysSupply")

      assert.are.equal("fillDate", p._end_computed_start)
      assert.are.equal("daysSupply", p._end_computed_duration)
    end)

    it("supports end_computed_expr with function", function()
      local fn = function(e) return e.weeks * 7 end
      local p = builder.plot("therapy")
        :start("sessionDate")
        :end_computed_expr(fn)

      assert.are.equal(fn, p._end_computed_expr)
    end)

    it("supports label as function", function()
      local fn = function(e) return e.name .. " (" .. e.id .. ")" end
      local p = builder.plot("items"):label(fn)
      assert.are.equal(fn, p._label)
    end)

    it("supports filter", function()
      local fn = function(e) return e.active end
      local p = builder.plot("items"):filter(fn)
      assert.are.equal(fn, p._filter)
    end)
  end)

  describe("global settings", function()
    it("sets title", function()
      builder.title("My Chart")
      assert.are.equal("My Chart", builder.get_global().title)
    end)

    it("sets date_format", function()
      builder.date_format("%m/%d/%Y")
      assert.are.equal("%m/%d/%Y", builder.get_global().date_format)
    end)

    it("sets sort", function()
      builder.sort("end")
      assert.are.equal("end", builder.get_global().sort)
    end)
  end)

  describe("reset", function()
    it("clears all plots and globals", function()
      builder.plot("a")
      builder.plot("b")
      builder.title("test")
      builder.reset()

      assert.are.equal(0, #builder.get_plots())
      assert.is_nil(builder.get_global().title)
    end)
  end)
end)
