data_dir = "/tmp/"

telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = true
}

domain = "yourdomain.consul"


log_level = "TRACE"
datacenter = "dc1"
server = true
bootstrap_expect = 1
ui = true
ports {
  grpc = 8502
}


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
        bind_address = "0.0.0.0"
        expose = { checks = true }
      }
    }
  ]
}
