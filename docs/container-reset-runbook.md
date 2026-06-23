# Runbook de Reinicio de Contenedores

Úsalo cuando los contenedores de estrategia del ciclo de vida estén divididos en estado obsoleto de SQLite/Chroma y necesites un reinicio limpio.

## Alcance

El script de reinicio realiza:

1. Respaldo de `forven.db` y `chromadb/`.
2. Elimina todas las filas de:
   - `strategies`
   - `trades`
   - `portfolio_positions`
   - `backtest_result_trash`
   - `backtest_runs`
   - `strategy_events`
   - `strategy_candidates`
   - `backtest_results` (si está presente)
3. Reinicia los prefijos de `container_counters` `S`, `B`, `E`, `T` a `1`.
4. Limpia la colección de Chroma `backtest_results`.

## 1) Detener Servicios en Ejecución

Detén los procesos del backend/frontend antes del reinicio para evitar condiciones de escritura.

## 2) Vista Previa (Simulación)

```powershell
.venv\Scripts\python.exe scripts\reset_strategy_containers.py
```

## 3) Ejecutar Reinicio

```powershell
.venv\Scripts\python.exe scripts\reset_strategy_containers.py --yes
```

Ubicación de respaldo personalizada opcional:

```powershell
.venv\Scripts\python.exe scripts\reset_strategy_containers.py --yes --backup-dir C:\tmp\forven-reset-backup
```

## 4) Verificar Compuerta de Aceptación

Verificar conteos de tablas DB + contadores:

```powershell
@'
from forven.db import get_db
tables = [
    "strategies",
    "trades",
    "portfolio_positions",
    "backtest_result_trash",
    "backtest_runs",
    "strategy_events",
    "strategy_candidates",
    "backtest_results",
]
with get_db() as conn:
    for t in tables:
        try:
            c = conn.execute(f"SELECT COUNT(*) AS c FROM {t}").fetchone()["c"]
            print(f"{t}: {c}")
        except Exception as exc:
            print(f"{t}: <missing> ({exc})")
    rows = conn.execute("SELECT prefix, next_val FROM container_counters ORDER BY prefix").fetchall()
    print("container_counters:", [(r["prefix"], r["next_val"]) for r in rows])
'@ | .venv\Scripts\python.exe -
```

Verificar colección Chroma:

```powershell
@'
from forven.vectordb import get_client
client = get_client()
names = sorted([c.name for c in client.list_collections()])
print("collections:", names)
if "backtest_results" in names:
    col = client.get_collection("backtest_results")
    print("backtest_results count:", col.count())
'@ | .venv\Scripts\python.exe -
```

Resultado esperado:

- Las tablas reiniciadas reportan `0` filas.
- `container_counters` incluye `('B', 1)`, `('E', 1)`, `('S', 1)`, `('T', 1)`.
- Chroma `backtest_results` no existe o tiene `0` elementos.

## 5) Restaurar desde Respaldo (Si es Necesario)

1. Detén los servicios.
2. Copia el archivo DB de respaldo de vuelta a `FORVEN_HOME\forven.db`.
3. Reemplaza `FORVEN_HOME\chromadb` con la copia de respaldo.
4. Reinicia los servicios.
