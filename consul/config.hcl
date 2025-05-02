data_dir = "/tmp/"

telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = true
}

log_level = "TRACE"
datacenter = "dc1"
server = true
bootstrap_expect = 1
ui = true

ports {
  grpc = 8502
}


advertise_addr = "172.24.0.2"

bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"


connect {
  enabled = true
}

enable_central_service_config = false


config_entries {
  bootstrap = [
    {
      kind   = "proxy-defaults"
      name   = "global"


      config {
      envoy_dns_discovery_type = "STRICT_DNS"
      bind_address = "0.0.0.0"
        expose = { checks = true }
      }
    }
  ]
}
