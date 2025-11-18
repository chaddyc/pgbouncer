ARG ALPINE_VERSION=3.22.1
ARG PGBOUNCER_VERSION=1.25.0

FROM alpine:${ALPINE_VERSION} AS build
ARG PGBOUNCER_VERSION

# Install build dependencies for Alpine
RUN set -ex; \
    apk update && apk upgrade; \
    apk add --no-cache \
        curl \
        make \
        pkgconfig \
        libevent-dev \
        build-base \
        openssl-dev \
        udns-dev \
        openssl; \
    rm -rf /var/cache/apk/*

# Build pgbouncer
RUN curl -sL http://www.pgbouncer.org/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz > pgbouncer.tar.gz; \
    tar xzf pgbouncer.tar.gz; \
    cd pgbouncer-${PGBOUNCER_VERSION}; \
    sh ./configure --without-cares --with-udns; \
    make

FROM alpine:${ALPINE_VERSION}
ARG ALPINE_VERSION
ARG PGBOUNCER_VERSION
ARG TARGETARCH

LABEL name="PgBouncer Container Image" \
      version=${PGBOUNCER_VERSION} \
      summary="Container images for PgBouncer (connection pooler for PostgreSQL)." \
      description="This Docker image contains PgBouncer ${PGBOUNCER_VERSION} based on Alpine ${ALPINE_VERSION}."

# Install runtime dependencies for Alpine
RUN set -ex; \
    apk update && apk upgrade; \
    apk add --no-cache \
        libevent \
        openssl \
        udns \
        shadow \
        findutils \
        postgresql-client; \
    rm -rf /var/cache/apk/*; \
    addgroup -g 996 -S pgbouncer; \
    adduser -u 998 -D -S -G pgbouncer pgbouncer; \
    mkdir -p /var/log/pgbouncer; \
    mkdir -p /var/run/pgbouncer; \
    mkdir -p /etc/pgbouncer; \
    chown pgbouncer:pgbouncer /var/log/pgbouncer; \
    chown pgbouncer:pgbouncer /var/run/pgbouncer; \
    chown pgbouncer:pgbouncer /etc/pgbouncer

COPY --from=build ["/pgbouncer-${PGBOUNCER_VERSION}/pgbouncer", "/usr/bin/"]
COPY --from=build ["/pgbouncer-${PGBOUNCER_VERSION}/etc/pgbouncer.ini", "/etc/pgbouncer/pgbouncer.ini.example"]
COPY --from=build ["/pgbouncer-${PGBOUNCER_VERSION}/etc/userlist.txt", "/etc/pgbouncer/userlist.txt.example"]

# Create empty config files that will be populated by entrypoint
RUN touch /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt; \
    chown pgbouncer:pgbouncer /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt

# DoD 2.3 - remove setuid/setgid from any binary that not strictly requires it
RUN find / -not -path "/proc/*" -perm /6000 -type f -exec ls -ld {} \; -exec chmod a-s {} \; 2>/dev/null || true

# Set default environment variables
ENV DB_HOST=localhost \
    DB_PORT=5432 \
    DB_USER=postgres \
    DB_PASSWORD=password \
    DB_NAME=postgres \
    PGBOUNCER_PORT=6432 \
    PGBOUNCER_DATABASE="*" \
    PGBOUNCER_POOL_MODE=transaction \
    PGBOUNCER_AUTH_TYPE=md5 \
    PGBOUNCER_MAX_CLIENT_CONN=100 \
    PGBOUNCER_DEFAULT_POOL_SIZE=20 \
    PGBOUNCER_MIN_POOL_SIZE=5 \
    PGBOUNCER_RESERVE_POOL_SIZE=5 \
    PGBOUNCER_MAX_DB_CONNECTIONS=50 \
    PGBOUNCER_MAX_USER_CONNECTIONS=50 \
    PGBOUNCER_SERVER_LIFETIME=3600 \
    PGBOUNCER_SERVER_IDLE_TIMEOUT=600 \
    PGBOUNCER_CLIENT_IDLE_TIMEOUT=0 \
    PGBOUNCER_LOG_CONNECTIONS=1 \
    PGBOUNCER_LOG_DISCONNECTIONS=1 \
    PGBOUNCER_LOG_POOLER_ERRORS=1 \
    PGBOUNCER_STATS_PERIOD=60 \
    PGBOUNCER_SERVER_RESET_QUERY="DISCARD ALL" \
    PGBOUNCER_IGNORE_STARTUP_PARAMETERS="extra_float_digits"

EXPOSE 6432

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown pgbouncer:pgbouncer /entrypoint.sh

USER pgbouncer

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
