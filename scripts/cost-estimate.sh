#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Estimated monthly cost drivers:
- Wazuh AIO: VM.Standard.E5.Flex, 4 OCPU, 16 GB memory, 200 GB block volume
- Bastion: small flexible VM
- 2 Linux agents: small flexible VMs
- Optional Windows/GOAD: disabled unless selected or GOAD absent and requested
- Streaming: 1 partition, 24h retention
- Object Storage fallback: request/storage dependent
- Log Analytics bridge: ingest-volume dependent

Use OCI Cost Estimator or tenancy-specific price list before apply.
EOF
