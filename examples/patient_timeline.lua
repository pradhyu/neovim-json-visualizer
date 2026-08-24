local tl = require("json_plot.builder")

tl.title("Patient Timeline — Maria Garcia (MBR-2024-44821)")

tl.plot("medicalHistory")
  :label(function(e)
    return e.facility .. " — " .. e.diagnosis
  end)
  :start("admitDate")
  :end_date("dischargeDate")
  :tag("Admit")
  :color("#e06c75")

tl.plot("pharmacyHistory")
  :label(function(e)
    return e.drugName .. " (" .. e.daysSupply .. "d)"
  end)
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Rx Fill")
  :color("#98c379")

tl.plot("currentPrescription")
  :label(function(e)
    return e.drugName .. " [" .. e.status .. "]"
  end)
  :start("startDate")
  :end_computed("startDate", "daysSupply")
  :tag("Active Rx")
  :color("#61afef")

tl.sort("start")
tl.date_format("%Y-%m-%d")
