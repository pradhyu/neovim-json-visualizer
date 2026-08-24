local tl = require("json_tsdb_plot.builder")

tl.title("⚠ Opioid Monitoring — Robert Chen (MBR-2024-98321)")

tl.plot("opioidPrescriptions")
  :label(function(e)
    return e.drugName .. " [MME:" .. e.mme .. "] — " .. e.prescriber
  end)
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Opioid")
  :color("#e06c75")

tl.plot("benzodiazepines")
  :label(function(e)
    return e.drugName .. " — " .. e.prescriber
  end)
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Benzo")
  :color("#d19a66")

tl.plot("naloxonePrescription")
  :label("drugName")
  :start("fillDate")
  :end_computed("fillDate", "daysSupply")
  :tag("Naloxone")
  :color("#56b6c2")

tl.sort("start")
