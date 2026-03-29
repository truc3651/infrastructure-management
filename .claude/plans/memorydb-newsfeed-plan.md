# MemoryDB Plan for Newsfeed Cache

## Overview

Build AWS MemoryDB cluster for the **newsfeed materialized view** - a durable, high-performance cache that persists news feed data.

## Why MemoryDB Instead of ElastiCache?

| Aspect | ElastiCache (Valkey) | MemoryDB |
|--------|---------------------|----------|
| **Durability** | Cache only, data loss on failure | Durable with Multi-AZ transaction log |
| **Use Case** | Cache-aside (rebuild from DB) | Primary data store / materialized view |
| **Persistence** | Optional snapshots | Always durable (transaction log) |
| **Recovery** | Cold start, cache warming | Instant recovery, no data loss |
| **Price** | Lower | ~20% higher |

**For newsfeed materialized view**: Data is pre-computed (fanout on write) and expensive to rebuild. MemoryDB's durability ensures no data loss on failover.

---

## Configuration Summary

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Engine** | Redis 7.1 (MemoryDB) | MemoryDB uses Redis-compatible API |
| **Cluster Mode** | Enabled | 2 shards for write scalability — see reasoning below |
| **Shards** | 2 | Distribute fanout write load across two primaries |
| **Replicas/Shard** | 1 | HA with lower cost |
| **Node Type** | `db.t4g.small` | Side project — 1.37 GB, cheapest MemoryDB tier |
| **Durability** | Multi-AZ transaction log | Automatic, always enabled in MemoryDB |
| **Encryption** | TLS in-transit + KMS at-rest | MemoryDB holds durable materialized data |

## Why 2 Shards in MemoryDB But 1 in ElastiCache?

The deciding factor is the **nature of writes**, not the technology.

**ElastiCache (cache-aside)**: writes are cache misses — a single `SET user:123 ...` per cache miss. Low write volume, one primary is fine.

**MemoryDB (fanout on write)**: when a user with 5,000 followers posts, the fanout service writes to 5,000 different `feed:{userId}` keys **in parallel**. Every write goes to a primary node. With 1 shard, all 5,000 writes queue on one primary — this is the exact write bottleneck sharding solves.

With 2 shards (16,384 hash slots split evenly):
- `feed:{userId}` is hashed via `CRC16(feed:{userId}) % 16384`
- Roughly half the users land on shard 1's primary, half on shard 2's primary
- A popular-user fanout distributes writes across both primaries simultaneously
- If shard 1 fails, users whose feed keys hash to shard 2 still get their feed unaffected

## MemoryDB Durability — Multi-AZ Transaction Log

MemoryDB works like a database, not a cache. Every write follows this sequence:

```
Client: ZADD feed:123 1709500000 "post:456"
                │
                ▼
  MemoryDB Primary Node (in-memory)
                │
                ▼  [committed synchronously before ACK]
  Multi-AZ Transaction Log (3 AZs)
                │
                ▼  [replicated asynchronously]
  Replica Node (in-memory)
                │
                ▼
  "OK" returned to client
```

The write is **not acknowledged until it is in the transaction log**. This means:
- Primary crashes immediately after "OK" → data is safe, transaction log persists it
- New primary starts → replays transaction log to restore full state → zero data loss
- Entire AZ goes down → transaction log exists in other AZs, replica promotes instantly

This is equivalent to PostgreSQL's Write-Ahead Log (WAL). The log is the source of truth; the in-memory state is derived from the log.

**Contrast with ElastiCache**: writes go to memory first, then replicated **asynchronously** to replica. Primary dies before replication finishes → that write is lost. Acceptable for a disposable cache; not acceptable for a materialized view you cannot cheaply rebuild.

## Point-in-Time Snapshots

MemoryDB takes daily RDB (Redis Database) snapshots — a full serialized dump of all keys at a specific moment. With `snapshot_retention_limit = 7`, you can restore to any daily point within the past week.

```
Week timeline:
  Mon 03:00 ── snapshot_1 ──┐
  Tue 03:00 ── snapshot_2   │ Any of these can be used
  Wed 03:00 ── snapshot_3   │ to spin up a new cluster
  Thu 03:00 ── snapshot_4 ──┘
                │
  Thu 14:00: bug deploys, corrupts feed data
                │
  Thu 15:00: restore from snapshot_4 → feeds are back to Thu 03:00 state
```

Snapshots complement (not replace) the transaction log:
- **Transaction log** → real-time durability, protects every individual write
- **Snapshots** → point-in-time recovery, protects against logical corruption (bad data written by a bug)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MemoryDB Cluster                              │
│                  (Cluster Mode Enabled)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Shard 1 (Slots 0-8191)         Shard 2 (Slots 8192-16383)      │
│  ┌─────────────┐                ┌─────────────┐                 │
│  │   Primary   │                │   Primary   │                 │
│  │   (AZ-a)    │                │   (AZ-b)    │                 │
│  └──────┬──────┘                └──────┬──────┘                 │
│         │                              │                         │
│  ┌──────▼──────┐                ┌──────▼──────┐                 │
│  │   Replica   │                │   Replica   │                 │
│  │   (AZ-b)    │                │   (AZ-a)    │                 │
│  └─────────────┘                └─────────────┘                 │
│                                                                  │
│  Newsfeed Data (from system design):                            │
│  • feed:{userId} → List of post IDs (sorted, reverse chrono)    │
│  • Hash slot = CRC16(feed:{userId}) % 16384                     │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│              Durable Multi-AZ Transaction Log                    │
│        (Automatic, no snapshot configuration needed)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files to Create

```
modules/memorydb-cluster/
├── main.tf              # Cluster, subnet group, ACL
├── variables.tf         # Input variables
├── outputs.tf           # Cluster endpoint + secret ARN
├── security.tf          # Security group for EKS access
├── parameter-group.tf   # MemoryDB parameters
└── versions.tf          # Provider versions

environments/prod/memorydb-cluster/
└── terragrunt.hcl       # Terragrunt wrapper
```

---

## Parameter Group Configuration

**Family**: `memorydb_redis7`

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `maxmemory-policy` | `volatile-lru` | Only evict keys with TTL set. Newsfeed entries have TTL. |
| `timeout` | `0` | Disabled - MemoryDB handles connection lifecycle |
| `tcp-keepalive` | `300` | Detect dead connections |
| `activedefrag` | `yes` | Memory defragmentation |
| `hash-max-listpack-entries` | `512` | Optimize hash encoding |

```hcl
resource "aws_memorydb_parameter_group" "this" {
  family = "memorydb_redis7"
  name   = "${var.cluster_name}-memorydb-params"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  tags = var.common_tags
}
```

---

## ACL (Access Control List)

MemoryDB uses ACLs instead of simple AUTH tokens:

```hcl
resource "random_password" "user_password" {
  length  = 32
  special = false
}

resource "aws_memorydb_user" "app_user" {
  user_name     = "${var.cluster_name}-app"
  access_string = "on ~feed:* &* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [random_password.user_password.result]
  }

  tags = var.common_tags
}

resource "aws_memorydb_acl" "this" {
  name       = "${var.cluster_name}-acl"
  user_names = [aws_memorydb_user.app_user.user_name]

  tags = var.common_tags
}
```

**Access String Explained**:
- `on` - User is active
- `~feed:*` - Can only access keys starting with `feed:`
- `&*` - Can access all channels (pub/sub)
- `+@all` - All commands allowed
- `-@dangerous` - Except dangerous commands (FLUSHALL, DEBUG, etc.)

---

## Cluster Resource

```hcl
resource "aws_memorydb_cluster" "this" {
  name                   = "${var.cluster_name}-newsfeed"
  description            = "MemoryDB cluster for newsfeed materialized view"

  # Engine
  engine_version         = "7.1"

  # Cluster Mode (Sharding)
  num_shards             = var.num_shards              # 2
  num_replicas_per_shard = var.replicas_per_shard      # 1

  # Node Type
  node_type              = var.node_type               # db.t4g.small

  # ACL
  acl_name               = aws_memorydb_acl.this.name

  # Networking
  subnet_group_name      = aws_memorydb_subnet_group.this.name
  security_group_ids     = [aws_security_group.this.id]

  # Security
  tls_enabled            = true
  kms_key_arn            = aws_kms_key.this.arn

  # Parameter Group
  parameter_group_name   = aws_memorydb_parameter_group.this.name

  # Maintenance
  maintenance_window     = var.maintenance_window

  # Snapshots (MemoryDB manages durability via transaction log)
  snapshot_retention_limit = var.snapshot_retention_limit  # 7 days for backup
  snapshot_window          = "03:00-04:00"

  # SNS Notifications (optional)
  # sns_topic_arn = var.sns_topic_arn

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-newsfeed"
  })
}
```

---

## Outputs

```hcl
output "cluster_endpoint" {
  description = "Cluster endpoint for Redis Cluster mode connections"
  value       = aws_memorydb_cluster.this.cluster_endpoint[0].address
}

output "port" {
  description = "MemoryDB port"
  value       = aws_memorydb_cluster.this.cluster_endpoint[0].port
}

output "credentials_secret_arn" {
  description = "Secrets Manager ARN containing connection credentials"
  value       = aws_secretsmanager_secret.credentials.arn
}
```

---

## Secrets Manager Structure

```json
{
  "host": "<cluster-endpoint>",
  "port": "6379",
  "username": "backend-app",
  "password": "<user-password>",
  "tlsEnabled": "true",
  "clusterMode": "true"
}
```

---

## Security Group

```hcl
resource "aws_security_group" "this" {
  name        = "${var.cluster_name}-memorydb-sg"
  description = "Security group for MemoryDB newsfeed cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MemoryDB from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-memorydb-sg"
  })
}
```

---

## Terragrunt Configuration

```hcl
# environments/prod/memorydb-cluster/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules/memorydb-cluster"
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
  num_shards           = 2
  replicas_per_shard   = 1
  node_type            = "db.t4g.small"
  engine_version       = "7.1"

  # Maintenance & Snapshots
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = 7

  # Timeouts
  tcp_keepalive = 300
}
```

---

## Newsfeed Data Model

Based on the system design document:

```
Key Pattern: feed:{userId}
Data Type: Sorted Set (ZSET)
Score: Timestamp (for reverse chronological ordering)
Member: Post ID

Example:
  ZADD feed:123 1709500000 "post:456"
  ZADD feed:123 1709499000 "post:789"

Retrieve latest 20 posts:
  ZREVRANGE feed:123 0 19
```

**Fanout on Write** (from system design):
1. User publishes a post
2. Fanout service gets friend list
3. For each friend, add post ID to their feed:
   ```
   ZADD feed:{friendId} {timestamp} {postId}
   ```
4. Trim feed to max length:
   ```
   ZREMRANGEBYRANK feed:{friendId} 0 -{maxFeedSize+1}
   ```

---

## Backend Code Changes for MemoryDB

### New ReactiveCacheTemplate for Cluster Mode

MemoryDB with cluster mode requires a **Redis Cluster client**. The existing `ReactiveCacheTemplate` uses standalone mode.

**Option 1**: Create a new `ReactiveClusterCacheTemplate` in backend-core
**Option 2**: Add cluster mode support to existing factory

Recommended changes in `backend-core`:

```java
// CacheConnectionSettings.java - Add cluster mode flag
public class CacheConnectionSettings {
  private String host;
  private String port;
  private String username;  // NEW for MemoryDB ACL
  private String password;
  private boolean tlsEnabled;
  private boolean clusterMode;  // NEW
}

// ReactiveCacheFactory.java - Support cluster mode
if (settings.isClusterMode()) {
  // Use LettuceClusterConnectionFactory
  RedisClusterConfiguration clusterConfig = new RedisClusterConfiguration();
  clusterConfig.addClusterNode(new RedisNode(settings.getHost(), settings.getPort()));
  // ... configure cluster client
}
```

---

## Cost Estimate (ap-southeast-1)

| Resource | Spec | Monthly Cost (USD) |
|----------|------|-------------------|
| db.t4g.small | 4 nodes (~$30/node, 2 shards x 2) | ~$120 |
| Snapshot storage | ~5 GB | ~$1 |
| KMS Key | 1 key | ~$1 |
| Secrets Manager | 1 secret | ~$0.40 |
| **Total** | | **~$122/month** |

MemoryDB is more expensive than ElastiCache but provides durability for the materialized view. `db.t4g.small` gives 1.37 GB per node — sufficient for a side project newsfeed.

---

## Comparison: ElastiCache vs MemoryDB

| Feature | ElastiCache Valkey | MemoryDB |
|---------|-------------------|----------|
| **Purpose** | Cache (backend-users, backend-posts) | Materialized View (newsfeed) |
| **Pattern** | Cache-aside | Write-through / Fanout |
| **Durability** | None (rebuild from DB) | Multi-AZ transaction log |
| **Cluster Mode** | Disabled (single shard) | Enabled (2 shards) |
| **Cost** | ~$28/month | ~$122/month |
| **Data Loss on Failure** | OK (rebuild) | NOT OK (expensive to rebuild) |

---

## Verification Plan

1. **Terraform Validation**
   ```bash
   cd environments/prod/memorydb-cluster
   terragrunt init && terragrunt validate && terragrunt plan
   ```

2. **Connectivity Test**
   ```bash
   kubectl run memorydb-test --rm -it --image=redis:7 -- \
     redis-cli -c -h <cluster-endpoint> -p 6379 --tls \
     --user <username> -a <password> PING
   # Note: -c flag for cluster mode
   ```

3. **Cluster Info**
   ```bash
   redis-cli -c ... CLUSTER INFO
   redis-cli -c ... CLUSTER NODES
   ```

4. **Newsfeed Operations Test**
   ```bash
   # Add post to feed
   redis-cli -c ... ZADD feed:test:123 1709500000 "post:456"
   # Get latest posts
   redis-cli -c ... ZREVRANGE feed:test:123 0 19 WITHSCORES
   # Trim feed
   redis-cli -c ... ZREMRANGEBYRANK feed:test:123 0 -1001
   ```

---

## Deployment Order

```yaml
1. vpc
2. eks-cluster
3. rds-cluster
4. rds-database-factory
5. elasticache-valkey      # For backend-users, backend-posts
6. memorydb-cluster        # For newsfeed
7. eks-addons
8. kafka-cluster
9. debezium
10. ecr
```
