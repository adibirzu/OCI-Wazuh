.PHONY: bootstrap lint test shell-test schema-validate validate e2e m11-gate cost up down plan cap-preflight goad-discover goad-up goad-down goad-validate log-analytics-bridge log-analytics-freshness wazuh-log-analytics wazuh-content opensearch-oci validate-opensearch-oci validate-management-dashboard validate-windows validate-bootstrap simulate-detections validate-real-oci-logs auth-screenshots teach-validate dashboards-validate public-pages orm-package security-scan

bootstrap:
	bash scripts/bootstrap.sh

test:
	pytest

shell-test:
	bats tests/shell

schema-validate:
	python3 scripts/validate-orm-schema.py

security-scan:
	bash scripts/redact-gate.sh

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

log-analytics-freshness:
	bash scripts/validate-log-analytics-freshness.sh

wazuh-log-analytics:
	bash scripts/configure-wazuh-log-analytics.sh

wazuh-content:
	bash scripts/deploy-wazuh-content.sh

opensearch-oci:
	bash scripts/configure-opensearch-oci.sh

validate-opensearch-oci:
	bash scripts/validate-opensearch-oci.sh

validate-management-dashboard:
	bash scripts/validate-management-dashboard.sh

validate-windows:
	bash scripts/validate-windows-mode.sh

validate-bootstrap:
	bash scripts/validate-bootstrap-status.sh

simulate-detections:
	bash scripts/simulate-detections.sh

validate-real-oci-logs:
	bash scripts/validate-real-oci-logs.sh

auth-screenshots:
	bash scripts/capture-authenticated-screenshots.sh

teach-validate:
	bash scripts/validate-teaching-assets.sh

dashboards-validate:
	python3 scripts/validate-dashboard-assets.py

public-pages:
	python3 scripts/validate-public-pages.py

orm-package:
	bash scripts/package-orm-stack.sh

lint:
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform init -backend=false -input=false
	terraform -chdir=terraform validate
	python3 -m compileall -q m11 scripts wazuh/consumer
	shellcheck -e SC1091,SC2016 scripts/*.sh

plan:
	terraform -chdir=terraform init -backend=false -input=false
	terraform -chdir=terraform plan

up: cost
	bash scripts/cap-up.sh

down:
	bash scripts/down.sh

validate:
	bash scripts/e2e.sh --dry-run

e2e:
	bash scripts/e2e.sh

m11-gate:
	python3 scripts/m11-gate.py

cost:
	bash scripts/cost-estimate.sh
