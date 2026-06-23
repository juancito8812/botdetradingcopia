# Manual de Usuario de Forven

Este manual refleja la superficie actual de la aplicación en este repositorio.

## 1. Qué es Forven

Forven es un espacio de trabajo local-first para construir, validar, supervisar y operar estrategias de trading algorítmico.

Componentes principales:

- Un backend FastAPI en `http://127.0.0.1:8003`
- Un frontend SvelteKit en `http://127.0.0.1:5173`
- Estado SQLite almacenado bajo `FORVEN_HOME`
- Memoria y contexto de espacio de trabajo respaldados por ChromaDB
- Adaptadores de exchange basados en CCXT en `forven/exchange/`

Forven mantiene la investigación, aprobaciones, monitoreo del runtime y controles operativos en un solo lugar en lugar de dividirlos entre notebooks, bots y paneles.

## 2. Iniciar la App

### Stack completo

```powershell
powershell -ExecutionPolicy Bypass -File .\start_all.ps1
```

```bash
bash start_all.sh
```

### Solo backend

```powershell
python -m uvicorn --app-dir . forven.api:app --host 127.0.0.1 --port 8003 --reload
```

### Solo frontend

```powershell
cd frontend
npm run dev
```

### CLI

```powershell
python -m forven --help
python -m forven configure
python -m forven auth status
```

## 3. Navegación Principal

La barra lateral izquierda es el mapa más rápido del producto.

| Ruta | Propósito | Uso típico |
| --- | --- | --- |
| `/` | Panel principal | Salud general, actividad, acciones, ganadores y señales en vivo |
| `/?view=quant_factory` | Vista Quant | Sección alternativa del panel centrada en generación de estrategias |
| `/?view=beta` | Vista Spec | Presentación alternativa del panel shell/spec |
| `/data` | Espacio de datos | Cobertura de datasets, ejecuciones de ingesta y operaciones de obtención |
| `/lab` | Laboratorio de estrategias | Explorar y gestionar flujos de trabajo de investigación de estrategias |
| `/lab/strategy/[id]` | Detalle de estrategia | Inspeccionar métricas, estado y ciclo de vida de una estrategia |
| `/runs` | Historial de ejecuciones | Revisar backtests, trabajos, optimizaciones y resultados anteriores |
| `/ai-dropzone` | Recepción de ideas IA | Enviar o refinar ideas de estrategia impulsadas por prompts |
| `/risk` | Supervisión de riesgo | Estado del kill switch, límites de riesgo y controles de supervisión |
| `/trades` | Revisión de trades | Posiciones abiertas, trades recientes y resúmenes de ejecución |
| `/agents` | Centro de agentes | Estado de agentes, enrutamiento, tareas y política de modelos |
| `/memory` | Espacio de memoria | Buscar e inspeccionar elementos de memoria Chroma/workspace |
| `/tasks` | Cola de tareas | Tareas de agentes, auditorías y visibilidad de tareas del pipeline |
| `/approval` | Compuertas humanas | Revisar aprobaciones y transferencias de acciones sensibles |
| `/ops` | Operaciones del runtime | Informe de soak, notificaciones, scheduler, logs y reparaciones |
| `/settings` | Configuración global | Credenciales, autenticación de proveedores, claves API, configuración del pipeline y reinicios |

## 4. Primera Sesión Recomendada

1. Inicia el stack.
2. Abre `/settings` y revisa el modo de ejecución, autenticación de proveedores y claves API.
3. Abre `/data` para asegurarte de que los datasets y los endpoints de ingesta estén saludables.
4. Abre `/lab` o `/ai-dropzone` para crear o inspeccionar ideas de estrategia.
5. Abre `/runs` para revisar el historial de backtests y trabajos.
6. Abre `/risk`, `/approval` y `/ops` antes de mover una estrategia más allá de los flujos de paper.

## 5. Flujos de Trabajo Comunes

### Investigación de estrategias

Usa `/ai-dropzone` o `/lab` para crear o refinar una idea, luego profundiza en `/lab/strategy/[id]` una vez que exista una estrategia.

Secuencia típica:

1. Crear o importar una idea.
2. Revisar parámetros y metadatos.
3. Ejecutar un backtest o flujo de robustez.
4. Inspeccionar resultados en la página de detalle de la estrategia y en `/runs`.

### Ciclo de vida de la estrategia

El ciclo de vida canónico es:

- `researching`
- `backtesting`
- `paper`
- `deployed`
- `retired`

Estos se asignan a las compuertas de política gestionadas en `forven/policy.py`.

### Revisión operativa

Cuando algo necesita atención del operador:

- `/approval` muestra acciones bloqueadas
- `/tasks` muestra trabajo en cola e histórico
- `/ops` muestra salud del sistema, notificaciones, estado del scheduler, logs y acciones de reparación
- `/risk` muestra controles de seguridad y estado relacionado con drawdown

### Memoria y contexto

Usa `/memory` para inspeccionar recuerdos guardados, anotaciones y salud de fuentes para la capa de memoria del espacio de trabajo.

## 6. Notas de Runtime y Seguridad

- Mantén los entornos nuevos en modo `paper`.
- No habilites `mainnet` casualmente.
- Revisa los límites de riesgo antes de habilitar comportamiento autónomo o conectado al exchange.
- Si las claves API están configuradas para acceso desde el navegador, empareja `FORVEN_API_KEY` con `VITE_FORVEN_API_KEY`, y empareja `FORVEN_OPERATOR_KEY` con `VITE_FORVEN_OPERATOR_KEY`.
- El código del exchange en vivo vive en `forven/exchange/` y debe tratarse como sensible.

## 7. Verificaciones de Salud Útiles

- Salud del backend: `http://127.0.0.1:8003/api/health`
- Salud de compatibilidad heredada: `http://127.0.0.1:8003/health`
- Raíz del frontend: `http://127.0.0.1:5173`
- Endpoints WebSocket:
  - `/api/ws/live`
  - `/ws/live`

## 8. Solución de Problemas

- Los logs del lanzador viven en `.tmp/logs/` en sistemas Unix y `.tmp\logs\` en Windows.
- `python -m forven` es el punto de entrada de la CLI, no el servidor backend.
- Si el frontend está activo pero las llamadas API fallan, verifica `http://127.0.0.1:8003/api/health` primero.
- Si la autenticación o el estado del espacio de trabajo parecen faltar, verifica la ruta activa de `FORVEN_HOME`.
