# Teaching Notes

- The learner wants an enterprise-ready demo, not a toy walkthrough.
- Favor modules that connect telemetry to posture decisions: identify signal, normalize fields, correlate, detect, then remediate.
- Keep committed material public-safe. Use placeholders for tenant values and link to local runbooks instead of embedding live access details.
- Start every Log Analytics dashboard lesson with source inventory because source names and field availability can differ by tenancy.
- Wazuh and Log Analytics should be taught as complementary systems: Wazuh for endpoint/SIEM detections and agent posture, Log Analytics for cross-source OCI-scale correlation and dashboards.
