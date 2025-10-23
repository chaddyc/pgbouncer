# PgBouncer Docker Container

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-%230D597F.svg?style=for-the-badge&logo=alpine-linux&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)


A production-ready, lightweight Docker container for [PgBouncer](https://www.pgbouncer.org/) - a lightweight connection pooler for PostgreSQL. Built on Alpine Linux with comprehensive configuration management through environment variables.

## 🚀 Features

- **Lightweight**: Based on Alpine Linux for minimal resource usage
- **Environment-driven Configuration**: Complete configuration through environment variables
- **Automatic Setup**: Auto-generates `pgbouncer.ini` and `userlist.txt` on startup
- **Security-focused**: Scram-sha-256 password hashing, non-root execution, proper file permissions
- **Production-ready**: Health checks, graceful shutdown, comprehensive logging
- **Easy Deployment**: Docker Compose support with PostgreSQL integration
- **Validation**: Configuration validation and database connectivity testing

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Environment Variables](#-environment-variables)
- [Deployment](#-deployment)
- [Usage Examples](#-usage-examples)
- [Monitoring](#-monitoring)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

## 🚀 Quick Start

### Using Docker Compose (Recommended)

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd pgbouncer-docker
   ```

2. **Start the services:**
   ```bash
   docker-compose up -d
   ```

3. **Connect to PgBouncer:**
   ```bash
   psql -h localhost -p 6432 -U myuser -d myapp
   ```

### Using Docker

```bash
# Build the image
docker build -t my-pgbouncer .

# Run the container
docker run -d \
  --name pgbouncer \
  -p 6432:6432 \
  -e DB_HOST=postgres-server \
  -e DB_PORT=5432 \
  -e DB_USER=myuser \
  -e DB_PASSWORD=mypassword \
  -e DB_NAME=myapp \
  my-pgbouncer
```

## ⚙️ Configuration

The container is configured entirely through environment variables. The entrypoint script automatically generates the PgBouncer configuration files on startup.

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DB_HOST` | PostgreSQL server hostname | `postgres` |
| `DB_PORT` | PostgreSQL server port | `5432` |
| `DB_USER` | Database username | `myuser` |
| `DB_PASSWORD` | Database password | `mypassword` |
| `DB_NAME` | Database name | `myapp` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `PGBOUNCER_PORT` | PgBouncer listen port | `6432` |
| `PGBOUNCER_DATABASE` | Database pattern | `"*"` |
| `PGBOUNCER_POOL_MODE` | Pool mode (transaction/session/statement) | `transaction` |
| `PGBOUNCER_AUTH_TYPE` | Authentication type | `md5` |

## 🔧 Environment Variables

### Connection Pool Settings
```bash
PGBOUNCER_MAX_CLIENT_CONN=100          # Maximum client connections
PGBOUNCER_DEFAULT_POOL_SIZE=20         # Default pool size per database
PGBOUNCER_MIN_POOL_SIZE=5              # Minimum pool size
PGBOUNCER_RESERVE_POOL_SIZE=5          # Reserved connections
PGBOUNCER_MAX_DB_CONNECTIONS=50        # Maximum database connections
PGBOUNCER_MAX_USER_CONNECTIONS=50      # Maximum connections per user
```

### Timeout Settings (in seconds)
```bash
PGBOUNCER_SERVER_LIFETIME=3600         # Connection lifetime
PGBOUNCER_SERVER_IDLE_TIMEOUT=600      # Server idle timeout
PGBOUNCER_CLIENT_IDLE_TIMEOUT=0        # Client idle timeout (0 = disabled)
```

### Logging Settings
```bash
PGBOUNCER_LOG_CONNECTIONS=1            # Log connections (0/1)
PGBOUNCER_LOG_DISCONNECTIONS=1         # Log disconnections (0/1)
PGBOUNCER_LOG_POOLER_ERRORS=1          # Log pooler errors (0/1)
PGBOUNCER_STATS_PERIOD=60              # Stats logging period
```

### Performance Settings
```bash
PGBOUNCER_SERVER_RESET_QUERY="DISCARD ALL"
PGBOUNCER_IGNORE_STARTUP_PARAMETERS="extra_float_digits"
```

### Admin Access
```bash
PGBOUNCER_ADMIN_USERS=myuser           # Users with admin access
PGBOUNCER_STATS_USERS=myuser           # Users with stats access
```

## 🚢 Deployment

### Docker Compose with PostgreSQL

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:18.0
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
    volumes:
      - postgres_data:/var/lib/postgresql/18/docker
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5

  pgbouncer:
    build: .
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
      DB_USER: myuser
      DB_PASSWORD: mypassword
      DB_NAME: myapp
      PGBOUNCER_POOL_MODE: transaction
      PGBOUNCER_DEFAULT_POOL_SIZE: 20
    ports:
      - "6432:6432"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "psql -h localhost -p 6432 -U myuser -d myapp -c 'SELECT 1;' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        image: my-pgbouncer:latest
        ports:
        - containerPort: 6432
        env:
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_PORT
          value: "5432"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: DB_NAME
          value: "myapp"
        livenessProbe:
          exec:
            command:
            - psql
            - -h
            - localhost
            - -p
            - "6432"
            - -U
            - $(DB_USER)
            - -d
            - $(DB_NAME)
            - -c
            - "SELECT 1;"
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer-service
spec:
  selector:
    app: pgbouncer
  ports:
  - protocol: TCP
    port: 6432
    targetPort: 6432
```

## 📊 Usage Examples

### Basic Connection

```bash
# Connect using psql
psql -h localhost -p 6432 -U myuser -d myapp

# Connection string
postgresql://myuser:mypassword@localhost:6432/myapp
```

### Admin Commands

```bash
# Connect to PgBouncer admin console
psql -h localhost -p 6432 -U myuser -d pgbouncer

# Show active pools
SHOW POOLS;

# Show database configuration
SHOW DATABASES;

# Show connection statistics
SHOW STATS;

# Show current configuration
SHOW CONFIG;

# Reload configuration (after changes)
RELOAD;

# Pause all activity
PAUSE;

# Resume activity
RESUME;
```

### Application Integration

#### Python (psycopg2)
```python
import psycopg2

conn = psycopg2.connect(
    host="pgbouncer-host",
    port=6432,
    database="myapp",
    user="myuser",
    password="mypassword"
)
```

#### Node.js (pg)
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'pgbouncer-host',
  port: 6432,
  database: 'myapp',
  user: 'myuser',
  password: 'mypassword',
});
```

#### Go (lib/pq)
```go
import (
    "database/sql"
    _ "github.com/lib/pq"
)

db, err := sql.Open("postgres", 
    "host=pgbouncer-host port=6432 user=myuser password=mypassword dbname=myapp sslmode=disable")
```

#### Java (JDBC)
```java
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DatabaseConnection {
    private static final String URL = "jdbc:postgresql://pgbouncer-host:6432/myapp";
    private static final String USER = "myuser";
    private static final String PASSWORD = "mypassword";
    
    public static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(URL, USER, PASSWORD);
    }
    
    // Using HikariCP connection pool (recommended)
    public static HikariDataSource createDataSource() {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(URL);
        config.setUsername(USER);
        config.setPassword(PASSWORD);
        config.setMaximumPoolSize(20);
        return new HikariDataSource(config);
    }
}
```

#### C# (Npgsql)
```csharp
using Npgsql;
using Microsoft.Extensions.DependencyInjection;

// Basic connection
var connectionString = "Host=pgbouncer-host;Port=6432;Database=myapp;Username=myuser;Password=mypassword";

using var connection = new NpgsqlConnection(connectionString);
await connection.OpenAsync();

// ASP.NET Core DI registration
services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql("Host=pgbouncer-host;Port=6432;Database=myapp;Username=myuser;Password=mypassword"));

// Connection pooling with NpgsqlDataSource (.NET 6+)
var dataSourceBuilder = new NpgsqlDataSourceBuilder(connectionString);
dataSourceBuilder.UseLoggerFactory(loggerFactory);
await using var dataSource = dataSourceBuilder.Build();
await using var connection = await dataSource.OpenConnectionAsync();
```

## 📈 Monitoring

### Health Checks

The container includes built-in health checks:

```bash
# Check container health
docker ps

# View health check logs
docker inspect pgbouncer | jq '.[0].State.Health'
```

### Log Files

```bash
# View PgBouncer logs
docker logs pgbouncer

# View logs inside container
docker exec pgbouncer tail -f /var/log/pgbouncer/pgbouncer.log
```

### Statistics Monitoring

```sql
-- Connect to pgbouncer admin
psql -h localhost -p 6432 -U myuser -d pgbouncer

-- Pool statistics
SHOW STATS;

-- Pool status
SHOW POOLS;

-- Active clients
SHOW CLIENTS;

-- Active servers
SHOW SERVERS;
```

### Prometheus Metrics

For Prometheus monitoring, consider using [pgbouncer_exporter](https://github.com/prometheus-community/pgbouncer_exporter):

```yaml
version: '3.8'

services:
  # ... pgbouncer service ...
  
  pgbouncer-exporter:
    image: prometheuscommunity/pgbouncer-exporter:latest
    environment:
      PGBOUNCER_EXPORTER_HOST: pgbouncer
      PGBOUNCER_EXPORTER_PORT: 6432
      PGBOUNCER_EXPORTER_USER: myuser
      PGBOUNCER_EXPORTER_PASSWORD: mypassword
    ports:
      - "9127:9127"
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Database Connection Failures
```bash
# Check database connectivity
docker exec pgbouncer psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "SELECT 1;"

# Check environment variables
docker exec pgbouncer env | grep -E "^(DB_|PGBOUNCER_)"
```

#### 2. Authentication Errors
```bash
# Verify userlist.txt generation
docker exec pgbouncer cat /etc/pgbouncer/userlist.txt

# Check MD5 hash generation
docker exec pgbouncer sh -c 'echo -n "${DB_PASSWORD}${DB_USER}" | md5sum'
```

#### 3. Pool Exhaustion
```sql
-- Check pool utilization
SHOW POOLS;
SHOW STATS;

-- Increase pool sizes if needed
```

#### 4. Configuration Issues
```bash
# View generated configuration
docker exec pgbouncer cat /etc/pgbouncer/pgbouncer.ini

# Test configuration syntax
docker exec pgbouncer pgbouncer -v /etc/pgbouncer/pgbouncer.ini
```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Add to environment variables
PGBOUNCER_VERBOSE=2
PGBOUNCER_LOG_CONNECTIONS=1
PGBOUNCER_LOG_DISCONNECTIONS=1
PGBOUNCER_LOG_POOLER_ERRORS=1
```

### Performance Tuning

#### Pool Mode Selection
- **Transaction**: Best for most applications (recommended)
- **Session**: Use only if your app requires session state
- **Statement**: Highest throughput but limited compatibility

#### Pool Sizing Guidelines
- Start with `default_pool_size = 20-25`
- Set `max_client_conn` higher than expected concurrent users
- Monitor pool utilization: `cl_active / cl_waiting` ratio
- Adjust based on your application's connection patterns

#### Timeout Tuning
- `server_lifetime`: Set to handle connection rotation (3600s default)
- `server_idle_timeout`: Adjust based on database timeout settings
- `client_idle_timeout`: Set to 0 for most applications

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Test the changes: `docker-compose up --build`
5. Submit a pull request

### Reporting Issues

Please include:
- Docker version
- Container logs
- Environment variables (without sensitive data)
- Steps to reproduce

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 References

- [PgBouncer Official Documentation](https://www.pgbouncer.org/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Docker Best Practices](https://docs.docker.com/develop/best-practices/)

## ⭐ Support

If this project helped you, please consider giving it a ⭐ on GitHub!

---

**Made with ❤️ for the PostgreSQL community**
