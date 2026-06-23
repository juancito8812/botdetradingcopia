# LESSONS.md — Información de Inteligencia de Trading

Captura de ideas puras. Sin tablas, sin volcados de backtest. Solo "aprendí X porque Y."
Actualizado a medida que se completan los experimentos. Lee esto antes de diseñar cualquier nueva estrategia.

---

## Mercado y Régimen

(Lecciones sobre condiciones del mercado y detección de régimen van aquí)

---

## Diseño de Estrategias

(Lecciones sobre construcción de estrategias, parámetros y tipos de señales van aquí)

---

## Infraestructura

(Lecciones sobre herramientas, APIs y comportamiento del sistema van aquí)

---

## Riesgo y Dimensionamiento

(Lecciones sobre dimensionamiento de posiciones, criterio de Kelly y gestión de riesgo van aquí)

---

## Proceso

(Lecciones sobre metodología de investigación y flujo de trabajo van aquí)

---

*Última actualización: (fecha)*
# Resumen de Revisión S50209 (27 de marzo de 2026)

## Resultados de la Investigación

### Hallazgo 1: El Archivo de Estrategia EXISTE
El tipo de estrategia `funding_mean_reversion_v2` existe en:
`forven/strategies/custom/funding_mean_reversion_v2.py`

Este NO es el mismo problema que S50147 (el tipo de estrategia no existe).

### Hallazgo 2: S50209 NO Existe en la Base de Datos
Se buscaron todas las tablas (strategies, backtest_results, strategy_candidates, tasks, agent_tasks) - S50209 NO está en la base de datos.

### Hallazgo 3: Razón del Fallo del Backtest
Ejecutar backtest en `funding_mean_reversion_v2` produce un error de `'timestamp'`, sugiriendo:
- La estrategia puede no estar registrada correctamente en el registro de estrategias
- O el enriquecimiento de datos (funding_rate) carece de la columna de timestamp requerida

### Conclusión
- El contenedor S50209 parece ser fantasma/no creado
- El tipo de estrategia real EXISTE pero no puede ser backtesteado vía `run_backtest`
- Esto es un **problema de registro/registry**, no un problema de código faltante

## Acciones Pendientes
1. Si se suponía que S50209 existiera, recrearlo correctamente
2. Investigar por qué `funding_mean_reversion_v2` falla con error de timestamp
3. Verificar si las estrategias personalizadas requieren registro explícito antes de que `run_backtest` pueda usarlas