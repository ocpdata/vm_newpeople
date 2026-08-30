# vm_newpeople

Infraestructura y despliegue de NewPeople en AWS con Terraform y GitHub Actions.

## Alcance

Este repositorio administra:

- VPC con una subnet publica y dos subnets privadas en zonas distintas.
- VM EC2 Ubuntu con Elastic IP.
- RDS MySQL en las subnets privadas.
- Security Groups para trafico web y acceso MySQL desde la VM.
- Bootstrap base de la VM (Nginx, Node.js 20, usuario deployer).
- Despliegue remoto de la aplicacion ocpdata/newpeople por workflow.

Fuera de alcance:

- Provisionamiento de bucket S3 de documentos.
- Codigo fuente de la aplicacion NewPeople (vive en otro repositorio).

## Estructura

```text
terraform/                 Stack de infraestructura
scripts/                   Scripts de render y despliegue remoto
.github/workflows/         infra-vm y destroy-environment
```

## Workflows

### infra-vm

Workflow manual (workflow_dispatch) que ejecuta en cadena:

1. plan
2. apply
3. deploy

Inputs:

- app_repository: repo de aplicacion a desplegar (default ocpdata/newpeople).
- app_ref: branch, tag o SHA a desplegar (default main).

Comportamiento relevante:

- El checkout de aplicacion usa exactamente app_ref.
- La build web se ejecuta en GitHub Actions y luego se empaqueta release tar.gz.
- DB_HOST se obtiene de terraform output y se inyecta al runtime env.
- El despliegue remoto crea un release versionado en /var/app/newpeople/releases/<release_id> y actualiza /var/app/newpeople/current.
- Se levanta servicio systemd newpeople-api y Nginx sirve apps/web/dist.
- Healthcheck final externo: http://<VM_HOST>/health.

### destroy-environment

Workflow manual que elimina solamente la VM EC2 y su Elastic IP. Conserva VPC, subnets, Security Groups y RDS.

Validaciones obligatorias:

- confirmation debe ser DELETE_VM.
- terraform_workspace debe coincidir exactamente con vars.TFC_WORKSPACE.
  Si no coinciden, el job falla de forma segura sin destruir recursos.

## Variables y secretos

Infraestructura (plan/apply/destroy):

- Variables generales: AWS_REGION, TFC_ORG, TFC_WORKSPACE, INSTANCE_TYPE.
- Variables de red: VPC_CIDR=`10.90.0.0/16`, PUBLIC_SUBNET_CIDR=`10.90.1.0/24`, PRIVATE_SUBNET_1_CIDR=`10.90.10.0/24`, PRIVATE_SUBNET_2_CIDR=`10.90.20.0/24`.
- Variables RDS: DB_INSTANCE_CLASS=`db.t4g.micro`, DB_ALLOCATED_STORAGE, DB_ENGINE_VERSION=`8.4.8`, DB_NAME=`newpeople_crm_dev`, DB_PORT, DB_MULTI_AZ, DB_PUBLICLY_ACCESSIBLE, DB_DELETION_PROTECTION=`false`, DB_SKIP_FINAL_SNAPSHOT=`true`.
- Secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, TFC_TOKEN, SSH_KEY_PEM, DB_USER, DB_PASSWORD.

Terraform crea la VPC, subnets y RDS cuando no existen y los reutiliza en las siguientes ejecuciones mediante el mismo estado de TFC_WORKSPACE. RDS usa `prevent_destroy`, por lo que cualquier plan que intente eliminarla o reemplazarla falla antes de aplicar cambios. SSH_KEY_PEM contiene el archivo PEM completo; el workflow deriva de el la clave publica que instala en la VM.

Runtime de aplicacion (deploy):

- App: PORT, JWT_EXPIRES_IN, APP_BASE_URL, APP_INVITE_SETUP_URL, VITE_API_URL, AUTH_GOOGLE_ENABLED.
- Secrets app: JWT_SECRET.
- DB: DB_PORT, DB_NAME, DB_POOL_SIZE, DB_USER, DB_PASSWORD (DB_HOST se resuelve desde Terraform).
- SMTP: SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_FROM, SMTP_USER, SMTP_PASS.
- OpenAI: OPENAI_MODEL, OPENAI_BASE_URL, OPENAI_ENABLE_WEB_SEARCH, OPENAI_API_KEY.
- Storage local: DOCUMENT_STORAGE_PROVIDER=local y DOCUMENT_STORAGE_LOCAL_ROOT.
- Storage S3/S3-compatible: DOCUMENT_STORAGE_PROVIDER=s3 o s3_compatible, DOCUMENT_STORAGE_S3_BUCKET, DOCUMENT_STORAGE_S3_REGION, DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE, DOCUMENT_STORAGE_S3_ACCESS_KEY_ID, DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY, opcional DOCUMENT_STORAGE_S3_ENDPOINT.
- OAuth Google (solo si AUTH_GOOGLE_ENABLED=true): GOOGLE_CLIENT_ID, GOOGLE_REDIRECT_URI, GOOGLE_CLIENT_SECRET.
- Secret de acceso VM desde Actions: SSH_KEY_PEM.

## Flujo operativo recomendado

1. Lanzar infra-vm indicando app_ref exacto (idealmente SHA completo).
2. Verificar en logs del step Checkout application repository que ref y SHA sean los esperados.
3. Tomar VM_HOST desde logs (Show public IP).
4. Validar salud en http://<VM_HOST>/health.
5. Validar funcionalidad de la app en la URL publicada.

## Detalles tecnicos de despliegue remoto

El script remoto:

- Instala dependencias npm del release.
- Instala Chromium y sus dependencias Linux.
- Ejecuta la API dentro de Xvfb para las pruebas de Bot Defense.
- Instala k6 para ejecutar las fases controladas de las pruebas DoS L7 desde la VM.
- Si la tabla users no existe, aplica apps/api/sql/schema.sql automaticamente una sola vez.
- Si el esquema ya existe, conserva los datos y solo aplica compatibilidad con tablas de propuestas.
- Configura systemd para API y Nginx para frontend + proxy /api.
- Reinicia servicios y valida healthcheck local antes de salir.

## Notas actuales de versionado y diagnostico

- El estado funcional visible depende del app_ref desplegado.
- Si se usa app_ref=main, el resultado depende del HEAD vigente al momento de la corrida.
- Para auditoria, el origen real de version se confirma en logs del checkout de aplicacion (ref y git log -1).
- Diferencias entre dominio publico e IP de VM pueden provenir de DNS/proxy delante de la instancia.

## Buenas practicas

- Usar SHA fijo de app_ref para despliegues reproducibles.
- Para eliminar RDS deliberadamente se debe retirar primero `prevent_destroy` mediante un cambio de codigo revisado.
- No reutilizar secretos de ejemplo en produccion.
- Verificar que VITE_API_URL y APP_BASE_URL correspondan al endpoint expuesto al usuario final.
- `DOCUMENT_STORAGE_S3_ENDPOINT` puede quedar vacio para S3 nativo de AWS.
- El workflow asume que `ocpdata/newpeople` es accesible desde GitHub Actions.
