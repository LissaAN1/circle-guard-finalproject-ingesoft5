# Cost estimate and shutdown procedure (TEC-04)

Prices are **us-east-1 on-demand estimates** (USD). Confirm them with the
[AWS Pricing Calculator](https://calculator.aws/) before relying on them;
the "real" column must be filled from AWS Billing after the Sprint 1 run.

| Item | Unit price | Qty | Per hour | 
|:---|---:|---:|---:|
| EC2 `t3.medium` (jenkins, sonarqube, nexus, dev, stage, prod) | 0.0416 | 6 | 0.2496 |
| Public IPv4 address (while running) | 0.005 | 6 | 0.0300 |
| **Compute + IPv4 while running** | | | **0.2796** |

| Storage (gp3, 0.08 USD/GB-month, billed even when stopped) | GB |
|:---|---:|
| jenkins 30, sonarqube 30, nexus 50, dev 30, stage 30, prod 30 | 200 → **16.0 USD/month** |

| Usage scenario | Hours/month | Compute+IPv4 | EBS | Total/month |
|:---|---:|---:|---:|---:|
| Always on (24/7) | 720 | 201.3 | 16.0 | **~217** (exceeds credits) |
| Working hours (8 h x 22 days) | 176 | 49.2 | 16.0 | **~65** |
| Everything stopped | 0 | 0 | 16.0 | **~16** |

Available credits when this was written: 117.17 USD (valid until 2027-03-11).
**Rule: servers are stopped whenever nobody is using them.**

| Real cost (fill in) | Date | Amount (USD) | Source |
|:---|:---|---:|:---|
| End of Sprint 1 | | | Billing > Bills |

## Shutdown procedure

```bash
infra/power.sh stop            # stop all servers (compute billing stops, EBS stays)
infra/power.sh start nexus     # start one server; public IPs change on start
infra/status.sh                # current state and addresses
infra/teardown.sh --yes        # DESTROYS servers and security groups (end of project)
```

* `stop` keeps disks and data; only EBS (~16 USD/month) is billed.
* `terminate` (teardown) deletes servers and disks; Nexus/Jenkins data is lost.
* Public IPs change after stop/start. Tools must reach each other through the
  current address (or private IPs inside the VPC); update the Jenkins/Nexus
  URLs after a restart, or move to Elastic IPs (0.005 USD/h each) later.
* A monthly budget with e-mail alerts at 50/80/100 % is created by
  `infra/create-budget.sh <email> [usd]`.
