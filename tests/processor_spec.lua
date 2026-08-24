-- tests/processor_spec.lua
-- Tests for json_plot.processor module

describe("processor", function()
  local processor = require("json_plot.processor")
  local builder

  before_each(function()
    package.loaded["json_plot.builder"] = nil
    builder = require("json_plot.builder")
    builder.reset()
  end)

  describe("process", function()
    it("processes entries with explicit end dates", function()
      local data = {
        admissions = {
          { facility = "Hospital A", admitDate = "2024-01-15", dischargeDate = "2024-01-22" },
          { facility = "Hospital B", admitDate = "2024-03-05", dischargeDate = "2024-03-05" },
        },
      }

      builder.plot("admissions")
        :label("facility")
        :start("admitDate")
        :end_date("dischargeDate")
        :tag("Admit")
        :color("#e06c75")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(2, #entries)
      assert.are.equal("[Admit] Hospital A", entries[1].label)
      assert.are.equal("Admit", entries[1].tag)
      assert.are.equal("#e06c75", entries[1].color)
      assert.is_true(entries[1].end_ts > entries[1].start_ts)
    end)

    it("processes entries with computed end dates", function()
      local data = {
        prescriptions = {
          { drugName = "Amoxicillin", fillDate = "2024-01-16", daysSupply = 10 },
        },
      }

      builder.plot("prescriptions")
        :label("drugName")
        :start("fillDate")
        :end_computed("fillDate", "daysSupply")
        :tag("Rx")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(1, #entries)
      -- 10 days = 10 * 86400 seconds
      local expected_duration = 10 * 86400
      local actual_duration = entries[1].end_ts - entries[1].start_ts
      assert.are.equal(expected_duration, actual_duration)
    end)

    it("processes entries with end_computed_expr", function()
      local data = {
        therapy = {
          { type = "PT", sessionDate = "2024-05-21", durationWeeks = 8 },
        },
      }

      builder.plot("therapy")
        :label("type")
        :start("sessionDate")
        :end_computed_expr(function(e) return e.durationWeeks * 7 end)
        :tag("Therapy")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(1, #entries)
      local expected_duration = 8 * 7 * 86400
      local actual_duration = entries[1].end_ts - entries[1].start_ts
      assert.are.equal(expected_duration, actual_duration)
    end)

    it("handles function-based labels", function()
      local data = {
        items = {
          { name = "Test", count = 42 },
        },
      }

      builder.plot("items")
        :label(function(e) return e.name .. " (" .. e.count .. ")" end)
        :start("date") -- will fail to parse but that's ok

      -- This will produce 0 entries because "date" field doesn't exist
      -- but let's test with a proper date
      data.items[1].date = "2024-01-01"
      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(1, #entries)
      assert.is_true(entries[1].label:find("Test (42)", 1, true) ~= nil)
    end)

    it("applies filter predicate", function()
      local data = {
        items = {
          { name = "A", date = "2024-01-01", active = true },
          { name = "B", date = "2024-02-01", active = false },
          { name = "C", date = "2024-03-01", active = true },
        },
      }

      builder.plot("items")
        :label("name")
        :start("date")
        :filter(function(e) return e.active end)

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(2, #entries)
    end)

    it("ensures minimum 1 day width for same-day events", function()
      local data = {
        visits = {
          { name = "Visit", visitDate = "2024-03-05", endDate = "2024-03-05" },
        },
      }

      builder.plot("visits")
        :label("name")
        :start("visitDate")
        :end_date("endDate")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(1, #entries)
      assert.is_true(entries[1].end_ts > entries[1].start_ts)
      assert.are.equal(86400, entries[1].end_ts - entries[1].start_ts)
    end)

    it("resolves dot-separated source paths", function()
      local data = {
        patient = {
          records = {
            { name = "Record 1", date = "2024-01-01" },
          },
        },
      }

      builder.plot("patient.records")
        :label("name")
        :start("date")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(1, #entries)
    end)

    it("handles missing source path gracefully", function()
      local data = { items = {} }

      builder.plot("nonexistent")
        :label("name")
        :start("date")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(0, #entries)
    end)

    it("processes multiple plot definitions", function()
      local data = {
        admissions = {
          { facility = "Hospital", admitDate = "2024-01-15", dischargeDate = "2024-01-22" },
        },
        prescriptions = {
          { drug = "Med A", fillDate = "2024-01-16", daysSupply = 10 },
          { drug = "Med B", fillDate = "2024-02-01", daysSupply = 30 },
        },
      }

      builder.plot("admissions")
        :label("facility"):start("admitDate"):end_date("dischargeDate"):tag("Admit")

      builder.plot("prescriptions")
        :label("drug"):start("fillDate"):end_computed("fillDate", "daysSupply"):tag("Rx")

      local entries = processor.process(data, builder.get_plots(), builder.get_global())
      assert.are.equal(3, #entries)
    end)
  end)
end)
