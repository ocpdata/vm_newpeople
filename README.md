# vm_newpeople

Infraestructura y despliegue para publicar NewPeople en AWS usando Terraform y GitHub Actions.

## Alcance

Este repositorio administra la infraestructura base del ambiente:

- EC2 con IP publica dentro de una VPC y subnet existentes
- RDS MySQL dentro de dos subnets existentes de la misma VPC
- Security Group publico en `22`, `80` y `443`
- Security Group privado para MySQL accesible solo desde la VM
- bootstrap base del sistema con Nginx, Node.js 20 y usuario `deployer`
- workflow de despliegue de la aplicacion `ocpdata/newpeople`

Quedan fuera del alcance de Terraform en este repositorio:

- bucket S3 de documentos

## Estructura

```text
terraform/                 Stack principal de Terraform
scripts/                   Scripts usados por el workflow de despliegue
.github/workflows/         Workflows `infra-vm` y `destroy-environment`
```

## Workflows

### `infra-vm`

Hace `plan`, `apply` y despliegue de aplicacion en una sola ejecucion manual por `workflow_dispatch`.

### `destroy-environment`

Hace `terraform destroy` manual sobre el mismo workspace de Terraform Cloud para eliminar toda la infraestructura del entorno, incluida la VM y la base RDS.

Usa estas variables/secrets de infraestructura:

- Variables: `AWS_REGION`, `TFC_ORG`, `TFC_WORKSPACE`, `VPC_ID`, `SUBNET_ID`, `INSTANCE_TYPE`
- Variables RDS: `DB_SUBNET_ID_1`, `DB_SUBNET_ID_2`, `DB_INSTANCE_CLASS`, `DB_ALLOCATED_STORAGE`, `DB_ENGINE_VERSION`, `DB_NAME`, `DB_PORT`, `DB_MULTI_AZ`, `DB_PUBLICLY_ACCESSIBLE`, `DB_DELETION_PROTECTION`, `DB_SKIP_FINAL_SNAPSHOT`
- Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TFC_TOKEN`, `SSH_PUBLIC_KEY`, `DB_USER`, `DB_PASSWORD`

Variables y secrets esperados para runtime:

- App: `PORT`, `JWT_EXPIRES_IN`, `APP_INVITE_SETUP_URL`, `VITE_API_URL`
- Secrets: `JWT_SECRET`
- DB: `DB_PORT`, `DB_NAME`, `DB_POOL_SIZE`, `DB_USER`, `DB_PASSWORD`
- SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM`, `SMTP_USER`, `SMTP_PASS`
- OpenAI: `OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_ENABLE_WEB_SEARCH`, `OPENAI_API_KEY`
- Storage: `DOCUMENT_STORAGE_PROVIDER`, `DOCUMENT_STORAGE_LOCAL_ROOT`, `DOCUMENT_STORAGE_S3_BUCKET`, `DOCUMENT_STORAGE_S3_REGION`, `DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE`, `DOCUMENT_STORAGE_S3_ENDPOINT`, `DOCUMENT_STORAGE_S3_ACCESS_KEY_ID`, `DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY`
- SSH: `SSH_PRIVATE_KEY`

## Flujo recomendado

1. Ejecutar `infra-vm` manualmente indicando el `app_ref` que quieres desplegar.
2. El workflow hace `terraform plan` y `terraform apply`.
3. Luego construye y despliega `ocpdata/newpeople` sobre la VM.
4. El workflow resuelve el endpoint de RDS desde Terraform y lo inyecta como `DB_HOST` en tiempo de despliegue.
5. Para una base nueva, ejecutar bootstrap de esquema una sola vez de forma manual en la VM:
   Comando: `sudo bash /var/app/newpeople/current/scripts/bootstrap_schema_manual.sh /var/app/newpeople/current /var/app/newpeople/shared/config/api.env`
   Este paso NO se ejecuta automaticamente durante deploys.
6. Verificar `http://<ip-publica>/health`.
7. Cuando quieras desmontar el entorno, ejecutar `destroy-environment` manualmente y confirmar el borrado del workspace y de la base RDS.

## Notas operativas

- `DOCUMENT_STORAGE_S3_ENDPOINT` puede quedar vacio para S3 nativo de AWS.
- `JWT_SECRET` debe vivir en GitHub Secrets y no debe usar valores de ejemplo.
- El workflow asume que `ocpdata/newpeople` es accesible desde GitHub Actions.
- El despliegue instala Chromium y sus dependencias Linux, y ejecuta la API dentro de Xvfb para que las pruebas de Bot Defense dispongan de un display virtual.
- El despliegue instala k6 para ejecutar las fases controladas de las pruebas DoS L7 desde la misma VM.
- Para que `destroy-vm` funcione sin pedir snapshot final, usa `DB_SKIP_FINAL_SNAPSHOT=true`.
- `scripts/deploy_remote.sh` no aplica `apps/api/sql/schema.sql`; el esquema se deja para aprovisionamiento inicial/manual.
