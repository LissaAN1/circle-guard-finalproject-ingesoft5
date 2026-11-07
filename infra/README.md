# infra/ - AWS provisioning (TEC-04 / E1.2)

Idempotent Bash scripts that create the CircleGuard servers on AWS (default VPC,
`us-east-1`): **jenkins, sonarqube, nexus** (CI/CD) and **dev, stage, prod**
(one server per environment). Nothing is configured by hand; re-running a
script only creates what is missing. No credentials or keys live in this repo.

## Topology

| Security group | Servers | Inbound |
|:---|:---|:---|
| `circleguard-sg-cicd` | jenkins, sonarqube, nexus | 22, 8080 (Jenkins), 9000 (SonarQube), 8081/8082 (Nexus) from the admin IP; 8081/8082 from the env SGs (image/artifact pull) |
| `circleguard-sg-dev/stage/prod` | one server each | 22 from admin IP and from the CI/CD SG; 80 public (web client); service ports 8180, 8082-8088 from CI/CD SG and admin IP |

Environment SGs never reference each other, so **traffic between dev, stage and
prod is denied**. SSH is key-only (Ubuntu 24.04 default) and never open to
`0.0.0.0/0`. Servers use IMDSv2 and encrypted-in-transit package sources.
`c7i-flex.large` (CI/CD, 4 GiB) and `t3.small` (environments, 2 GiB + swap) are a first estimate; resize if Neo4j + Kafka need more.

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

---

# HU-01 - CI/CD Platform Bootstrap

Idempotent Bash scripts that configure **Jenkins, SonarQube + PostgreSQL, and Nexus Repository** using Docker Compose on the existing EC2 instances provisioned by TEC-04.

HU-01 does **not** provision new EC2 instances, deploy application environments (`dev`, `stage`, `prod`), implement Jenkins pipelines, configure Quality Gates, or publish Docker images.

## Service Topology

| Service | Port | Persistent Volumes | Health Check |
|:---|:---|:---|:---|
| Jenkins | 8080 | `circleguard_jenkins_home` | Container healthy; `/login` returns HTTP 200 |
| SonarQube + PostgreSQL | 9000 | `circleguard_sonar_data`, `circleguard_sonar_extensions`, `circleguard_sonar_logs`, `circleguard_sonar_postgresql` | SonarQube API returns `UP` |
| Nexus Repository | 8081 | `circleguard_nexus_data` | Web interface returns HTTP 200 |
| Nexus Docker Registry | 8082 | Uses Nexus persistent storage | `/v2/` returns HTTP 401 without authentication |

Nexus configures the `circleguard-docker` hosted Docker repository and the technical accounts `cg-publisher` and `cg-reader` with separate permissions.

Public IP addresses are retrieved using `bash infra/status.sh` and may change when EC2 instances are stopped and restarted.

## Prerequisites

- AWS CLI configured with an authorized IAM profile and permissions to describe EC2 instances.
- Scoped `ec2:AuthorizeSecurityGroupIngress` permissions for the CI/CD security group when internal connectivity rules must be configured.
- Existing Jenkins, SonarQube, and Nexus EC2 instances in the `running` state, with Docker, Docker Compose, and Python 3 available.
- An authorized SSH private key. Set `CIRCLEGUARD_SSH_KEY` when using a key different from `${KEY_DIR}/${KEY_NAME}.pem`.
- A valid `infra/config.env` containing non-secret infrastructure configuration.
- `JENKINS_TEACHER_USER` configured during the initial Jenkins installation when the teacher account does not exist.

AWS IAM, EC2 provisioning, and security groups are managed through TEC-04. Do not start `dev`, `stage`, or `prod` to validate HU-01.

## Usage (from the repository root)

Configure the local AWS and SSH environment:

```bash
export AWS_PROFILE=circleguard
export CIRCLEGUARD_SSH_KEY="$HOME/.ssh/id_ed25519"

eval "$(ssh-agent -s)"
ssh-add "$CIRCLEGUARD_SSH_KEY"

aws sts get-caller-identity
bash infra/status.sh
```

Replace the AWS profile and SSH key path with the operator's authorized configuration.

### Initial Bootstrap

Run the unified bootstrap only during initial setup or when authorized configuration changes are required:

```bash
export JENKINS_TEACHER_USER=teacher

bash infra/bootstrap-cicd.sh
bash infra/bootstrap-verify.sh
```

`bootstrap-cicd.sh` executes the following scripts in order:

1. `bootstrap-connectivity.sh`
2. `bootstrap-jenkins.sh`
3. `bootstrap-sonarqube.sh`
4. `bootstrap-nexus.sh`

Existing credentials, accounts, repositories, and persistent volumes are preserved during subsequent executions.

The individual bootstrap scripts can also be executed separately for troubleshooting.

### Quick Verification

For an existing installation, **do not reinstall the services**.

With the three EC2 instances running and SSH connectivity available:

```bash
bash infra/bootstrap-verify.sh
```

Expected results:

- Jenkins reports `healthy`.
- SonarQube and PostgreSQL are running.
- Nexus is running.
- Docker Registry returns HTTP 401 without authentication.
- The verification script exits with code `0`.

An HTTP 401 response from the Docker Registry is expected because anonymous access is disabled.

This verification checks the services remotely through SSH. External browser access also depends on the security group rules and the client's authorized network.

## Service Access and Security

| Service | URL |
|:---|:---|
| Jenkins | `http://<JENKINS_PUBLIC_IP>:8080/login` |
| SonarQube | `http://<SONARQUBE_PUBLIC_IP>:9000/` |
| Nexus Repository | `http://<NEXUS_PUBLIC_IP>:8081/` |
| Nexus Docker Registry | `<NEXUS_IP>:8082` |

The Jenkins teacher account must be able to access the dashboard without administrative privileges.

Credentials are stored exclusively on their respective EC2 instances:

| Service | Credentials File |
|:---|:---|
| Jenkins | `/opt/circleguard/jenkins/jenkins.secrets.env` |
| SonarQube | `/opt/circleguard/sonarqube/sonar.secrets.env` |
| Nexus | `/opt/circleguard/nexus/nexus.secrets.env` |

Credentials and private keys must never be committed, attached to Jira, included in pull requests, or displayed in evidence screenshots.

Docker Compose runs with the required privileges because the remote configuration directories under `/opt/circleguard/` have restricted ownership.

The Nexus Docker Registry uses an HTTP connector restricted through AWS security groups for the laboratory environment. Remote Docker clients require a properly secured connection, preferably verified TLS, before publishing images.

Docker image publication belongs to HU-03.

## Idempotency and Persistence

HU-01 was validated on November 7, 2026, using two successful executions of the unified bootstrap.

The validation confirmed:

- All three services remained operational.
- The verification script completed with `EXIT_CODE=0`.
- Jenkins, SonarQube, and Nexus credentials remained unchanged.
- Four Docker containers remained available without duplicates.
- Six persistent Docker volumes remained available.
- The Jenkins teacher account could access the dashboard without administrative privileges from the validation network.

The teacher's access from their own authorized network must be confirmed separately when required for acceptance.

The bootstrap does not need to be executed again during an ordinary pull request review. The original idempotency results are documented in evidence `HU01_06` and `HU01_07`.

## Troubleshooting

| Issue | Resolution |
|:---|:---|
| `Unable to locate credentials` | Select the authorized AWS profile using `AWS_PROFILE` and verify with `aws sts get-caller-identity`. |
| `Permission denied (publickey)` | Check `CIRCLEGUARD_SSH_KEY`, the SSH agent, key authorization, and network access. |
| `AccessDenied` for `ec2:AuthorizeSecurityGroupIngress` | Request scoped security group permissions from the TEC-04 owner. |
| Docker Compose permission errors | Verify privileged execution in the root-owned `/opt/circleguard/` directories. |
| SonarQube password validation failure | Ensure generated passwords satisfy SonarQube complexity requirements. |
| Git Bash closes during bootstrap | Redirect output to a local log file and inspect it before retrying. |
| Docker Registry returns HTTP 401 | Expected behavior without authentication. |

For bootstrap logging:

```bash
bash infra/bootstrap-cicd.sh > "$HOME/hu01-bootstrap.log" 2>&1
```

Do not rerun a potentially interrupted bootstrap without first checking its log.

If Nexus requires license acceptance or initial onboarding, an authorized operator must complete those steps through the web interface before repeating the Nexus bootstrap.

## Cost Control and Restrictions

After verification, coordinate with TEC-04 and the development team before stopping the EC2 instances.

When authorized and permitted:

```bash
bash infra/status.sh
bash infra/power.sh stop jenkins sonarqube nexus
bash infra/status.sh
```

Stopping EC2 instances reduces compute costs, but EBS volumes and other AWS resources may continue generating charges.

Do **not** execute the following commands to validate HU-01:

- `infra/bootstrap-instances.sh`
- `infra/teardown.sh`
- `docker compose down -v`
- `docker volume rm`
- `docker volume prune`

These operations may provision additional infrastructure or remove persistent data.

## Acceptance Criteria (HU-01)

| Criterion | Evidence |
|:---|:---|
| CA-01: Docker Compose bootstrap scripts are versioned | `infra/bootstrap-*.sh` and this README |
| CA-02: Bootstrap is idempotent and preserves configuration | `HU01_06`, `HU01_07` |
| CA-03: Services are accessible and the teacher has restricted Jenkins access | `HU01_01` through `HU01_05`; authorized network verification when required |
| CA-04: No real credentials are committed | Repository security review; `infra/config.env` contains only non-secret infrastructure parameters |

The formal completion of HU-01 requires pull request review and approval according to the team's development workflow.

HU-04 covers Jenkins pipelines, HU-05 covers SonarQube Quality Gates, and HU-03 covers Docker image publication to Nexus.
