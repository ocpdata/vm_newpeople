# vm_newpeople

Infraestructura y despliegue para publicar NewPeople en una VM de AWS usando Terraform y GitHub Actions.

## Alcance

Este repositorio administra solo el host de aplicacion:

- EC2 con IP publica dentro de una VPC y subnet existentes
- Security Group publico en `22`, `80` y `443`
- bootstrap base del sistema con Nginx, Node.js 20 y usuario `deployer`
- workflow de despliegue de la aplicacion `ocpdata/newpeople`

Quedan fuera del alcance de Terraform en este repositorio:

- RDS MySQL
- bucket S3 de documentos

## Estructura

```text
terraform/                 Stack principal de Terraform
scripts/                   Scripts usados por el workflow de despliegue
.github/workflows/         Workflows `infra-vm` y `destroy-vm`
```

## Workflows

### `infra-vm`

Hace `plan`, `apply` y despliegue de aplicacion en una sola ejecucion manual por `workflow_dispatch`.

### `destroy-vm`

Hace `terraform destroy` manual sobre el mismo workspace de Terraform Cloud para eliminar la infraestructura de la VM.

Usa estas variables/secrets:

- Variables: `AWS_REGION`, `TFC_ORG`, `TFC_WORKSPACE`, `VPC_ID`, `SUBNET_ID`
- Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TFC_TOKEN`, `SSH_PUBLIC_KEY`

Variables y secrets esperados para runtime:

- App: `PORT`, `JWT_EXPIRES_IN`, `APP_INVITE_SETUP_URL`, `VITE_API_URL`
- Secrets: `JWT_SECRET`
- DB: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_POOL_SIZE`, `DB_USER`, `DB_PASSWORD`
- SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM`, `SMTP_USER`, `SMTP_PASS`
- OpenAI: `OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_ENABLE_WEB_SEARCH`, `OPENAI_API_KEY`
- Storage: `DOCUMENT_STORAGE_PROVIDER`, `DOCUMENT_STORAGE_LOCAL_ROOT`, `DOCUMENT_STORAGE_S3_BUCKET`, `DOCUMENT_STORAGE_S3_REGION`, `DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE`, `DOCUMENT_STORAGE_S3_ENDPOINT`, `DOCUMENT_STORAGE_S3_ACCESS_KEY_ID`, `DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY`
- SSH: `SSH_PRIVATE_KEY`

## Flujo recomendado

1. Ejecutar `infra-vm` manualmente indicando el `app_ref` que quieres desplegar.
2. El workflow hace `terraform plan` y `terraform apply`.
3. Luego construye y despliega `ocpdata/newpeople` sobre la VM.
4. Verificar `http://<ip-publica>/health`.
5. Cuando quieras desmontar el entorno, ejecutar `destroy-vm` manualmente.

## Notas operativas

- `DOCUMENT_STORAGE_S3_ENDPOINT` puede quedar vacio para S3 nativo de AWS.
- `JWT_SECRET` debe vivir en GitHub Secrets y no debe usar valores de ejemplo.
- El workflow asume que `ocpdata/newpeople` es accesible desde GitHub Actions.
