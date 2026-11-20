# HU-25: FinOps (bonificación de la Parte 2)

Cubre los tres criterios de aceptación de la historia: reporte de costos por ambiente, presupuesto con alerta y
escala a cero de dev y stage cuando no se usan. Todo usa servicios sin costo adicional (Budgets sin acciones,
EventBridge Scheduler y etiquetas de costos); lo único que cobra es la API de Cost Explorer, 0,01 USD por consulta.

## 1. Dónde está el gasto

Gasto real de noviembre (1 al 20), tomado de Cost Explorer sin créditos:

| Servicio | USD |
|:---|---:|
| EC2, cómputo | 15,43 |
| EC2 - Other (discos EBS, IPs públicas, transferencia) | 10,84 |
| VPC | 1,18 |
| **Total bruto** | **27,45** |

Los créditos de AWS cubren todo, así que el neto cobrado es 0. Por eso el presupuesto mide el gasto **bruto**: con
los créditos dentro, el neto queda en cero mientras duren y ninguna alerta se dispararía nunca.

El cómputo es el 56 % del gasto y el único que se puede apagar. Los discos y las IPs siguen cobrando con las
instancias detenidas (unos 0,59 USD diarios de piso fijo).

## 2. Reporte de costos por ambiente (criterio 1)

Los recursos ya llevan la etiqueta `Environment` (`dev`, `stage`, `prod`) por `default_tags` de cada ambiente.
Para que Cost Explorer pueda separar por ella hay que **activarla como etiqueta de asignación de costos** en
Billing. Se activó `Environment` y `Project` el 20 de noviembre de 2026; AWS no aplica la etiqueta hacia atrás,
así que el gasto anterior aparece como "sin etiqueta" y el desglose por ambiente empieza desde esa fecha.

```bash
python infra/finops/cost_report.py --start 2026-11-01 --end 2026-11-21 --profile circleguard \
  > docs/costos/reporte-2026-11-20.md
```

El script hace tres consultas a Cost Explorer (unos 0,03 USD por ejecución): gasto bruto por etiqueta, gasto bruto
por servicio y créditos. El primer reporte está en [`reporte-2026-11-20.md`](reporte-2026-11-20.md).

## 3. Presupuesto con alerta (criterio 2)

El módulo [`infra/terraform/modules/finops`](../../infra/terraform/modules/finops) crea un presupuesto mensual por
ambiente, filtrado por la etiqueta `Environment`:

| Ambiente | Tope mensual |
|:---|---:|
| dev | 40 USD |
| stage | 40 USD |
| prod | 80 USD |

Avisa por correo cuando el gasto real pasa del 50 %, 80 % y 100 %, y cuando el pronóstico del mes supera el 100 %.
Los correos salen de `alarm_email` del `terraform.tfvars` de cada ambiente, que git ignora. Con `alarm_email`
vacío el presupuesto se crea sin notificaciones. La cuenta ya tenía `circleguard-monthly` (50 USD en total, de la
Parte 1); los presupuestos por ambiente lo complementan.

## 4. Escala a cero de dev y stage (criterio 3)

El HPA de Kubernetes no puede bajar de una réplica, y apagar los pods no ahorra nada mientras los nodos sigan
encendidos: el costo está en las instancias EC2. Por eso la escala a cero se hace en los nodos.
EventBridge Scheduler detiene los nodos de dev y stage a las **20:00** todos los días y los enciende a las
**07:00** de lunes a viernes (hora de Bogotá), con lo que los fines de semana quedan apagados. **Prod no se toca**:
el módulo rechaza `scale_to_zero_enabled = true` en ese ambiente.

- Un rol de IAM dedicado solo puede detener e iniciar los nodos de su ambiente.
- `scale_to_zero_enabled = false` en el `tfvars` desactiva el horario, por ejemplo cuando alguien prueba de noche.
- El horario se cambia con `stop_schedule` y `start_schedule`.

Al encender un nodo cambia su IP pública. Jenkins debe usar las IP privadas por el peering, y los kubeconfig locales
necesitan actualizar la línea `server:`. Tras un encendido k3s y los 15 workloads vuelven solos, como se comprobó en
la prueba de recuperación de la HU-10.

## 5. Ahorro estimado

Precio del nodo `m7i-flex.large` en us-east-1: 0,09576 USD por hora (API de precios de AWS).
`python infra/finops/savings.py` calcula lo siguiente:

| Ambiente | Nodos | Siempre encendido | Con horario | Ahorro | Discos (fijo) |
|:---|---:|---:|---:|---:|---:|
| dev | 1 | 69,90 USD | 26,97 USD | 42,93 USD | 2,40 USD |
| stage | 2 | 139,81 USD | 53,94 USD | 85,86 USD | 4,80 USD |
| **Total** | | **209,71 USD** | **80,92 USD** | **128,80 USD** | **7,20 USD** |

Con el horario los nodos corren 282 horas al mes en lugar de 730: un **61 % menos de cómputo** en dev y stage.
Es un estimado frente a tener los ambientes siempre encendidos, no un ahorro ya medido en la factura. La medición
real sale del reporte por ambiente cuando haya semanas de datos con el horario activo.

## 6. Pruebas

- `terraform test` del módulo: 7 pruebas (filtro por etiqueta, créditos excluidos, notificaciones, horario y
  rechazo de prod).
- `python -m pytest infra/finops/tests`: 8 pruebas del cálculo de ahorro y del reporte, sin acceso a AWS.
- `terraform plan` real en stage: agrega solo el presupuesto, sin tocar los nodos.

## 7. Cómo apagar los ambientes para el cierre

Al terminar la evaluación el enunciado pide destruir los recursos de nube (`terraform destroy` en cada ambiente).
El horario solo reduce el gasto mientras los ambientes existen; no reemplaza ese paso.
