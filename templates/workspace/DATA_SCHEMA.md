# Esquema de Datos

Esto documenta las columnas disponibles en el DataFrame de backtest/scanner para que las estrategias referencien campos reales. Se inyecta en el contexto de cada agente trabajador.

## Columnas Principales (siempre presentes)

Cada DataFrame de backtest contiene estas columnas OHLCV:

| Columna     | Tipo    | Descripción                          |
|-------------|---------|--------------------------------------|
| timestamp   | int64   | Milisegundos Unix (UTC)              |
| open        | float64 | Precio de apertura de la vela        |
| high        | float64 | Precio máximo de la vela             |
| low         | float64 | Precio mínimo de la vela             |
| close       | float64 | Precio de cierre de la vela          |
| volume      | float64 | Volumen en moneda base               |

## Columnas de Enriquecimiento (presentes cuando se recopilan datos históricos)

Estas columnas se unen a OHLCV en tiempo de lectura a través de `DataManager.enrich()`. Se rellenan mediante el backfill masivo de Binance Vision y la recopilación continua.

| Columna        | Tipo    | Granularidad | Disponible Desde | Descripción                                               |
|---------------|---------|-------------|----------------|-----------------------------------------------------------|
| funding_rate  | float64 | 8h          | ~2020-11       | Tasa de funding de Binance Futures a 8h. Positivo = longs pagan a shorts. Negativo = shorts pagan a longs. Útil como señal de sentimiento/posicionamiento. |
| open_interest | float64 | 1h, 4h      | ~2020-11       | Interés abierto agregado en moneda base (ej. BTC). OI creciente con precio creciente = confirmación de tendencia. OI creciente con precio decreciente = presión bajista. |

### Notas

- `funding_rate` se une mediante `merge_asof` — cada vela obtiene la tasa de funding más reciente en o antes de su marca de tiempo.
- `open_interest` se une de la misma manera. Con granularidad 1h, cada vela tiene OI. Con 4h, cada vela obtiene la muestra OI de 4h más reciente.
- Ambas columnas de enriquecimiento son `NaN` para velas anteriores a 2020-11 (antes de que Binance Futures lanzara perpetuos a escala).
- Disponible para los 9 símbolos activos: BTC-USDT, ETH-USDT, BNB-USDT, SOL-USDT, XRP-USDT, DOGE-USDT, ADA-USDT, AVAX-USDT, MATIC-USDT.
- Al escribir estrategias que usan estas señales, siempre protégete contra NaN: `df['funding_rate'].fillna(0)` o `df['funding_rate'].notna()`.
