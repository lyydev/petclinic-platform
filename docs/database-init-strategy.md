# Database Initialization Strategy — Petclinic Platform

## Overview

Spring Petclinic Microservices uses a single shared MySQL database named `petclinic` for all three database-backed domain services:
- `customers-service`
- `vets-service`
- `visits-service`

All three microservices connect to the same Amazon RDS MySQL 8.4 instance using credentials retrieved from AWS Secrets Manager (`petclinic/{env}/rds-credentials`) via External Secrets Operator.

---

## Architectural Context & Schema Design

### Shared Database Design

As documented in [ADR-0003](docs/technical-spec.md#adr-index) and [technical-spec.md](docs/technical-spec.md#rds-database), the application architecture uses a shared database due to cross-service relational dependencies:
- `customers-service` owns customer and pet data (`types`, `owners`, `pets`).
- `visits-service` owns visit data (`visits`), which has a foreign key referencing pets: `FOREIGN KEY (pet_id) REFERENCES pets(id)`.
- `vets-service` owns vet clinic data (`vets`, `specialties`, `vet_specialties`).

### Database Tables (7 Total)

| Service | Tables | Foreign Keys | Script Location |
|---------|--------|--------------|-----------------|
| `customers-service` | `types`<br>`owners`<br>`pets` | `pets.owner_id` &rarr; `owners.id`<br>`pets.type_id` &rarr; `types.id` | `src/main/resources/db/mysql/schema.sql`<br>`src/main/resources/db/mysql/data.sql` |
| `vets-service` | `vets`<br>`specialties`<br>`vet_specialties` | `vet_specialties.vet_id` &rarr; `vets.id`<br>`vet_specialties.specialty_id` &rarr; `specialties.id` | `src/main/resources/db/mysql/schema.sql`<br>`src/main/resources/db/mysql/data.sql` |
| `visits-service` | `visits` | `visits.pet_id` &rarr; `pets.id` | `src/main/resources/db/mysql/schema.sql`<br>`src/main/resources/db/mysql/data.sql` |

Each SQL script in the application begins with:
```sql
CREATE DATABASE IF NOT EXISTS petclinic;
USE petclinic;
```

---

## Initialization Strategy: Spring Boot Auto-Initialization

### Mechanism

Spring Boot provides built-in SQL database initialization capabilities via `spring.sql.init`.
When activated with:
- Profile: `SPRING_PROFILES_ACTIVE=docker,mysql`
- Datasource URL pointing to RDS: `jdbc:mysql://{rds-endpoint}:3306/petclinic`
- Property: `spring.sql.init.mode=always`

Spring Boot automatically detects and executes:
1. `db/mysql/schema.sql` (table definitions and constraints using `CREATE TABLE IF NOT EXISTS`)
2. `db/mysql/data.sql` (seed data)

### Startup Sequence & Dependency Enforcement

Because the `visits` table enforces `FOREIGN KEY (pet_id) REFERENCES pets(id)`, attempting to initialize `visits-service` before `customers-service` has created the `pets` table would fail with MySQL error 1215/1824 (Cannot add foreign key constraint).

To ensure correct initialization:
1. **Infrastructure Service Startup**:
   - `config-server` starts first.
   - `discovery-server` starts second.
2. **Domain Service Deployment Order**:
   - `customers-service` is deployed and initializes `types`, `owners`, and `pets` tables.
   - `vets-service` is deployed and initializes `vets`, `specialties`, and `vet_specialties` tables (independent).
   - `visits-service` is deployed only after `customers-service` is healthy and its tables exist, safely creating the `visits` table.

In Kubernetes / Helm / ArgoCD:
- `customers-service` readiness probe (`/actuator/health/readiness`) verifies database connectivity before marking the pod `Ready`.
- `visits-service` uses an init container or ArgoCD sync wave (`sync-wave: "1"` vs `sync-wave: "2"`) to ensure `customers-service` is running before `visits-service` starts.

---

## Connection String Format & Kubernetes ConfigMaps

### Connection String Format
```text
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

Example for Dev:
```text
jdbc:mysql://petclinic-dev-mysql.c5s8...us-east-1.rds.amazonaws.com:3306/petclinic
```

### Environment Variables for Domain Deployments

Each database-backed service receives the following environment variables:

| Variable | Value / Source | Description |
|----------|----------------|-------------|
| `SPRING_PROFILES_ACTIVE` | `docker,mysql` | Enables Docker networking and MySQL datasource |
| `SPRING_DATASOURCE_URL` | ConfigMap: `jdbc:mysql://{rds-endpoint}:3306/petclinic` | Connection endpoint |
| `SPRING_DATASOURCE_USERNAME` | Secret (`rds-credentials` &rarr; `username`) | Master username (`petclinic`) |
| `SPRING_DATASOURCE_PASSWORD` | Secret (`rds-credentials` &rarr; `password`) | Generated master password |

---

## Alternative / Migration Considerations

- **Manual / CI Migration (Flyway/Liquibase)**: For production environments requiring strict schema change auditing, Liquibase or Flyway can be adopted. For the Petclinic learning platform, Spring SQL auto-initialization provides an automated, idempotent, and self-healing startup mechanism.
