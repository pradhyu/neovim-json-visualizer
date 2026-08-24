local tl = require("json_tsdb_plot.builder")

tl.title("Care Coordination — Dorothy Williams (MBR-2024-55102)")

tl.plot("snfStays")
  :label(function(e)
    return e.facility .. " — " .. e.reason
  end)
  :start("admitDate")
  :end_date("dischargeDate")
  :tag("SNF")
  :color("#e06c75")

tl.plot("homeHealth")
  :label(function(e)
    return e.agency .. " (" .. e.visitType .. ")"
  end)
  :start("startDate")
  :end_date("endDate")
  :tag("Home Health")
  :color("#c678dd")

tl.plot("therapySessions")
  :label(function(e)
    return e.type .. " — " .. e.provider .. " (" .. e.frequency .. ")"
  end)
  :start("sessionDate")
  :end_computed_expr(function(e)
    return e.durationWeeks * 7
  end)
  :tag("Therapy")
  :color("#61afef")

tl.plot("prescriptions")
  :label(function(e)
    return e.drugName .. " — " .. e.reason
  end)
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Rx")
  :color("#98c379")

tl.sort("start")
