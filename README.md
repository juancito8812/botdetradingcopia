# Bot de Trading Copia — Forven en Español

**Traducción completa al español del proyecto Forven.** Fork con toda la interfaz, documentación, scripts y mensajes del backend en español.

**Forven es un espacio de trabajo gratuito, open-source y auto-alojado para investigación y operaciones de trading de criptomonedas.** Combina un equipo de agentes de IA con un motor de backtesting, un "calvario" de robustez, paper trading y un panel de operador — para que la generación de ideas, validación y monitoreo vivan en un solo repositorio que ejecutas en tu propia máquina.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
&nbsp;[![Docs](https://img.shields.io/badge/docs-forven.app-0b7285.svg)](https://forven.app)

> ⚠️ **Paper + testnet por defecto. No es asesoría financiera.**
> Forven se distribuye en **modo paper trading** con **Hyperliquid testnet** como valor predeterminado compatible. Existe un motor de ejecución live/mainnet en el código, pero **no tiene soporte, está deshabilitado por defecto y solo es accesible mediante una aceptación explícita y deliberada** — activar trading con dinero real es bajo tu propio riesgo. El trading de criptomonedas conlleva un riesgo sustancial de pérdida total; los resultados de backtest y paper trading no predicen el rendimiento real, y las métricas del propio software pueden ser incorrectas. Úsalo completamente bajo tu propio riesgo. Consulta [`DISCLAIMER.md`](DISCLAIMER.md).

## Qué hace

- **Agentes de investigación autónomos** — un equipo de strategy-developer / quant-researcher / risk / execution agent que genera hipótesis, construye estrategias y las somete a validación.
- **Motor de backtesting** — ejecución barra por barra con generación vectorizada de señales.
- **El Calvario (Gauntlet)** — una batería de robustez (walk-forward analysis, Monte-Carlo, parameter-jitter, cost-stress) que controla la promoción de estrategias.
- **Paper trading** en Hyperliquid testnet, con controles de riesgo reales: stop-loss, un kill-switch de drawdown, conciliación de fills y monitoreo de distancia de liquidación.
- **Panel del operador** (SvelteKit) más un servidor **MCP** integrado, para que también puedas manejarlo desde Claude, Codex y otros clientes MCP.
- **Trae tus propias llaves** — tu clave del proveedor LLM y tus claves del exchange (testnet) permanecen **locales**; nada se envía a ningún servidor de Forven. No hay cuenta ni registro.

## Stack

- **Backend:** Python 3.11+, FastAPI, uvicorn
- **Frontend:** SvelteKit 2, Svelte 5, Tailwind CSS, Vite
- **Base de datos:** SQLite bajo `FORVEN_HOME` (por defecto `~/.forven`)
- **Memoria:** ChromaDB
- **Backtesting:** motor integrado barra por barra con generación vectorizada de señales
- **Capa de exchange:** Adaptadores CCXT en `forven/exchange/`
- **URLs locales por defecto:** frontend `http://127.0.0.1:5173` · backend `http://127.0.0.1:8003` · health `http://127.0.0.1:8003/api/health`

## Inicio Rápido

Requisitos: **Python 3.11+**, **Node.js** y **git**.

```bash
git clone https://github.com/judder659/Forven.git
cd Forven
```

### Windows (recomendado)

El lanzador PowerShell crea `.venv`, instala las dependencias del backend + frontend, inicializa la base de datos y lo inicia todo:

```powershell
$env:START_BOT = '0'
$env:START_DAEMON = '0'
powershell -ExecutionPolicy Bypass -File .\start_all.ps1
```

### macOS / Linux

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
cd frontend && npm install && cd ..
cp .env.example .env
START_BOT=0 START_DAEMON=0 bash start_all.sh
```

Luego abre **http://127.0.0.1:5173**.

### Trae tus propias llaves

Forven usa **tu** proveedor LLM y **tu** exchange — configurados localmente y nunca enviados a ningún servidor de Forven. Dos formas de conectar un proveedor LLM:

- **API key (recomendado):** agrégalo en el panel en **Settings → Agents**, o exporta la variable de entorno del proveedor antes de iniciar (ej. `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`).
- **Inicio de sesión OAuth:** `python -m forven auth login openai` conecta tu cuenta de ChatGPT/proveedor vía OAuth. `python -m forven auth status` muestra lo configurado.

Agrega tus credenciales de Hyperliquid **testnet** en el panel en `/settings`. No se requiere cuenta de Forven y las credenciales nunca salen de tu máquina.

## Documentación

- **Documentación completa:** **https://forven.app**
- En el repositorio: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · [`docs/FIRST_RUN_CHECKLIST.md`](docs/FIRST_RUN_CHECKLIST.md) · [`docs/USER_MANUAL.md`](docs/USER_MANUAL.md)

## Comunidad

- **GitHub:** https://github.com/judder659/Forven
- **Discord:** https://discord.gg/vzSQTneq6a
- **Reddit:** https://www.reddit.com/r/Forven/
- **X:** https://x.com/forvenapp

## Comandos comunes

```bash
# Run the full stack
powershell -ExecutionPolicy Bypass -File .\start_all.ps1     # Windows
bash start_all.sh                                            # macOS / Linux

# Backend only
python -m uvicorn --app-dir . forven.api:app --host 127.0.0.1 --port 8003 --reload

# Frontend only
cd frontend && npm run dev

# CLI
python -m forven --help

# Tests / checks
python -m pytest tests -q
python -m ruff check forven tests
cd frontend && npm test && npm run check
```

## Configuración y seguridad

Comienza desde `.env.example` y configura solo lo que necesites. Valores útiles:

- `FORVEN_EXECUTION_MODE=paper` — el modo predeterminado y el único **con soporte**. `live` existe pero no tiene soporte; una orden con dinero real adicionalmente requiere `FORVEN_ALLOW_MAINNET=1` y credenciales de mainnet, y es completamente bajo tu propio riesgo.
- `START_BOT=0` / `START_DAEMON=0` — deja el bot de Discord / el daemon de trading autónomo apagados a menos que los quieras.
- `FORVEN_BIND_HOST=127.0.0.1` — solo localhost por defecto. Exponer la API (`0.0.0.0` / una IP LAN) requiere configurar `FORVEN_API_KEY`, o la app se niega a iniciar.
- `FORVEN_API_KEY` / `FORVEN_OPERATOR_KEY` — establécelos si la API será accesible más allá de localhost.
- `FORVEN_ENABLE_SHELL_TOOL=0` — la herramienta shell del agente está desactivada por defecto (riesgo de inyección de prompts); actívala solo bajo tu propio riesgo.
- `FORVEN_ENCRYPTION_KEY` — para credenciales cifradas portátiles.
- `FORVEN_HOME` — para ubicar el estado de ejecución fuera del `~/.forven` predeterminado.

Nunca hagas commit de `.env`, `*.db`, tokens de autenticación o claves API (están en gitignore). La configuración predeterminada es paper + testnet y no realiza operaciones con dinero real; activar live/mainnet no tiene soporte y es completamente bajo tu propio riesgo.

## Contribuciones

Forven **aún no acepta contribuciones externas de código** — no existe un acuerdo de contribución todavía, por lo que las pull requests de contribuyentes externos no serán fusionadas por ahora. **Issues, ideas y discusiones son bienvenidas** (GitHub issues, [Discord](https://discord.gg/vzSQTneq6a), [r/Forven](https://www.reddit.com/r/Forven/)). Consulta [`CONTRIBUTING.md`](CONTRIBUTING.md) y [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

¿Encontraste un problema de seguridad? Repórtalo de forma privada — consulta [`SECURITY.md`](SECURITY.md). No abras un issue público para vulnerabilidades.

## Licencia

Copyright (C) 2026 Judder <judder@forven.app>

Forven es software libre, licenciado bajo la **GNU Affero General Public License, versión 3 o (a tu elección) cualquier versión posterior**. Se distribuye SIN NINGUNA GARANTÍA. Por ser AGPL, si ejecutas una versión modificada como servicio de red, debes poner el código fuente correspondiente a disposición de sus usuarios (AGPL §13). Texto completo en [`LICENSE`](LICENSE); consulta también [`NOTICE`](NOTICE) y [`TRADEMARK.md`](TRADEMARK.md).

## Descargo de responsabilidad

Forven es un software experimental proporcionado **TAL CUAL** para uso educativo y de investigación, y **no es asesoría financiera**. Solo paper trading + Hyperliquid testnet; riesgo sustancial de pérdida total. Eres el único responsable de cualquier orden colocada y de proteger tus propias credenciales. Consulta [`DISCLAIMER.md`](DISCLAIMER.md) para los términos completos.
