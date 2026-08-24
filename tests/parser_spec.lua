-- tests/parser_spec.lua
-- Tests for json_plot.parser module

describe("parser", function()
  local parser = require("json_plot.parser")

  describe("parse_date", function()
    it("parses ISO 8601 date (YYYY-MM-DD)", function()
      local ts = parser.parse_date("2024-01-15")
      assert.is_not_nil(ts)
      assert.is_true(ts > 0)
      local date = os.date("*t", ts)
      assert.are.equal(2024, date.year)
      assert.are.equal(1, date.month)
      assert.are.equal(15, date.day)
    end)

    it("parses ISO 8601 datetime (YYYY-MM-DDTHH:MM:SS)", function()
      local ts = parser.parse_date("2024-06-15T14:30:00")
      assert.is_not_nil(ts)
      local date = os.date("*t", ts)
      assert.are.equal(2024, date.year)
      assert.are.equal(6, date.month)
      assert.are.equal(15, date.day)
      assert.are.equal(14, date.hour)
      assert.are.equal(30, date.min)
    end)

    it("parses US format (MM/DD/YYYY)", function()
      local ts = parser.parse_date("03/05/2024")
      assert.is_not_nil(ts)
      local date = os.date("*t", ts)
      assert.are.equal(2024, date.year)
      assert.are.equal(3, date.month)
      assert.are.equal(5, date.day)
    end)

    it("returns nil for invalid input", function()
      assert.is_nil(parser.parse_date(nil))
      assert.is_nil(parser.parse_date(""))
      assert.is_nil(parser.parse_date("not-a-date"))
      assert.is_nil(parser.parse_date(12345))
    end)
  end)

  describe("detect_fields", function()
    it("detects unique field names from an array", function()
      local data = {
        { name = "Alice", age = 30 },
        { name = "Bob", city = "NYC" },
      }
      local fields = parser.detect_fields(data)
      assert.are.equal(3, #fields) -- age, city, name (sorted)
      assert.are.equal("age", fields[1])
      assert.are.equal("city", fields[2])
      assert.are.equal("name", fields[3])
    end)

    it("returns empty table for non-table input", function()
      assert.are.same({}, parser.detect_fields(nil))
      assert.are.same({}, parser.detect_fields("string"))
    end)
  end)

  describe("resolve_path", function()
    it("resolves simple key", function()
      local data = { items = { 1, 2, 3 } }
      assert.are.same({ 1, 2, 3 }, parser.resolve_path(data, "items"))
    end)

    it("resolves dot-separated path", function()
      local data = { patient = { history = { "a", "b" } } }
      assert.are.same({ "a", "b" }, parser.resolve_path(data, "patient.history"))
    end)

    it("returns nil for missing path", function()
      local data = { a = 1 }
      assert.is_nil(parser.resolve_path(data, "b.c"))
    end)

    it("returns data for empty path", function()
      local data = { a = 1 }
      assert.are.same(data, parser.resolve_path(data, ""))
    end)
  end)

  describe("read_file", function()
    it("reads and parses a JSON fixture", function()
      local fixture = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
        .. "/fixtures/patient_timeline.json"
      local data, err = parser.read_file(fixture)
      assert.is_nil(err)
      assert.is_not_nil(data)
      assert.is_not_nil(data.medicalHistory)
      assert.is_true(#data.medicalHistory > 0)
    end)

    it("returns error for missing file", function()
      local data, err = parser.read_file("/nonexistent/file.json")
      assert.is_nil(data)
      assert.is_not_nil(err)
    end)
  end)
end)
