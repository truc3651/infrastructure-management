# ElastiCache Valkey Plan for Backend Services

## Overview

Build AWS ElastiCache with **Valkey engine** for `backend-users` and `backend-posts` services using the **cache-aside pattern**.

## Configuration Summary

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Engine** | Valkey 7.2 | Open-source Redis fork, AWS recommended |
| **Cluster Mode** | Disabled | 1 shard is correct for cache-aside — see reasoning below |
| **Nodes** | 2 (1 primary + 1 replica) | HA without excessive cost |
| **Node Type** | `cache.t4g.micro` | Side project — 0.5 GB in-memory only, no data tiering |
| **Data Tiering** | Disabled | `t4g` does not support data tiering; only `r6gd` does |
| **Eviction Policy** | `allkeys-lru` | Evict least-recently-used when memory full |
| **Persistence** | Disabled | Cache-aside rebuilds from DB |
| **Multi-AZ** | Enabled | Replica in different AZ |
| **Auto-failover** | Enabled | Automatic promotion on failure |
| **Encryption** | TLS in-transit only | At-rest not needed (no persistence, no durable data) |

## Why 1 Shard (Cluster Mode Disabled)?

For **cache-aside**, the shard count decision is driven by whether the cache is **disposable**:

- **The cache is disposable by design.** If the entire cluster goes down, the application falls back to PostgreSQL/Neo4j seamlessly. The replica's only job is failover — keeping the cache alive during a single-node failure.
- **No write scalability pressure.** Cache writes are individual key sets (`SET user:123 ...`) triggered by cache misses, not bulk fanout. A single primary handles this easily.
- **Shards add client complexity for zero benefit.** Cluster mode forces the client to use `CLUSTER SLOTS` / `CLUSTER NODES` for slot discovery, implement exponential backoff + jitter on slot redirection, and handle `MOVED`/`ASK` errors. With cache-aside you get none of the upside (the data is disposable anyway) and all of the complexity.
- **Vertical scaling is the right lever.** When the cache gets too small, upgrade from `t4g.micro` → `t4g.medium` → `r7g.large`, not add shards.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              ElastiCache Valkey Replication Group                │
│                    (Cluster Mode Disabled)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│      ┌─────────────┐         ┌─────────────┐                    │
│      │   Primary   │────────▶│   Replica   │                    │
│      │   (AZ-a)    │  async  │   (AZ-b)    │                    │
│      │  Read/Write │         │  Read-only  │                    │
│      └─────────────┘         └─────────────┘                    │
│           0.5 GB                  0.5 GB                        │
│        in-memory only          in-memory only                   │
│                                                                  │
│      Cache Domains (from backend-users-management):             │
│      • user:{id}        → User profiles (TTL: 10m)              │
│      • friends:{id}     → Friend lists (TTL: 15m)               │
│      • suggestions:{id} → Friend suggestions (TTL: 30m)         │
│                                                                  │
│      Future (backend-posts):                                     │
│      • post:{id}        → Post content                          │
│      • comments:{id}    → Comments on posts                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files to Create

```
modules/elasticache-valkey/
├── main.tf              # Replication group, subnet group, secrets
├── variables.tf         # Input variables
├── outputs.tf           # Primary endpoint + secret ARN only
├── security.tf          # Security group for EKS access
├── parameter-group.tf   # Valkey parameters (timeouts, LFU)
└── versions.tf          # Provider versions

environments/prod/elasticache-valkey/
└── terragrunt.hcl       # Terragrunt wrapper
```

---

## Parameter Group Configuration

**Family**: `valkey7`

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `maxmemory-policy` | `allkeys-lru` | Evict least-recently-used keys when memory full. LFU dropped since we have no data tiering. |
| `timeout` | `300` | Close idle connections after 5 minutes. Prevents connection accumulation from crashed clients. |
| `tcp-keepalive` | `300` | Send TCP keepalive every 5 minutes. Detects dead connections that appear alive. |
| `activedefrag` | `yes` | Reorganize memory in background to reduce fragmentation. Prevents memory bloat over time. |
| `lazyfree-lazy-eviction` | `yes` | Free memory asynchronously during eviction. Reduces latency spikes under memory pressure. |
| `lazyfree-lazy-expire` | `yes` | Free memory asynchronously during TTL expiration. Same benefit as above. |

```hcl
resource "aws_elasticache_parameter_group" "this" {
  family      = "valkey7"
  name        = "${var.cluster_name}-valkey-params"
  description = "Valkey parameters for ${var.cluster_name} cache"

  # Eviction policy - LRU (no data tiering on t4g)
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Server-side idle timeout (5 minutes)
  parameter {
    name  = "timeout"
    value = var.idle_timeout
  }

  # TCP keepalive interval
  parameter {
    name  = "tcp-keepalive"
    value = var.tcp_keepalive
  }

  # Active memory defragmentation
  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  # Async memory reclaim during eviction
  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  # Async memory reclaim during TTL expiration
  parameter {
    name  = "lazyfree-lazy-expire"
    value = "yes"
  }

  tags = var.common_tags
}
```

---

## Replication Group Resource

```hcl
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.cluster_name}-valkey"
  description          = "Valkey cache for ${var.cluster_name} (backend-users, backend-posts)"

  # Valkey Engine
  engine         = "valkey"
  engine_version = "7.2"

  # Non-Clustered Mode (1 shard with replica)
  num_cache_clusters = var.num_cache_clusters  # 2 = 1 primary + 1 replica

  node_type = var.node_type  # cache.t4g.micro

  # Data tiering NOT supported on t4g; only cache.r6gd.* supports it
  # data_tiering_enabled - NOT SET (defaults to false)

  # High Availability
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Security - TLS only (no at-rest encryption needed for cache)
  transit_encryption_enabled = true
  at_rest_encryption_enabled = false  # No persistence, no need
  auth_token                 = random_password.auth_token.result

  # Networking
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  # Parameter Group
  parameter_group_name = aws_elasticache_parameter_group.this.name

  # NO Persistence (cache-aside pattern)
  # snapshot_retention_limit - NOT SET (defaults to 0 = disabled)
  # snapshot_window - NOT SET
  # final_snapshot_identifier - NOT SET

  # Maintenance
  maintenance_window = var.maintenance_window

  # Records commands that exceed a configured execution time threshold (default: 10ms). Helps identify slow queries, inefficient access patterns, or keys with large values.
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  # General Valkey/Redis engine logs including startup, shutdown, replication events, failover events, memory warnings, and error conditions
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-valkey"
  })
}
```

---

## Outputs (Minimal for Cache-Aside)

```hcl
output "primary_endpoint_address" {
  description = "Primary endpoint for read/write operations"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Valkey port"
  value       = 6379
}

output "auth_token_secret_arn" {
  description = "Secrets Manager ARN containing connection credentials"
  value       = aws_secretsmanager_secret.cache_credentials.arn
}
```

---

## Secrets Manager Structure

The secret will contain credentials in a format compatible with `backend-core`:

```json
{
  "host": "<primary-endpoint-address>",
  "port": "6379",
  "password": "<auth-token>",
  "tlsEnabled": "true"
}
```

This matches `CacheConnectionSettings.java` in backend-core - **no code changes needed**.

---

## Security Group

```hcl
resource "aws_security_group" "this" {
  name        = "${var.cluster_name}-valkey-sg"
  description = "Security group for Valkey cache"
  vpc_id      = var.vpc_id

  # Inbound from EKS nodes on Valkey port
  ingress {
    description     = "Valkey from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # All outbound (for replication, CloudWatch)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-valkey-sg"
  })
}
```

---

## Terragrunt Configuration

```hcl
# environments/prod/elasticache-valkey/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/elasticache-valkey"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id                  = "vpc-mock"
    private_subnet_ids_list = ["subnet-mock-1", "subnet-mock-2"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"
  mock_outputs = {
    node_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name               = include.env.locals.cluster_name
  environment                = include.env.locals.environment
  vpc_id                     = dependency.vpc.outputs.vpc_id
  private_subnet_ids         = dependency.vpc.outputs.private_subnet_ids_list
  allowed_security_group_ids = [dependency.eks_cluster.outputs.node_security_group_id]

  # Cluster sizing
  num_cache_clusters = 2  # 1 primary + 1 replica
  node_type          = "cache.t4g.micro"
  engine_version     = "7.2"

  # Timeouts
  idle_timeout  = 300  # 5 minutes
  tcp_keepalive = 300

  # Security
  transit_encryption_enabled = true

  # Maintenance
  maintenance_window = "sun:05:00-sun:06:00"
}
```

---

## Backend Application Changes

### No Code Changes Required

The existing `backend-core` library already supports the new infrastructure:

1. **`CacheConnectionSettings.java`** - Already has: host, port, password, tlsEnabled
2. **`CacheConnectionSettingsProviderImplAWSSecret.java`** - Already reads from Secrets Manager
3. **`ReactiveCacheFactory.java`** - Already configures TLS when `tlsEnabled=true`

### Deployment Change

Update the Kubernetes deployment to use the new secret name:

```yaml
env:
  - name: AWS_CACHE_SECRET_NAME
    value: "backend-valkey-credentials"  # New secret name
  - name: AWS_CACHE_SECRET_REGION
    value: "ap-southeast-1"
```

---

## Cost Estimate (ap-southeast-1)

| Resource | Spec | Monthly Cost (USD) |
|----------|------|-------------------|
| cache.t4g.micro | 2 nodes (~$13/node) | ~$26 |
| CloudWatch Logs | Slow + Engine logs | ~$2 |
| Secrets Manager | 1 secret | ~$0.40 |
| **Total** | | **~$28/month** |

No KMS key cost (at-rest encryption disabled).
No snapshot storage cost (persistence disabled).

---

## Verification Plan

1. **Terraform Validation**
   ```bash
   cd environments/prod/elasticache-valkey
   terragrunt init && terragrunt validate && terragrunt plan
   ```

2. **Connectivity Test**
   ```bash
   kubectl run valkey-test --rm -it --image=redis:7 -- \
     redis-cli -h <primary-endpoint> -p 6379 --tls \
     -a <auth-token> PING
   # Expected: PONG
   ```

3. **Cache Operations Test**
   ```bash
   # Set with TTL
   redis-cli ... SET user:test:1 '{"id":1,"name":"test"}' EX 600
   # Get
   redis-cli ... GET user:test:1
   # Evict
   redis-cli ... DEL user:test:1
   ```
