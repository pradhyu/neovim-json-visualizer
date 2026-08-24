local tl = require("json_plot.builder")

tl.title("CMS Prior Authorization & Utilization Review — Robert Chen (3AK9-WL4-TR81)")

-- 1. Inpatient Pre-Certifications & Surgical Authorizations (Da Vinci PAS)
tl.plot("inpatientPrecertifications")
  :label(function(e)
    return e.procedure .. " (" .. e.facility .. ")"
  end)
  :start("requestDate")
  :end_computed("requestDate", "authorizedDays")
  :tag("Inpatient Pre-Cert")
  :color("#e06c75")

-- 2. Advanced Diagnostic Imaging Requests (Da Vinci CRD)
tl.plot("advancedImagingRequests")
  :label(function(e)
    return e.serviceName .. " — " .. e.orderingProvider
  end)
  :start("requestDate")
  :end_computed("requestDate", "authorizedDays")
  :tag("Imaging Auth")
  :color("#d19a66")

-- 3. DME & Orthotic Supplies Requests
tl.plot("dmeSuppliesRequests")
  :label(function(e)
    return e.serviceName .. " (" .. e.supplier .. ")"
  end)
  :start("requestDate")
  :end_computed("requestDate", "authorizedDays")
  :tag("DME Auth")
  :color("#56b6c2")

tl.sort("start")
