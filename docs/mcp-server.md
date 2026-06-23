# Servidor MCP de Forven

Expón la Zona de Descarga de IA (AI Drop Zone) a Claude Desktop (o cualquier
cliente MCP) como un conjunto de herramientas, para que la generación de
estrategias sea una conversación en lugar de un bucle de copiar y pegar.

## Qué es

Un servidor MCP que envuelve la API HTTP de Forven en ejecución. Habla el
Protocolo de Contexto de Modelo (MCP) sobre stdio — Claude Desktop inicia el
proceso, lee la lista de herramientas y las llama en tu nombre mientras
charlas.

## Requisitos previos

- Backend de Forven en ejecución (`forven serve` o `python -m uvicorn forven.api:app --port 8003`)
- Entorno Python donde `forven` sea importable (el mismo venv desde el que ejecutas el backend está bien)
- Claude Desktop instalado, o cualquier otro cliente MCP

## Ejecutar localmente

```bash
python -m forven.mcp_server
```

El proceso lee tramas MCP de stdin y escribe a stdout, por lo que ejecutarlo
en una terminal parece que se ha colgado. Eso es normal — está esperando un
cliente.

### Configuración

Todo a través de variables de entorno:

| Variable | Predeterminado | Propósito |
|---|---|---|
| `FORVEN_API_URL` | `http://127.0.0.1:8003` | URL base del backend |
| `FORVEN_API_KEY` | *(vacío)* | Enviado como `x-api-key` cuando se establece |
| `FORVEN_OPERATOR_KEY` | *(vacío)* | Enviado como `x-operator-key` cuando se establece |
| `FORVEN_MCP_TIMEOUT` | `60` | Timeout HTTP en segundos |

Si `FORVEN_AUTH_REQUIRED=true` en el backend, DEBES establecer
`FORVEN_API_KEY` y `FORVEN_OPERATOR_KEY` o cada llamada de herramienta dará 401.

## Conectar a Claude Desktop

Edita `claude_desktop_config.json`:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "forven": {
      "command": "python",
      "args": ["-m", "forven.mcp_server"],
      "env": {
        "FORVEN_API_URL": "http://127.0.0.1:8003",
        "FORVEN_API_KEY": "tu-api-key",
        "FORVEN_OPERATOR_KEY": "tu-operator-key"
      }
    }
  }
}
```

Si tu `python` no está en PATH dentro del entorno de generación de Claude
Desktop, usa la ruta absoluta al intérprete (ej.
`C:\Users\tu\venvs\forven\Scripts\python.exe`).

Reinicia Claude Desktop. Deberías ver un icono de martillo/herramienta en la
UI del chat — haz clic para confirmar que las herramientas `forven_*` están
cargadas.

## Referencia de herramientas

### Solo lectura

| Herramienta | Propósito |
|---|---|
| `forven_get_context` | Contexto completo de AI Drop Zone (plantilla, datasets, endpoints, flujo de trabajo). Llama primero. |
| `forven_list_sessions` | Sesiones recientes con conteos de estrategias. |
| `forven_get_session` | Estrategias + ejecuciones etiquetadas en una sesión. |
| `forven_list_strategies` | Estrategias registradas. |
| `forven_get_recent_runs` | Últimas N ejecuciones de backtest. |
| `forven_get_result` | Métricas + trades + configuración para un resultado. |
| `forven_get_quant_skills` | Información curada por régimen. Verifica antes de diseñar. |

### Escritura

| Herramienta | Propósito |
|---|---|
| `forven_create_session` | Abrir una sesión (devuelve id como `ADZ-0007`). |
| `forven_close_session` | Marcar una sesión como cerrada. Idempotente. |
| `forven_register_strategy_file` | Registrar un archivo .py. Etiqueta a sesión si se proporciona. |
| `forven_run_backtest` | Ejecutar un backtest. Etiqueta a sesión si se proporciona. |

## Flujo de trabajo típico dentro de Claude Desktop

```
> Open a session for "RSI mean reversion iteration 3"
Claude calls forven_create_session → returns ADZ-0007

> Design and register a novel RSI strategy for BTC-1h
Claude calls forven_get_context, forven_get_quant_skills(regime="range_bound"),
writes a .py file into the workspace, calls forven_register_strategy_file
with session_id="ADZ-0007" → returns strategy_id

> Backtest it
Claude calls forven_run_backtest(strategy_id, dataset_id="BTC/USDT-1h",
session_id="ADZ-0007") → returns result

> Show me what I've tried this session
Claude calls forven_get_session("ADZ-0007") → summary of every strategy
and run under this session
```

## Solución de problemas

**"Tool call timed out"** — aumenta `FORVEN_MCP_TIMEOUT`. Los backtests
completos pueden tomar minutos en cachés frías.

**"401 Invalid or missing operator key"** — el backend tiene la
autenticación habilitada pero el entorno MCP no tiene `FORVEN_OPERATOR_KEY`.
Configúralo en el bloque `env` de la configuración de Claude Desktop.

**"Connection refused"** — el backend no se está ejecutando o está en un
puerto diferente al de `FORVEN_API_URL`.

**Las herramientas no aparecen en Claude Desktop** — verifica los logs de
Desktop (`%APPDATA%\Claude\logs\mcp-server-forven.log` en Windows). Causas
comunes: `python` no está en PATH, `forven` no es importable en el entorno
generado, o el JSON de configuración tiene un error de sintaxis.
