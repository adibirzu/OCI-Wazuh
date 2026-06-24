# Plan

## RPEQ Milestones

M1 bootstrap/discovery is implemented by `make bootstrap`.

M2-M10 are represented by Terraform modules, Ansible playbooks, Wazuh packs, scripts, and KBs in this repo. Each milestone will harden the corresponding module and gate until green against a real tenancy.

## Current Gate

Run:

```bash
make bootstrap
```
