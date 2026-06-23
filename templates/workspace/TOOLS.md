# TOOLS.md — Notas Locales y Runtime

## Cómo Funciona Realmente Forven

Forven es una **app de escritorio Tauri**. El shell Rust inicia el backend Python incrustado como `python -m forven.api`. **No hay servicios 24/7 del SO, no hay unidades systemd, no hay cron jobs, no hay tareas programadas.** Todo depende de que la app esté abierta:

- Abre la app → el backend FastAPI se inicia y, bajo un solo bloqueo de runtime-worker, ejecuta todos los bucles **en el proceso**:
  - **bucle del scheduler** (~30s tick — despachador de trabajos cron/intervalo)
  - **bucle de agente headless** (~5s)
  - **bucle del cerebro headless** (~20s)
  - **daemon de datos/riesgo** (ingesta de precios/datos + kill-switch duro, detención por pérdida diaria, reconciliación de posiciones, heartbeat)
- Cierra la app → todo se detiene. Los ciclos perdidos se **colapsan en una ejecución de recuperación** al reabrir (no se reproducen N veces).

No intentes hacer `systemctl`, `sc start` o "iniciar un servicio" — no los hay, y en Windows esos comandos no aplican. Para ejecutar Forven, abre la app (o, para desarrollo, `start_all.ps1`).

## Endpoints (solo local)

| Qué | Dirección |
|------|---------|
| API Backend (FastAPI/uvicorn) | `http://127.0.0.1:8003` |
| Servidor de desarrollo Frontend (SvelteKit/Vite) | `http://127.0.0.1:5173` |

## Puntos de entrada solo para desarrollo

Estos existen para desarrollo; la app empaquetada no los usa:

- `start_all.ps1` — arranque local completo (backend + frontend, opcionalmente el bot de Discord cuando `START_BOT=1` y hay un token configurado, y el daemon independiente cuando `START_DAEMON=1`).
- `python -m forven daemon start` — ejecutar el daemon de datos/riesgo de forma independiente.
- `python -m forven bot start` — ejecutar el bot opcional de Discord (heredado).

## Qué va aquí

Notas específicas del entorno que vale la pena conservar: detalles del dispositivo, puertos locales, cualquier cosa única de esta máquina. Esta es tu hoja de trucos — agrega lo que sea que te ayude a hacer el trabajo.
