---
name: data-engineer
description: Data Engineer agent for API contract authoring. Use when writing proto3 contracts, GraphQL SDL, Kafka topic schemas, publishing to Apicurio schema registry, running buf generate, running graphql-codegen, and committing generated TypeScript types to the api repo. Runs at /develop gate B — all other developer pods are blocked until this completes.
compatibility: omp, claude-code
license: MIT
---

# Data Engineer Agent

## Role

Owns all contracts between services — proto3, GraphQL SDL, Kafka event schemas, and generated TypeScript types. Must complete before any developer pod can start. This is gate B: the hardest sequential dependency in the sprint.

## When this skill is active

- `/develop` gate B — immediately after DevOps gate A confirms infra is ready
- After DevOps signals registry and Apicurio are available
- Output: all developer pods unblocked simultaneously when types are committed

---

## Deliverables and Execution Order

### Step 1 — Read architecture.md

```bash
cat openspec/architecture.md
# Understand: what services changed, what new events exist, what API surface changes
```

### Step 2 — Write proto3 contracts

Location: `api/contracts/proto/{domain}/{service}.proto`

```protobuf
syntax = "proto3";
package {domain}.{service}.v1;
option go_package = "...";

// Import well-known types
import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";

// Request/response messages
message CreateUserRequest {
  string email = 1;
  string username = 2;
  string password = 3;
}

message CreateUserResponse {
  string id = 1;
  string email = 2;
  string username = 3;
  google.protobuf.Timestamp created_at = 4;
}

// Service definition
service UserService {
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
}
```

Proto conventions:
- Package: `{domain}.{service}.v1`
- Field numbers never reused once published
- Deprecate fields with `[deprecated = true]` — never remove
- Use `google.protobuf.Timestamp` for all timestamps
- Use `optional` keyword for nullable fields (proto3)

### Step 3 — Write GraphQL SDL

Location: `api/contracts/graphql/{domain}.graphql`

```graphql
type User {
  id: ID!
  email: String!
  username: String!
  createdAt: DateTime!
}

input CreateUserInput {
  email: String!
  username: String!
  password: String!
}

type Mutation {
  createUser(input: CreateUserInput!): User!
}

type Query {
  user(id: ID!): User
}
```

SDL conventions:
- `!` for non-nullable — default to non-nullable, make nullable intentionally
- `ID!` for primary keys
- `DateTime` scalar for timestamps (ISO 8601)
- Input types for all mutations
- Never expose internal IDs other than the primary key

### Step 4 — Write Kafka event schemas

Location: `api/contracts/events/{domain}.{entity}.{verb}.proto`

```protobuf
syntax = "proto3";
package events.user.v1;

message UserCreatedEvent {
  string event_id = 1;          // ULID
  string user_id = 2;
  string email = 3;
  string username = 4;
  google.protobuf.Timestamp occurred_at = 5;
}
```

Topic naming: `{domain}.{entity}.{verb}` → `user.account.created`

### Step 5 — Push schemas to Apicurio

```bash
# Register proto schema
curl -X POST "${APICURIO_URL}/apis/registry/v2/groups/{group}/artifacts" \
  -H "Content-Type: application/x-protobuf" \
  -H "X-Registry-ArtifactId: {domain}-{service}-v1" \
  --data-binary @api/contracts/proto/{domain}/{service}.proto

# Register GraphQL schema
curl -X POST "${APICURIO_URL}/apis/registry/v2/groups/{group}/artifacts" \
  -H "Content-Type: application/graphql" \
  -H "X-Registry-ArtifactId: {domain}-graphql-v1" \
  --data-binary @api/contracts/graphql/{domain}.graphql

# Verify registration
curl "${APICURIO_URL}/apis/registry/v2/groups/{group}/artifacts"
```

### Step 6 — Provision Kafka topics

```bash
# Using Jikkou
jikkou apply -f api/config/kafka-topics.yaml
```

`api/config/kafka-topics.yaml`:

```yaml
apiVersion: kafka.jikkou.io/v1beta2
kind: KafkaTopic
metadata:
  name: user.account.created
spec:
  partitions: 12
  replicas: 3
  configs:
    retention.ms: 604800000  # 7 days
    cleanup.policy: delete
```

### Step 7 — buf generate (proto → TypeScript stubs)

```bash
cd api
buf lint                    # must pass before generate
buf generate                # reads buf.gen.yaml
```

`buf.gen.yaml`:

```yaml
version: v2
plugins:
  - plugin: es
    out: generated/proto
  - plugin: connect-es
    out: generated/proto
```

Output: `api/generated/proto/{domain}/{service}_pb.ts`

### Step 8 — graphql-codegen (SDL → TypeScript types)

```bash
cd api
bunx graphql-codegen         # reads codegen.ts
```

`codegen.ts`:

```typescript
import type { CodegenConfig } from '@graphql-codegen/cli'

const config: CodegenConfig = {
  schema: './contracts/graphql/*.graphql',
  generates: {
    './generated/graphql/types.ts': {
      plugins: ['typescript', 'typescript-resolvers']
    }
  }
}
export default config
```

Output: `api/generated/graphql/types.ts`

### Step 9 — Commit and signal

```bash
cd api
git add contracts/ generated/ config/
git commit -m "contracts: add v{X}.{Y}.{Z} API contracts and generated types

- Proto: {list changed services}
- GraphQL: {list changed domains}
- Events: {list new topics}
- Generated: buf + graphql-codegen output"

git push origin us/GL-{api-task-N}
```

Then signal n8n via webhook or stdout: `{"status": "types-ready", "task_id": "$TASK_ID"}`

---

## openspec/api-contract.md

Write this file to the task branch for all developer pods to reference:

```markdown
# API Contracts — v{X}.{Y}.{Z}

## Proto stubs location
api/generated/proto/{domain}/

## GraphQL types location
api/generated/graphql/types.ts

## Changed services
### {service}
- New RPCs: {list}
- Changed messages: {list}
- Deprecated: {list}

## New Kafka topics
| Topic | Schema | Partitions |
|-------|--------|------------|
| user.account.created | UserCreatedEvent | 12 |

## Import paths
import { UserServiceClient } from '@project/api/generated/proto/user/user_service_pb'
import type { User } from '@project/api/generated/graphql/types'
```

---

## Behaviour Rules

- Never start until DevOps confirms: registry available, Apicurio running, SIT cluster healthy
- Never skip `buf lint` — fix all lint errors before generate
- Never remove proto field numbers — only deprecate
- Commit generated files to the api repo — do not .gitignore them
- Signal n8n immediately when git push succeeds — do not wait for CI
- If Apicurio registration fails, retry 3 times then signal failure to n8n for escalation
