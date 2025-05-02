#!/bin/bash

# Strict mode
set -euo pipefail

# === Configuration (from Environment Variables) ===
# See Dockerfile ENV section for descriptions and defaults

# Consul CLI Address (must reach server API)
CONSUL_CLI_ADDR="${CONSUL_HTTP_ADDR}"
# Address 'consul connect envoy' uses for bootstrap (if needed)
CONNECT_BOOTSTRAP_ADDR="${CONNECT_BOOTSTRAP_ADDR}"

# Script Behavior
_LOG_LEVEL="${ENTRYPOINT_LOG_LEVEL:-INFO}"
_WAIT_FOR_CONSUL="${WAIT_FOR_CONSUL:-true}"
_CONSUL_WAIT_TIMEOUT="${CONSUL_WAIT_TIMEOUT:-60s}"
_CONSUL_WAIT_INTERVAL="${CONSUL_WAIT_INTERVAL:-2s}"

# Config Paths (base directories)
_CONSUL_CONFIG_DIR="${CONSUL_CONFIG_DIR:-/etc/consul/config}"
_CONSUL_CENTRAL_CONFIG_DIR="${CONSUL_CENTRAL_CONFIG_DIR:-/etc/consul/central-config}"

# Specific Config Files (relative to base dirs or absolute)
_SERVICE_CONFIG_FILE="${SERVICE_CONFIG_FILE:-}" # Filename, e.g., "my-service.json"
_CENTRAL_CONFIG_FILES="${CENTRAL_CONFIG_FILES:-}" # Semicolon-separated list

# Command to execute (passed from Dockerfile CMD or docker-compose command:)
MAIN_COMMAND=("$@")

# === Logging ===
# Usage: log "INFO" "My message"
log() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # ISO 8601 UTC

  # Only log if level is >= configured level
  case "$_LOG_LEVEL" in
    DEBUG) ;; # Always log debug if level is DEBUG
    INFO) [[ "$level" =~ ^(INFO|WARN|ERROR)$ ]] || return 0 ;;
    WARN) [[ "$level" =~ ^(WARN|ERROR)$ ]] || return 0 ;;
    ERROR) [[ "$level" == "ERROR" ]] || return 0 ;;
    *) ;; # Default: log INFO, WARN, ERROR
  esac

  echo "${timestamp} [${level}] [Entrypoint] ${msg}" >&2 # Log to stderr
}

# === Utility Functions ===

# Parse duration string (e.g., "60s", "2m") into seconds
parse_duration() {
  local duration="$1"
  local num part
  num=$(echo "$duration" | sed 's/[^0-9]*//g')
  part=$(echo "$duration" | sed 's/[0-9]*//g')
  case "$part" in
    s|S|"") echo "$num" ;;
    m|M) echo "$((num * 60))" ;;
    h|H) echo "$((num * 3600))" ;;
    *) log "ERROR" "Invalid duration format: $duration"; exit 1 ;;
  esac
}

# Check if Consul server is available and has a leader
check_consul_ready() {
    # Using 'list-peers' is generally more reliable than checking /v1/status/leader
    if consul operator raft list-peers -http-addr="${CONSUL_CLI_ADDR}" > /dev/null 2>&1; then
        return 0 # Success
    else
        return 1 # Failure
    fi
}

# Wait loop for Consul
wait_for_consul() {
  if [[ "${_WAIT_FOR_CONSUL,,}" != "true" ]]; then
      log "INFO" "Skipping wait for Consul server."
      return 0
  fi

  log "INFO" "Waiting up to ${_CONSUL_WAIT_TIMEOUT} for Consul server at ${CONSUL_CLI_ADDR}..."
  local end_time=$(( $(date +%s) + $(parse_duration "$_CONSUL_WAIT_TIMEOUT") ))
  local interval_sec=$(( $(parse_duration "$_CONSUL_WAIT_INTERVAL") ))

  while [ "$(date +%s)" -lt "$end_time" ]; do
    if check_consul_ready; then
      log "INFO" "Consul server is ready."
      return 0
    fi
    log "DEBUG" "Consul not ready, waiting ${interval_sec}s..."
    sleep "$interval_sec"
  done

  log "ERROR" "Timed out waiting for Consul server after ${_CONSUL_WAIT_TIMEOUT}."
  exit 1
}

# Get full path for service config file
get_service_config_path() {
    if [ -z "$_SERVICE_CONFIG_FILE" ]; then
        echo "" # Return empty if not set
    elif [[ "$_SERVICE_CONFIG_FILE" == /* ]]; then
        echo "$_SERVICE_CONFIG_FILE" # Absolute path
    else
        echo "${_CONSUL_CONFIG_DIR}/${_SERVICE_CONFIG_FILE}" # Relative to config dir
    fi
}

# Register service defined in the config file
register_service() {
  local config_path
  config_path=$(get_service_config_path)

  if [ -z "$config_path" ]; then
    log "INFO" "No service registration file specified (SERVICE_CONFIG_FILE not set)."
    return 0
  fi

  if [ ! -f "$config_path" ]; then
    log "ERROR" "Service config file not found: ${config_path}"
    exit 1
  fi

  log "INFO" "Registering service defined in ${config_path}..."
  if consul services register -http-addr="${CONSUL_CLI_ADDR}" "${config_path}"; then
    log "INFO" "Service registration successful."
    # Set up trap only AFTER successful registration

    trap cleanup_and_exit EXIT INT TERM QUIT
  else
    log "ERROR" "Failed to register service from ${config_path}."
    log "ERROR" "Check file content and Consul server logs."
    # echo "--- Service Config Content ---"; cat "$config_path"; echo "--- End Service Config ---" # Optional: dump config
    exit 1
  fi
}

# Write central configuration entries (from files list and/or directory)
write_central_config() {
  local config_written=false
  local file_path

  # Process semicolon-separated list of files
  if [ -n "$_CENTRAL_CONFIG_FILES" ]; then
    log "INFO" "Processing central config files list..."
    local IFS=';'
    for file in $_CENTRAL_CONFIG_FILES; do
        # Handle absolute vs relative paths
        if [[ "$file" == /* ]]; then
            file_path="$file"
        else
            file_path="${_CONSUL_CENTRAL_CONFIG_DIR}/${file}"
        fi

        if [ -f "$file_path" ]; then
            log "INFO" "Writing central config: ${file_path}"
            if consul config write -http-addr="${CONSUL_CLI_ADDR}" "$file_path"; then
                config_written=true
            else
                log "ERROR" "Error writing central config: ${file_path}. Check file content/Consul server logs."
                # echo "--- Config Content ---"; cat "$file_path"; echo "--- End Config ---"
                exit 1
            fi
        else
            log "WARN" "Central config file not found: ${file_path}"
        fi
    done
  fi

  # Process directory
  if [ -d "$_CONSUL_CENTRAL_CONFIG_DIR" ]; then
     log "INFO" "Processing central config files from directory: ${_CONSUL_CENTRAL_CONFIG_DIR}..."
     # Use find for safe filename handling and only process .hcl or .json files
     find "$_CONSUL_CENTRAL_CONFIG_DIR" -maxdepth 1 -type f \( -name "*.hcl" -o -name "*.json" \) -print0 | while IFS= read -r -d $'\0' file; do
        log "INFO" "Writing central config: ${file}"
        if consul config write -http-addr="${CONSUL_CLI_ADDR}" "$file"; then
           config_written=true
        else
           log "ERROR" "Error writing central config: ${file}. Check file content/Consul server logs."
           # echo "--- Config Content ---"; cat "$file"; echo "--- End Config ---"
           exit 1
        fi
     done
  fi

  if ! $config_written; then
    log "INFO" "No central configuration specified or found to write."
  fi
}


# Cleanup function called by trap
cleanup_and_exit() {
  local exit_code=$? # Capture exit code before doing anything else
  log "INFO" "Received signal or main command exited (Code: $exit_code). Cleaning up..."

  # Deregister service if it was registered
  local config_path
  config_path=$(get_service_config_path)
  if [ -n "$config_path" ] && [ -f "$config_path" ]; then
    # Safely extract service ID using jq (requires jq installed)
    local service_id
    service_id=$(jq -r '.service.id // .service.name // empty' < "$config_path" 2>/dev/null)

    if [ -n "$service_id" ]; then
        log "INFO" "Deregistering service ID: ${service_id}..."
        # Use a timeout for the deregister command
        timeout 10s consul services deregister -http-addr="${CONSUL_CLI_ADDR}" -id="${service_id}" \
          || log "WARN" "Failed to deregister service ID ${service_id} (maybe already done or timed out)."
    else
        log "WARN" "Could not determine service ID from ${config_path} for automatic deregistration."
    fi
  fi

  # Kill the background command if it's still running (gracefully first, then force)
  if [ -n "${CHILD_PID:-}" ] && ps -p "$CHILD_PID" > /dev/null; then
      log "INFO" "Sending SIGTERM to main command PID ${CHILD_PID}..."
      kill -TERM "$CHILD_PID" 2>/dev/null
      # Wait a short time for graceful shutdown
      if ! timeout 5s wait "$CHILD_PID" 2>/dev/null; then
          log "WARN" "Main command did not exit after SIGTERM, sending SIGKILL to PID ${CHILD_PID}..."
          kill -KILL "$CHILD_PID" 2>/dev/null || true # Ignore errors if already gone
      fi
  fi

  log "INFO" "Cleanup complete. Exiting with code ${exit_code}."
  exit "$exit_code"
}

# === Main Execution ===

log "INFO" "Starting Consul/Envoy Sidecar Entrypoint..."
log "DEBUG" "--- Environment Configuration ---"
log "DEBUG" "CONSUL_CLI_ADDR: ${CONSUL_CLI_ADDR}"
log "DEBUG" "CONNECT_BOOTSTRAP_ADDR: ${CONNECT_BOOTSTRAP_ADDR}"
log "DEBUG" "ENTRYPOINT_LOG_LEVEL: ${_LOG_LEVEL}"
log "DEBUG" "WAIT_FOR_CONSUL: ${_WAIT_FOR_CONSUL}"
log "DEBUG" "CONSUL_CONFIG_DIR: ${_CONSUL_CONFIG_DIR}"
log "DEBUG" "CONSUL_CENTRAL_CONFIG_DIR: ${_CONSUL_CENTRAL_CONFIG_DIR}"
log "DEBUG" "SERVICE_CONFIG_FILE: ${_SERVICE_CONFIG_FILE}"
log "DEBUG" "CENTRAL_CONFIG_FILES: ${_CENTRAL_CONFIG_FILES}"
log "DEBUG" "Main Command Args: ${MAIN_COMMAND[*]:-(Not provided)}"
log "DEBUG" "Running as user: $(id -u):$(id -g) ($(id -un))"
log "DEBUG" "Entrypoint PID: $$"
log "DEBUG" "-------------------------------"


# 1. Wait for Consul Server (if enabled)
wait_for_consul

# 2. Register Service (sets up cleanup trap on success)
register_service

# 3. Write Central Config Entries
write_central_config

# 4. Execute the main command (e.g., consul connect envoy...)
if [ ${#MAIN_COMMAND[@]} -eq 0 ]; then
    log "ERROR" "No main command specified (CMD in Dockerfile or command: in compose). Exiting."
    exit 1
fi

log "INFO" "Executing main command: ${MAIN_COMMAND[*]}"

# Execute the command in the background
"${MAIN_COMMAND[@]}" &
CHILD_PID=$!
log "DEBUG" "Main command running in background with PID ${CHILD_PID}"

# Wait for the background command to finish or be signaled
# This wait ensures the script stays alive until the main command exits or a signal is received
wait $CHILD_PID

# The exit code is captured and used by the trap handler
# The script will exit here, triggering the 'cleanup_and_exit' function via the trap

