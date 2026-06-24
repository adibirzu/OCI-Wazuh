.PHONY: bootstrap lint validate e2e cost up down plan cap-preflight goad-discover goad-up goad-down goad-validate log-analytics-bridge wazuh-log-analytics wazuh-content opensearch-oci validate-opensearch-oci simulate-detections validate-real-oci-logs

bootstrap:
	bash scripts/bootstrap.sh

cap-preflight:
	bash scripts/cap-preflight.sh

goad-discover:
	bash scripts/goad-discover.sh

goad-up:
	bash scripts/goad-wazuh.sh install

goad-down:
	bash scripts/goad-wazuh.sh cleanup

goad-validate:
	bash scripts/goad-wazuh.sh validate

log-analytics-bridge:
	bash scripts/log-analytics-bridge.sh

wazuh-log-analytics:
	bash scripts/configure-wazuh-log-analytics.sh

wazuh-content:
	bash scripts/deploy-wazuh-content.sh

opensearch-oci:
	bash scripts/configure-opensearch-oci.sh

validate-opensearch-oci:
	bash scripts/validate-opensearch-oci.sh

simulate-detections:
	bash scripts/simulate-detections.sh

validate-real-oci-logs:
	bash scripts/validate-real-oci-logs.sh

lint:
	terraform -chdir=terraform fmt -check -recursive
	python3 -m py_compile wazuh/consumer/oci_log_consumer.py

plan:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform plan

up: cost
	bash scripts/cap-up.sh

down: goad-down
	terraform -chdir=terraform destroy

validate:
	bash scripts/e2e.sh --dry-run

e2e:
	bash scripts/e2e.sh

cost:
	bash scripts/cost-estimate.sh
