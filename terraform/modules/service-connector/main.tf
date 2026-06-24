# SCH resources are implemented in M6/M7 after log source IDs are known.
# This module owns the contract and variables for selectable ingestion modes.
locals {
  selected_mode = var.ingestion_mode
}
