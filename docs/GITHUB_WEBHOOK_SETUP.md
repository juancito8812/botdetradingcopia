# Auto-Actualización por Webhook de GitHub

Este repositorio ahora soporta webhooks de push de GitHub en:

- `POST /api/webhooks/github`
- `GET /api/webhooks/github/health`

El endpoint del webhook verifica `X-Hub-Signature-256` con `HMAC-SHA256`.

## 1) Configurar Entorno

Establece esto en `.env` (o tu entorno de servicio):

```bash
FORVEN_GITHUB_WEBHOOK_SECRET=<secreto-largo-aleatorio>
FORVEN_GITHUB_WEBHOOK_BRANCH=feature/quant-factory-upgrade
FORVEN_GITHUB_WEBHOOK_REMOTE=origin
FORVEN_GITHUB_WEBHOOK_REPO=/home/trestor/forven
FORVEN_GITHUB_WEBHOOK_POST_PULL_CMD=
```

Ejemplo de comando post-pull opcional:

```bash
FORVEN_GITHUB_WEBHOOK_POST_PULL_CMD=systemctl --user restart forven-stack.service
```

Reinicia el backend después de configurar las variables de entorno.

## 2) Configurar el Webhook de GitHub

En la configuración del repositorio de GitHub:

1. Ve a `Settings -> Webhooks -> Add webhook`
2. Payload URL: `https://<tu-dominio>/api/webhooks/github`
3. Content type: `application/json`
4. Secret: el mismo valor que `FORVEN_GITHUB_WEBHOOK_SECRET`
5. Events: `Just the push event`
6. Active: habilitado

## 3) Verificar

Verifica la configuración del endpoint:

```bash
curl -s http://127.0.0.1:8003/api/webhooks/github/health
```

En la UI de webhooks de GitHub, usa `Recent Deliveries` para inspeccionar los payloads de respuesta.

## Notas

- Solo los eventos push para `FORVEN_GITHUB_WEBHOOK_BRANCH` activan el pull.
- Las actualizaciones se ejecutan con:
  - `git -C <repo> fetch <remote>`
  - `git -C <repo> pull --ff-only <remote> <branch>`
- Si el árbol de trabajo está sucio, el pull puede fallar.
