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
.github/workflows/         Workflows `infra-vm` y `deploy-app`
```

## Workflows

### `infra-vm`

Hace plan sobre cambios en `main` y permite `apply` manual con `workflow_dispatch`.

Usa estas variables/secrets:

- Variables: `AWS_REGION`, `TFC_ORG`, `TFC_WORKSPACE`, `VPC_ID`, `SUBNET_ID`
- Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TFC_TOKEN`, `SSH_PUBLIC_KEY`

### `deploy-app`

Hace checkout del repo `ocpdata/newpeople`, construye el frontend, empaqueta el release, lo copia por SSH a la VM y activa la aplicacion.

Variables y secrets esperados para runtime:

- App: `PORT`, `JWT_EXPIRES_IN`, `APP_INVITE_SETUP_URL`, `VITE_API_URL`
- Secrets: `JWT_SECRET`
- DB: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_POOL_SIZE`, `DB_USER`, `DB_PASSWORD`
- SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM`, `SMTP_USER`, `SMTP_PASS`
- OpenAI: `OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_ENABLE_WEB_SEARCH`, `OPENAI_API_KEY`
- Storage: `DOCUMENT_STORAGE_PROVIDER`, `DOCUMENT_STORAGE_LOCAL_ROOT`, `DOCUMENT_STORAGE_S3_BUCKET`, `DOCUMENT_STORAGE_S3_REGION`, `DOCUMENT_STORAGE_S3_FORCE_PATH_STYLE`, `DOCUMENT_STORAGE_S3_ENDPOINT`, `DOCUMENT_STORAGE_S3_ACCESS_KEY_ID`, `DOCUMENT_STORAGE_S3_SECRET_ACCESS_KEY`
- SSH: `SSH_PRIVATE_KEY`

## Flujo recomendado

1. Ejecutar `infra-vm` con `apply=true` para crear la VM.
2. Confirmar que la salida `public_ip` responde por SSH.
3. Ejecutar `deploy-app` indicando el `app_ref` que quieres desplegar.
4. Verificar `http://<ip-publica>/health`.

## Notas operativas

- `DOCUMENT_STORAGE_S3_ENDPOINT` puede quedar vacio para S3 nativo de AWS.
- `JWT_SECRET` debe vivir en GitHub Secrets y no debe usar valores de ejemplo.
- El workflow asume que `ocpdata/newpeople` es accesible desde GitHub Actions.