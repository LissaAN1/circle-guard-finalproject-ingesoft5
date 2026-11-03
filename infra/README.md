# infra/ - AWS provisioning (TEC-04 / E1.2)

Idempotent Bash scripts that create the CircleGuard servers on AWS (default VPC,
`us-east-1`): **jenkins, sonarqube, nexus** (CI/CD) and **dev, stage, prod**
(one server per environment). Nothing is configured by hand; re-running a
script only creates what is missing. No credentials or keys live in this repo.

## Topology

| Security group | Servers | Inbound |
|:---|:---|:---|
| `circleguard-sg-cicd` | jenkins, sonarqube, nexus | 22, 8080 (Jenkins), 9000 (SonarQube), 8081/8082 (Nexus) from the admin IP; 8081/8082 from the env SGs (image/artifact pull) |
| `circleguard-sg-dev/stage/prod` | one server each | 22 from admin IP and from the CI/CD SG; 80 public (web client); service ports 8180, 8083-8087 from CI/CD SG and admin IP |

Environment SGs never reference each other, so **traffic between dev, stage and
prod is denied**. SSH is key-only (Ubuntu 24.04 default) and never open to
`0.0.0.0/0`. Servers use IMDSv2 and encrypted-in-transit package sources.
`t3.medium` (4 GiB) is a first estimate; resize if Neo4j + Kafka need more.

## Prerequisites

* AWS CLI v2 and a **personal IAM access key** (never pasted in chat or git):
  `aws configure` (region `us-east-1`). The IAM user needs EC2, SSM (read) and Budgets permissions.
* Bash (WSL/Linux/macOS), `curl`.

## Usage (in order)

```bash
infra/bootstrap-keypair.sh          # SSH key pair; .pem goes to ~/.ssh (chmod 400)
infra/bootstrap-network.sh          # security groups and rules
infra/bootstrap-instances.sh        # 6 servers, Docker installed via user-data
infra/create-budget.sh you@mail.com 50
infra/verify.sh                     # checks the TEC-04 acceptance criteria
infra/status.sh                     # states and IPs
ssh -i ~/.ssh/circleguard-key.pem ubuntu@<public-ip>
```

Change sizes, disks or the key name in `config.env` (or override via env vars).
Costs and shutdown: see `docs/costs.md`.

## Acceptance criteria (Jira PI-4)

| Criterion | Evidence |
|:---|:---|
| CI/CD and 3 environment servers exist | `verify.sh`, `status.sh` |
| Traffic between environments blocked | `verify.sh` (no cross-env SG references) |
| SSH by key, no key in the repo | `.gitignore` (`*.pem`), `verify.sh` |
| Cost estimate and shutdown procedure | `docs/costs.md`, `power.sh`, `teardown.sh` |
