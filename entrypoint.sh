#!/bin/sh

set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to create MD5 hash for PostgreSQL authentication
create_md5_hash() {
    local user="$1"
    local password="$2"
    echo -n "${password}${user}" | md5sum | cut -d' ' -f1 | sed 's/^/md5/'
}

# Function to generate pgbouncer.ini
generate_pgbouncer_config() {
    log "Generating PgBouncer configuration..."
    
    cat > /etc/pgbouncer/pgbouncer.ini << EOF
[databases]
${PGBOUNCER_DATABASE} = host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME}

[pgbouncer]
listen_port = ${PGBOUNCER_PORT}
listen_addr = 0.0.0.0
auth_type = ${PGBOUNCER_AUTH_TYPE}
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = ${PGBOUNCER_POOL_MODE}

; Connection limits
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE}
min_pool_size = ${PGBOUNCER_MIN_POOL_SIZE}
reserve_pool_size = ${PGBOUNCER_RESERVE_POOL_SIZE}
max_db_connections = ${PGBOUNCER_MAX_DB_CONNECTIONS}
max_user_connections = ${PGBOUNCER_MAX_USER_CONNECTIONS}

; Timeouts
server_lifetime = ${PGBOUNCER_SERVER_LIFETIME}
server_idle_timeout = ${PGBOUNCER_SERVER_IDLE_TIMEOUT}
client_idle_timeout = ${PGBOUNCER_CLIENT_IDLE_TIMEOUT}

; Logging
log_connections = ${PGBOUNCER_LOG_CONNECTIONS}
log_disconnections = ${PGBOUNCER_LOG_DISCONNECTIONS}
log_pooler_errors = ${PGBOUNCER_LOG_POOLER_ERRORS}
stats_period = ${PGBOUNCER_STATS_PERIOD}

; Performance
server_reset_query = ${PGBOUNCER_SERVER_RESET_QUERY}
ignore_startup_parameters = ${PGBOUNCER_IGNORE_STARTUP_PARAMETERS}

; Admin access
EOF

    # Add admin users if specified
    if [ -n "${PGBOUNCER_ADMIN_USERS}" ]; then
        echo "admin_users = ${PGBOUNCER_ADMIN_USERS}" >> /etc/pgbouncer/pgbouncer.ini
    fi
    
    # Add stats users if specified
    if [ -n "${PGBOUNCER_STATS_USERS}" ]; then
        echo "stats_users = ${PGBOUNCER_STATS_USERS}" >> /etc/pgbouncer/pgbouncer.ini
    fi
    
    # Set log destination
    echo "logfile = /var/log/pgbouncer/pgbouncer.log" >> /etc/pgbouncer/pgbouncer.ini
    echo "pidfile = /var/run/pgbouncer/pgbouncer.pid" >> /etc/pgbouncer/pgbouncer.ini
}

# Function to generate userlist.txt
generate_userlist() {
    log "Generating user authentication list..."
    
    # Validate required variables
    if [ -z "${DB_USER}" ] || [ -z "${DB_PASSWORD}" ]; then
        log "ERROR: DB_USER and DB_PASSWORD must be set"
        exit 1
    fi
    
    # Generate userlist.txt based on auth type
    case "${PGBOUNCER_AUTH_TYPE}" in
        "md5")
            log "Using MD5 authentication"
            local md5_hash
            md5_hash=$(create_md5_hash "${DB_USER}" "${DB_PASSWORD}")
            cat > /etc/pgbouncer/userlist.txt << EOF
"${DB_USER}" "${md5_hash}"
EOF
            ;;
        "scram-sha-256")
            log "Using SCRAM-SHA-256 authentication with plain text password"
            # For SCRAM-SHA-256, we need to store the plain text password
            # PgBouncer will handle the SCRAM exchange with the client
            # but needs the plain password to authenticate with PostgreSQL
            cat > /etc/pgbouncer/userlist.txt << EOF
"${DB_USER}" "${DB_PASSWORD}"
EOF
            ;;
        "plain")
            log "Using plain text authentication"
            cat > /etc/pgbouncer/userlist.txt << EOF
"${DB_USER}" "${DB_PASSWORD}"
EOF
            ;;
        *)
            log "ERROR: Unsupported auth type: ${PGBOUNCER_AUTH_TYPE}"
            log "Supported types: md5, scram-sha-256, plain"
            exit 1
            ;;
    esac
    
    # Set proper permissions for userlist.txt (contains passwords)
    chmod 600 /etc/pgbouncer/userlist.txt
}

# Function to validate configuration
validate_config() {
    log "Validating configuration..."
    
    # Check required environment variables
    local required_vars="DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME PGBOUNCER_PORT"
    for var in $required_vars; do
        eval "value=\$$var"
        if [ -z "$value" ]; then
            log "ERROR: Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Validate numeric values
    local numeric_vars="DB_PORT PGBOUNCER_PORT PGBOUNCER_MAX_CLIENT_CONN PGBOUNCER_DEFAULT_POOL_SIZE"
    for var in $numeric_vars; do
        eval "value=\$$var"
        if ! echo "$value" | grep -qE '^[0-9]+$'; then
            log "ERROR: $var must be a numeric value, got: $value"
            exit 1
        fi
    done
    
    # Test database connection
    log "Testing database connectivity..."
    if ! PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" > /dev/null 2>&1; then
        log "WARNING: Cannot connect to database ${DB_NAME} on ${DB_HOST}:${DB_PORT} as user ${DB_USER}"
        log "PgBouncer will start but database connections may fail until the database is available"
    else
        log "Database connection test successful"
    fi
}

# Function to setup logging
setup_logging() {
    # Create log file with proper permissions
    touch /var/log/pgbouncer/pgbouncer.log
    chmod 644 /var/log/pgbouncer/pgbouncer.log
}

# Function to handle shutdown signals
shutdown_handler() {
    log "Received shutdown signal, stopping PgBouncer..."
    if [ -f /var/run/pgbouncer/pgbouncer.pid ]; then
        local pid
        pid=$(cat /var/run/pgbouncer/pgbouncer.pid)
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid"
            # Wait for graceful shutdown
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 30 ]; do
                sleep 1
                count=$((count + 1))
            done
            if kill -0 "$pid" 2>/dev/null; then
                log "Forcing PgBouncer shutdown..."
                kill -KILL "$pid"
            fi
        fi
    fi
    exit 0
}

# Main execution
main() {
    log "Starting PgBouncer container initialization..."
    
    # Set up signal handlers
    trap 'shutdown_handler' TERM INT
    
    # Setup logging
    setup_logging
    
    # Validate configuration
    validate_config
    
    # Generate configuration files
    generate_pgbouncer_config
    generate_userlist
    
    log "Configuration complete. Starting PgBouncer..."
    log "PgBouncer will listen on port ${PGBOUNCER_PORT}"
    log "Database backend: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
    log "Pool mode: ${PGBOUNCER_POOL_MODE}"
    log "Auth type: ${PGBOUNCER_AUTH_TYPE}"
    
    # Start PgBouncer with the provided arguments
    exec "$@"
}

# Only run main if this script is executed directly (not sourced)
if [ "${0##*/}" = "entrypoint.sh" ]; then
    main "$@"
fi