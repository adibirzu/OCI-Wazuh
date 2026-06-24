# OCI Wazuh Dashboard Views

Use Wazuh Dashboard against `wazuh-alerts-*`.

## Data View

- Name: `OCI Wazuh Alerts`
- Index pattern: `wazuh-alerts-*`
- Time field: `timestamp`

## Saved Searches

### OCI Audit Detections

KQL:

```text
rule.id >= 100000 and rule.id <= 100099
```

Columns:

- `timestamp`
- `rule.id`
- `rule.description`
- `agent.name`
- `data.eventType`
- `data.principalName`
- `data.sourceIp`
- `data.compartmentId`

### VCN Flow Detections

KQL:

```text
rule.id >= 100100 and rule.id <= 100199
```

Columns:

- `timestamp`
- `rule.id`
- `rule.description`
- `data.srcaddr`
- `data.dstaddr`
- `data.srcport`
- `data.dstport`
- `data.action`
- `data.bytes`
- `data.packets`

### Linux FIM and SCA

KQL:

```text
rule.groups: syscheck or rule.groups: sca
```

Columns:

- `timestamp`
- `agent.name`
- `rule.id`
- `rule.description`
- `syscheck.path`
- `rule.mitre.id`

### GOAD Windows and Sysmon

KQL:

```text
agent.name: (braavos or castelblack or kingslanding or meereen or winterfell) or rule.groups: windows
```

Columns:

- `timestamp`
- `agent.name`
- `rule.id`
- `rule.description`
- `data.win.system.eventID`
- `data.win.system.channel`
- `data.win.eventdata.image`
- `data.win.eventdata.commandLine`

## Dashboard Panels

Create these panels from the saved searches:

| Panel | Type | Source |
|---|---|---|
| OCI audit alerts over time | Date histogram | OCI Audit Detections |
| VCN rejected traffic by destination port | Bar | VCN Flow Detections |
| Top Linux FIM paths | Data table | Linux FIM and SCA |
| GOAD Sysmon event IDs | Bar | GOAD Windows and Sysmon |
| MITRE technique count | Data table | all alerts, split by `rule.mitre.id` |

## Drilldown Flow

1. Start with `rule.level >= 5`.
2. Filter to the agent or cloud source.
3. Pivot on `rule.mitre.id`.
4. Open the raw alert and confirm parsed `data.*` fields for OCI Audit or VCN Flow.
