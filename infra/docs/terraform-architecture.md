# Diagramas de la infraestructura como código (HU-10)

Diagramas de la infraestructura que describen los módulos y ambientes de
[`infra/terraform`](../terraform/README.md). Están escritos en Mermaid, así que
GitHub los dibuja directamente al abrir este archivo.

## 1. Arquitectura de un ambiente

Lo que crea cada ambiente (`dev`, `stage` o `prod`) en AWS. El número de agentes
cambia por ambiente: 0 en `dev`, 1 en `stage` y 2 en `prod`.

```mermaid
flowchart TB
    user(["Usuarios y equipo"])

    subgraph aws["Cuenta AWS, us-east-1"]
        subgraph vpc["VPC del ambiente"]
            igw["Internet Gateway"]
            subgraph subnets["Subredes públicas en 2 zonas de disponibilidad"]
                sg{{"Security group del clúster<br/>80 y 443 públicos<br/>22 y 6443 solo admin_cidrs<br/>tráfico libre entre nodos"}}
                server["EC2 servidor k3s<br/>disco cifrado, IMDSv2"]
                agents["EC2 agentes k3s<br/>0 a 2 según el ambiente"]
            end
        end

        ssm[("SSM Parameter Store<br/>token del clúster, SecureString")]
        iam["Rol IAM del nodo<br/>lee solo el token"]
        ecr[("ECR<br/>un repositorio por servicio, 8 en total")]
        s3[("S3 de artefactos<br/>privado, cifrado, versionado")]
        logs["CloudWatch Logs<br/>un grupo por servicio"]
        alarms["Alarmas de CPU<br/>una por nodo"]
        sns["Tema SNS de alarmas"]
    end

    user -->|"HTTP y HTTPS"| igw
    igw --> sg
    sg --> server
    sg --> agents
    server <-->|"red del clúster"| agents
    iam -.->|"asumido por"| server
    iam -.->|"asumido por"| agents
    iam -->|"GetParameter"| ssm
    alarms -->|"CPUUtilization"| server
    alarms -->|"CPUUtilization"| agents
    alarms --> sns
    sns -->|"correo opcional"| user
```

Los repositorios ECR, el bucket y los grupos de logs no dependen de la red: son
recursos regionales que el ambiente crea junto al clúster.

## 2. Módulos y ambientes

Cada ambiente es una configuración raíz que llama a los mismos cinco módulos.
Las flechas de un módulo a otro son datos que pasa el ambiente.

```mermaid
flowchart LR
    subgraph env["Ambiente: dev, stage o prod"]
        direction LR
        network["modules/network<br/>VPC, subredes y security group"]
        compute["modules/compute<br/>servidor y agentes k3s"]
        registry["modules/registry<br/>repositorios ECR"]
        storage["modules/storage<br/>bucket de artefactos"]
        observability["modules/observability<br/>logs, alarmas y SNS"]
    end

    network -->|"subnet_ids y security_group_id"| compute
    compute -->|"ids de los nodos, una alarma por nodo"| observability
    vars["variables.tf<br/>dimensionamiento del ambiente"] --> env
    tfvars["terraform.tfvars<br/>IPs de administración, llave SSH, correo<br/>git lo ignora"] --> env
```

`registry` y `storage` no reciben datos de otros módulos. `observability` recibe
los identificadores de los nodos de `compute` y la lista de servicios.

## 3. Estado remoto

El backend se crea una vez con `bootstrap` y después lo usan los tres ambientes,
cada uno con su propia llave.

```mermaid
flowchart TB
    subgraph once["Una sola vez: infra/terraform/bootstrap"]
        direction LR
        boot["terraform apply<br/>con estado local"]
        bucket[("Bucket S3 del estado<br/>privado, cifrado, versionado, solo TLS")]
        lock[("Tabla DynamoDB de bloqueo<br/>llave LockID")]
        boot --> bucket
        boot --> lock
        boot -.->|"terraform init -migrate-state"| bootkey["bootstrap/terraform.tfstate"]
    end

    subgraph envs["Cada ambiente: infra/terraform/environments"]
        direction LR
        dev["dev"]
        stage["stage"]
        prod["prod"]
    end

    subgraph keys["Objetos dentro del mismo bucket"]
        direction LR
        kdev["dev/terraform.tfstate"]
        kstage["stage/terraform.tfstate"]
        kprod["prod/terraform.tfstate"]
    end

    dev -->|"lee y escribe"| kdev
    stage -->|"lee y escribe"| kstage
    prod -->|"lee y escribe"| kprod
    dev -.->|"bloquea en plan y apply"| lock
    stage -.->|"bloquea en plan y apply"| lock
    prod -.->|"bloquea en plan y apply"| lock
    kdev --- bucket
    kstage --- bucket
    kprod --- bucket
    bootkey --- bucket
```

Secuencia de un `terraform apply` en un ambiente, y por qué dos personas no
pueden cambiar el mismo ambiente a la vez:

```mermaid
sequenceDiagram
    actor A as Persona A
    actor B as Persona B
    participant T as Terraform
    participant L as DynamoDB, bloqueo
    participant S as S3, estado

    A->>T: terraform apply en dev
    T->>L: crear LockID de dev
    L-->>T: bloqueo concedido
    T->>S: leer dev/terraform.tfstate
    B->>T: terraform apply en dev
    T->>L: crear LockID de dev
    L-->>T: ya existe, error de bloqueo
    T-->>B: espera o falla sin cambiar nada
    T->>S: escribir nuevo estado, nueva versión
    T->>L: liberar el bloqueo
    T-->>A: apply terminado
```

Cada escritura crea una versión nueva del objeto de estado, y las versiones
anteriores se conservan 90 días para poder deshacer un cambio equivocado.

## 4. Redes por ambiente

Los rangos no se solapan, de modo que los ambientes podrían conectarse entre sí
más adelante si hiciera falta.

```mermaid
flowchart LR
    subgraph d["dev: 10.0.0.0/16"]
        d1["10.0.1.0/24, us-east-1a"]
        d2["10.0.2.0/24, us-east-1b"]
    end
    subgraph s["stage: 10.1.0.0/16"]
        s1["10.1.1.0/24, us-east-1a"]
        s2["10.1.2.0/24, us-east-1b"]
    end
    subgraph p["prod: 10.2.0.0/16"]
        p1["10.2.1.0/24, us-east-1a"]
        p2["10.2.2.0/24, us-east-1b"]
    end
```

## Referencias

- Módulos: [`infra/terraform/modules`](../terraform/modules)
- Backend remoto: [`infra/terraform/bootstrap`](../terraform/bootstrap/README.md)
- Ambientes: `infra/terraform/environments`
