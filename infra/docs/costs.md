# Cost estimate and shutdown procedure (TEC-04)

Prices are **us-east-1 on-demand estimates** (USD). Confirm them with the
[AWS Pricing Calculator](https://calculator.aws/) before relying on them;
the "real" column must be filled from AWS Billing after the Sprint 1 run.

| Item | Unit price | Qty | Per hour |
|:---|---:|---:|---:|
| EC2 `c7i-flex.large` (jenkins, sonarqube, nexus) | 0.0848 | 3 | 0.2544 |
| EC2 `t3.small` (dev, stage, prod) | 0.0208 | 3 | 0.0624 |
| Public IPv4 address (while running) | 0.005 | 6 | 0.0300 |
| **Compute + IPv4 while running** | | | **0.3468** |

`c7i-flex.large` is eligible for the AWS free plan (covered by credits); its
list price above is an estimate to confirm in the calculator.

| Storage (gp3, 0.08 USD/GB-month, billed even when stopped) | GB |
|:---|---:|
| jenkins 30, sonarqube 30, nexus 50, dev 30, stage 30, prod 30 | 200 -> **16.0 USD/month** |

| Usage scenario | Hours/month | Compute+IPv4 | EBS | Total/month |
|:---|---:|---:|---:|---:|
| Always on (24/7) | 720 | 249.7 | 16.0 | **~266** (exceeds credits) |
| Working hours (8 h x 22 days) | 176 | 61.0 | 16.0 | **~77** |
| Everything stopped | 0 | 0 | 16.0 | **~16** |

Available credits when this was written: 117.17 USD (valid until 2027-03-11).
**Rule: servers are stopped whenever nobody is using them.**

| Real cost (fill in) | Date | Amount (USD) | Source |
|:---|:---|---:|:---|
| End of Sprint 1 | | | Billing > Bills |
| Sprint 0 (servers launched 2026-11-02, stopped same day) | 2026-11-02 | pending | Billing > Bills |

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

---

## Actualización de capacidad y estimación — HU-02 (2026-11-08)

Esta sección **complementa y conserva** la estimación original de TEC-04 anterior. Durante la validación real de HU-02 se amplió `dev`, `stage` y `prod` de `t3.small` (2 GiB) a `m7i-flex.large` (8 GiB), porque la pila de doce contenedores requiere más memoria. Los tres servidores de CI/CD mantienen `c7i-flex.large` (4 GiB). No se crearon instancias adicionales.

Los siguientes valores son **estimaciones de tarifa pública Linux On-Demand en us-east-1**, no cargos reales ni promesa de gratuidad; verificar precios finales, descuentos/créditos y facturación en AWS Billing/Pricing Calculator. Se conserva el supuesto histórico de seis IPv4 públicas facturadas solamente durante las horas encendidas, a USD 0.005/h cada una, y EBS gp3 por 200 GiB a USD 0.08/GiB-mes.

| Concepto | Precio USD/h | Cantidad | Total USD/h |
|:---|---:|---:|---:|
| EC2 `c7i-flex.large` — Jenkins, SonarQube, Nexus | 0.0848 | 3 | 0.2544 |
| EC2 `m7i-flex.large` — dev, stage, prod | 0.0958 | 3 | 0.2874 |
| IPv4 públicas (supuesto histórico) | 0.0050 | 6 | 0.0300 |
| **Total con las seis EC2 encendidas** | | | **0.5718** |

| Escenario de referencia | Horas por instancia/mes | Compute + IPv4 (USD) | EBS (USD) | Total estimado (USD/mes) |
|:---|---:|---:|---:|---:|
| Seis instancias encendidas 24/7 | 720 | 411.70 | 16.00 | **427.70** |
| Seis instancias encendidas 8 h × 22 días | 176 | 100.64 | 16.00 | **116.64** |
| Todas las EC2 detenidas | 0 | 0.00 | 16.00 | **16.00** |

**Comparación histórica:** la estimación original de TEC-04 era USD 0.3468/h con tres `t3.small`; la nueva estimación es USD 0.5718/h, una diferencia de **USD 0.2250/h** (+64.9 %), cuando las seis instancias y seis IPv4 están en uso. Los importes históricos se mantienen arriba para permitir auditoría de la decisión de ampliación.

**Alcance de los importes:** estimación de EC2, IPv4 pública y EBS base. No incluyen transferencia de datos, snapshots, impuestos, eventuales EBS adicionales, otros recursos ni diferencias de facturación por IP. El volumen real de discos debe corroborarse contra AWS. El escenario "detenido" supone que no existen Elastic IPs u otras IPv4 públicas retenidas con cargos adicionales.

**Ejecución HU-02 (2026-11-08):** despliegues reales en dev, stage y prod con aplicaciones saludables y las mismas seis imágenes publicadas en Nexus; instancias ampliadas a `m7i-flex.large`. El costo real de las horas utilizadas se debe tomar de AWS Billing/Cost Explorer, no estimarse como consumo efectivamente facturado.

**Control de gastos:** detener `dev`, `stage`, `prod` y `nexus` al finalizar el trabajo, coordinando con el equipo. Jenkins y SonarQube se mantienen detenidas cuando no se usan. EBS permanece y se factura aun con EC2 detenida. La restauración de instancias puede cambiar sus IP públicas; Nexus mantiene su IP privada dentro de la VPC mientras conserve la interfaz correspondiente.

**Referencias consultadas:** AWS Pricing Calculator (https://calculator.aws/); precios públicos de `m7i-flex.large` en us-east-1 (https://www.economize.cloud/resources/aws/pricing/ec2/m7i-flex.large/) y de `c7i-flex.large` (https://www.economize.cloud/resources/aws/pricing/ec2/c7i-flex.large/). Consulta del 2026-11-08.
---

## Parte 2: arquitectura Terraform y K3s (actualización de TEC-11, 2026-11-22)

Las dos secciones anteriores son **estimaciones de la Parte 1** (TEC-04 y HU-02) y se conservan sin cambios como
antecedente histórico. Su tabla «Real cost (fill in)» no se completó durante la Parte 1.

La Parte 2 agregó seis nodos K3s `m7i-flex.large` creados con Terraform (1 en dev, 2 en stage y 3 en prod) y 240 GB de
EBS, sin borrar las seis EC2 de la Parte 1. La estimación actualizada, el gasto real registrado en Cost Explorer y la
comparación entre ambos están en [`docs/costos/costos-parte-2.md`](../../docs/costos/costos-parte-2.md). Resumen:

| Concepto | Parte 1 (estimado) | Parte 2 (estimado) | Real |
|:---|---:|---:|---:|
| USD por hora con lo que se puede encender a la vez | 0,5718 (6 EC2) | 0,7842 (Jenkins, Nexus y 6 nodos; límite de 16 vCPU) | — |
| USD por mes en horario laboral (8 h × 22 días) | 116,64 | 173,22 | — |
| USD por mes con todo detenido (EBS) | 16,00 | 35,20 | — |
| Gasto bruto del 1 al 20 de noviembre de 2026 | — | — | 27,45 (cubierto por créditos; neto 0,00) |

Los presupuestos por ambiente y la escala a cero de los nodos (HU-25) están en
[`docs/costos/hu-25-finops.md`](../../docs/costos/hu-25-finops.md).
