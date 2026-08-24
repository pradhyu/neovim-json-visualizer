local tl = require("json_plot.builder")

tl.title("Medicare Claims & Prior Auth — Maria Garcia (1EG4-TE5-MK72)")

-- 1. Inpatient & Outpatient Claims (CMS Part A / Part B)
tl.plot("medicalHistory")
  :label(function(e)
    return e.facility .. " — " .. e.diagnosis
  end)
  :start("admitDate")
  :end_date("dischargeDate")
  :tag("Claim")
  :color("#e06c75")

-- 2. CMS Prior Authorization & Service Requests (Da Vinci PAS / CRD)
tl.plot("priorAuthorizations")
  :label(function(e)
    return e.serviceType .. " [" .. e.decision .. "]"
  end)
  :start("requestDate")
  :end_computed("requestDate", "authorizedDays")
  :tag("Prior Auth")
  :color("#98c379")

-- 3. Durable Medical Equipment (CMS DMEPOS Rentals & Supplies)
tl.plot("durableMedicalEquipment")
  :label(function(e)
    return e.itemDescription .. " (" .. e.supplier .. ")"
  end)
  :start("startDate")
  :end_computed("startDate", "coverageDays")
  :tag("DME")
  :color("#61afef")

tl.sort("start")
tl.date_format("%Y-%m-%d")
