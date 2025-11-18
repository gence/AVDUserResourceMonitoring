# AVD User Resource Monitoring

User-level CPU and Memory visibility across an entire Azure Virtual Desktop (AVD) deployment.  
This repository delivers:
- Collection of per-user / per-process resource usage on AVD session hosts (data sent to Log Analytics).
- An Azure Workbook for interactive visualization (users, processes, hosts, trends).
- Reusable Kusto (KQL) queries.

> Focus: Turn raw per-session host metrics into actionable user & process insights for sizing, troubleshooting, and capacity planning.

## Repository Structure (current)
```
Dashboard/                    (Azure workbook and dashboard assets and deployment scripts)
DeploymentScripts/            (scripts for deploying collection)
ProvisionLogAnalytics/        (workspace / table provisioning assets)
SessionWatchScripts/          (session & process watch scripts)
README.md
```

## Dashboard Components
- Workbook Definition: `Dashboard/azure-workbook-avd-resource-usage.json`
- Deployment Script: `Dashboard/deploy-workbook.ps1`
- Deployment Instructions: `Dashboard/WORKBOOK-DEPLOYMENT.md`
- Query Library: `Dashboard/kusto-queries.kql` (includes sample user / process / host analytics)

## Core Workflow (High Level)
1. Session hosts run monitoring scripts (see `SessionWatchScripts/`) to capture:
   - User principal
   - Process name / PID
   - CPU (%) and Memory (Working Set / Private)
   - Host / pool context
   - Timestamp
2. Data is sent to a Log Analytics workspace (custom tables).
3. Azure Workbook (JSON in `Dashboard/azure-workbook-avd-resource-usage.json`) queries and visualizes:
   - Top users (CPU / Memory)
   - Top processes
   - Host density & saturation (roadmap)
   - Time series trends (roadmap)

## Workbook Deployment
The `Dashboard/deploy-workbook.ps1` script automates publishing the workbook using the JSON file.

## Queries
Use the curated examples in `Dashboard/kusto-queries.kql` directly inside the Log Analytics query interface or clone for custom alert rules and workbook tiles.

## Use Cases
- Identify resource-heavy users impacting multi-session density.
- Spot runaway or memory-leaking processes.
- Right-size AVD host pool VM SKUs and scaling schedules.
- Support incident investigation (spikes correlated to user / process).

## Contributing
1. Fork the repo.
2. Add or refine scripts / queries.
3. Submit a pull request with clear description referencing modified files.

## Troubleshooting
- Ensure Storage Account is available publicly
