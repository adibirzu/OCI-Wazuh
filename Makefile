.PHONY: bootstrap lint validate e2e cost up down plan cap-preflight goad-discover log-analytics-bridge wazuh-log-analytics wazuh-content simulate-detections

bootstrap:
	bash scripts/bootstrap.sh

cap-preflight:
	bash scripts/cap-preflight.sh

goad-discover:
	bash scripts/goad-discover.sh

log-analytics-bridge:
	bash scripts/log-analytics-bridge.sh

wazuh-log-analytics:
	bash scripts/configure-wazuh-log-analytics.sh

wazuh-content:
	bash scripts/deploy-wazuh-content.sh

simulate-detections:
	bash scripts/simulate-detections.sh

lint:
	terraform -chdir=terraform fmt -check -recursive
	python3 -m py_compile wazuh/consumer/oci_log_consumer.py

plan:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform plan

up: cost
	bash scripts/cap-up.sh

down:
	terraform -chdir=terraform destroy

validate:
	bash scripts/e2e.sh --dry-run

e2e:
	bash scripts/e2e.sh

cost:
	bash scripts/cost-estimate.sh
