resource "oci_streaming_stream_pool" "this" {
  compartment_id = var.compartment_id
  name           = "${var.project_name}-stream-pool"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_streaming_stream" "this" {
  name               = "${var.project_name}-oci-logs"
  partitions         = 1
  retention_in_hours = 24
  stream_pool_id     = oci_streaming_stream_pool.this.id
  freeform_tags      = var.freeform_tags
  defined_tags       = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
