# Forven - Instrucciones para Agentes

## Descripción General del Proyecto

Forven es un framework de operaciones de trading algorítmico local-first. Actúa como un espacio de trabajo autónomo para trading cuantitativo: creación de estrategias, backtesting, despliegue y gestión de riesgos.

- **Backend**: Python 3.11+ / FastAPI - sirve en `http://127.0.0.1:8003`
- **Frontend**: SvelteKit 2 (Svelte 5) + TailwindCSS + Vite - sirve en `http://127.0.0.1:5173`
- **Base de datos**: SQLite vía `forven/db.py`
- **Backtesting**: Motor integrado barra por barra con generación vectorizada de señales
- **Almacén vectorial**: ChromaDB
- **Exchange**: Integración CCXT / Hyperliquid en `forven/exchange/`

---

## Estructura del Repositorio

```text
forven/                    # Python backend package
  api.py                   # FastAPI app, lifespan, router registration
  api_core.py              # Shared startup, compatibility, and legacy helpers
  control_plane/           # Operator-facing control-plane logic
  api_domains/             # API-facing domain modules and compatibility helpers
  routers/                 # FastAPI routers (one file per domain)
    agents.py              #   /api/agents
    analytics.py           #   /api/dashboard/*, /api/stats, scanner analytics
    approvals.py           #   /api/approvals
    auth.py                #   /api/auth/providers/*
    backtesting.py         #   /api/backtesting/*
    data.py                #   /api/data/* and dataset routes
    jobs.py                #   /api/jobs
    legacy.py              #   /api/forven/* compatibility routes
    lifecycle.py           #   /api/lifecycle/*
    memory.py              #   /api/memory/*
    notifications.py       #   /api/notifications/*
    ops.py                 #   /api/system/*, /api/logs, scheduler, resets
    paper.py               #   /api/paper/*
    quant_factory.py       #   /api/quant-factory
    robustness.py          #   /api/robustness/*
    simulation.py          #   /api/simulation/*
    status.py              #   /, /api/health, dashboard and status routes
    strategies.py          #   /api/strategies and results routes
    system.py              #   /api/settings/*, brain chat, system helpers
    tasks.py               #   /api/tasks and pipeline task audit routes
    trading.py             #   /api/trades/*
    verdict.py             #   /verdict/*
    webhooks.py            #   /api/webhooks/*
    websockets.py          #   /api/ws/live and /ws/live
  strategies/
    base.py                # BaseStrategy interface - all strategies extend this
    backtest.py            # Backtest engine, run_backtest()
    optimizer.py           # Grid search and optimization helpers
    fitness.py             # Fitness scoring functions
    registry.py            # Strategy discovery and loading
    sentiment.py           # Sentiment-based signal helpers
    builtin/               # Shipped strategies
    custom/                # User-created strategies (gitignored)
  cli.py                   # Click CLI (`python -m forven ...`)
  config.py                # Global configuration loader
  data.py                  # Market data download and ingestion
  db.py                    # SQLite schema and session helpers
  policy.py                # Pipeline stages and gate criteria
  scanner.py               # Market screener / scanner logic
  scheduler.py             # Cron-style task scheduling
  simulation.py            # Core simulation engine

frontend/                  # SvelteKit frontend
  src/
    routes/
      +page.svelte         #   /
      agents/              #   /agents
      ai-dropzone/         #   /ai-dropzone
      approval/            #   /approval
      data/                #   /data
      lab/                 #   /lab
        strategy/[id]/     #   /lab/strategy/:id
      memory/              #   /memory
      ops/                 #   /ops
      risk/                #   /risk
      runs/                #   /runs
      settings/            #   /settings
      tasks/               #   /tasks
      trades/              #   /trades
    lib/
      api/                 # Typed API client modules
      stores/              # Svelte writable stores
      components/          # Reusable Svelte components

tests/                     # pytest suite
docs/                      # project documentation
templates/workspace/       # agent workspace file templates
```

---

## Convenciones Clave

### Backend (Python)

- **Estilo de importación**: Usa siempre importaciones absolutas - `from forven.module import X`, nunca relativas.
- **Patrón de routers**: Mantén los endpoints de FastAPI delgados y delega la lógica de negocio a módulos enfocados.
- **Etapas del pipeline**: `researching -> backtesting -> paper -> deployed -> retired` (consulta `forven/policy.py`).
- **Type hints**: Todas las firmas de funciones deben tener type hints.
- **Linter**: Ruff.
- **Tests**: pytest en `tests/`.
- **Async**: Los endpoints de FastAPI son async cuando corresponde; el cómputo pesado se puede descargar.

### Frontend (SvelteKit / TypeScript)

- **Llamadas API**: Dirige la comunicación del backend a través de `frontend/src/lib/api/`.
- **Estado**: Los stores compartidos viven en `frontend/src/lib/stores/`.
- **Estilos**: Clases utilitarias de TailwindCSS.
- **Componentes**: La UI reutilizable pertenece a `frontend/src/lib/components/`.

---

## Ejecutar el Proyecto

```powershell
# Stack completo (recomendado en Windows)
powershell -ExecutionPolicy Bypass -File .\start_all.ps1

# Stack completo (macOS/Linux)
bash start_all.sh

# Solo backend
python -m uvicorn --app-dir . forven.api:app --host 127.0.0.1 --port 8003 --reload

# Solo frontend
cd frontend
npm run dev

# CLI
python -m forven --help

# Tests
python -m pytest tests -q

# Linting
python -m ruff check forven tests
```

Importante:

- `python -m forven` lanza la CLI, no el servidor API.
- `start_all.ps1` es la ruta de arranque más completa en Windows y puede auto-crear `.venv` además de instalar dependencias faltantes.

---

## Patrones Importantes a Seguir

1. **Agregar un nuevo endpoint backend**
   - Crear o editar un router en `forven/routers/`
   - Agregar la lógica de negocio en un módulo backend enfocado
   - Registrar el router en `forven/api.py` si es nuevo
   - Agregar un wrapper API correspondiente en `frontend/src/lib/api/`

2. **Agregar una nueva estrategia**
   - Extender `BaseStrategy` de `forven/strategies/base.py`
   - Colocarla en `forven/strategies/builtin/` o `forven/strategies/custom/`
   - Registrarla a través de `forven/strategies/registry.py`

3. **Agregar una ruta frontend**
   - Crear `frontend/src/routes/<name>/`
   - Agregar `+page.svelte` y archivos loader opcionales
   - Agregar funciones de cliente API tipadas si la ruta necesita nuevos datos del backend

---

## NO HACER

- Hacer commit de `.env`, `*.db`, tokens de autenticación o archivos en `.forven_home/`
- Modificar `forven/exchange/` sin instrucción explícita
- Usar importaciones relativas en código backend
- Poner lógica de negocio directamente en archivos de router
- Usar `fetch()` crudo en componentes Svelte cuando un cliente API tipado pertenece a `frontend/src/lib/api/`
- Instalar nuevas dependencias Python sin actualizar `pyproject.toml`

---

## Usar Forven programáticamente (sin MCP) — `forven.agent`

El servidor MCP de Forven es solo un **wrapper stdio** delgado sobre la API REST
del backend en `:8003` (la misma API que usa el frontend). Cuando no puedas usar
MCP — Codex, la app Tauri, un sidecar, CI, o cuando MCP falle — usa el **harness
HTTP sin dependencias**. Hace todo lo que hace MCP.

**Shell (Claude Code / Codex):** cada comando imprime JSON en stdout.
```bash
python -m forven.agent health
python -m forven.agent context --out .tmp/ctx.json     # datasets, template, param families (large)
python -m forven.agent list --status paper
python -m forven.agent gate-report S02545              # por qué una estrategia es/no es promocionable
# escribe una estrategia .py en forven/strategies/custom/, luego ejecuta el pipeline completo:
python -m forven.agent enqueue --file /abs/path/strat.py --dataset BTC/USDT-1h
python -m forven.agent wait-paper --strategies S02545,S02604 --timeout 1800
```
También instalado como script de consola `forven-agent`. La lista completa de
comandos + la realidad de las compuertas (quick_screen / cost_stress /
deflated-Sharpe) están en `forven/agent/README.md`.

**Python (sidecars/embedding):**
```python
from forven.agent import ForvenAgentClient
fc = ForvenAgentClient()                       # http://127.0.0.1:8003, sobreescribible vía env
verdict = fc.enqueue_candidate("/abs/strat.py", "BTC/USDT-1h")   # register→backtest→screen→promote (force=false)
```

**En la app / Tauri / navegador (TypeScript):** usa `frontend/src/lib/api/agent.ts`
(`ForvenAgent`), que reutiliza el `fetchApi` de la app (auth + descubrimiento de base):
```ts
import ForvenAgent from '$lib/api/agent';
const v = await ForvenAgent.enqueueCandidate('/abs/strat.py', 'BTC/USDT-1h');
```

Reglas: nunca pases `force=true` para saltar una compuerta; establece
`compatible_regimes = ["trending","volatile","range_bound"]` en estrategias
personalizadas; no uses `stop_loss_pct` en `default_params`. Auth (solo si
`:8003` está expuesto más allá de localhost): establece `FORVEN_API_KEY` /
`FORVEN_OPERATOR_KEY`.
