output "stream_id" {
  value = oci_streaming_stream.this.id
}

output "stream_pool_id" {
  value = oci_streaming_stream_pool.this.id
}

output "messages_endpoint" {
  value = oci_streaming_stream.this.messages_endpoint
}
