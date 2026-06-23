# Runbook de Disciplina de Hipótesis

Cómo operar el bucle de refinamiento de hipótesis después del rediseño del 2026-04-17.
Este documento responde a "¿por qué no ha aparecido una nueva hipótesis hoy?"
y preguntas similares del operador.

---

## Qué cambió

Antes: el sistema creaba cientos de hipótesis superficiales (una estrategia por
hipótesis, luego seguía adelante). Cada hipótesis se trataba como única; los
veredictos esencialmente nunca se escribían.

Después: el sistema trabaja cada hipótesis hasta que está **demostrada** o
**refutada**, bajo tres mecanismos de disciplina:

1. **Válvula de presión del grupo activo** — una población objetivo de N
   hipótesis está en `manager_state='active'`. Cuando llega una creación y el
   grupo ya está al límite, el sistema auto-archiva la hipótesis activa más
   débil (menos estrategias vinculadas, luego `updated_at` más antiguo, luego
   `created_at` más antiguo) para hacer espacio. Los agentes de investigación
   y los operadores nunca son rechazados. `HypothesisPoolFullError` ahora es
   un respaldo defensivo que solo se activa si no se puede encontrar una
   víctima de desalojo — estructuralmente inusual.
2. **Profundidad round-robin** — el bucle de promoción no volverá a
   seleccionar la misma hipótesis hasta que al menos `min_per_pick`
   estrategias se hayan creado desde su último envío. Obliga a la amplitud.
3. **Piso matemático del veredicto** — el veredicto del LLM está limitado
   superiormente por matemáticas duras: `proven` requiere tasa de aciertos ≥
   umbral Y diversidad ≥ celdas mínimas en la ventana móvil. El LLM puede
   degradar `proven` a `researching` pero no puede mejorar `disproven` a
   `proven`.

Cuando una hipótesis alcanza `proven`, **se gradúa**: `manager_state` cambia a
`graduated`, el mejor hijo por celda `(asset, timeframe)` se marca como
`canonical=1` (protegido de limpieza), y se establece `next_revisit_at`.

---

## Configuración de disciplina

Editar en **Settings → Research → Hypothesis Discipline**. Los valores
predeterminados son deliberadamente estrictos; aflojar solo con una razón
específica.

| Configuración | Predeterminado | Qué controla |
|---|---|---|
| `active_pool_cap` | 100 | Población objetivo de hipótesis activas simultáneas. Cuando se excede, la más débil se auto-archiva; los operadores nunca son rechazados. |
| `min_per_pick` | 2 | Estrategias necesarias antes de volver a seleccionar una hipótesis. |
| `verdict_rolling_window` | 5 | Cuántos resultados hijos recientes considera el veredicto. |
| `verdict_hit_rate_threshold` | 0.4 | Fracción de hijos exitosos necesaria para `proven`. |
| `verdict_min_diversity_cells` | 2 | Celdas distintas `(asset, timeframe)` necesarias para `proven`. |
| `revisit_interval_days` | 30 | Días hasta que una hipótesis graduada sea elegible para revisitar. |

---

## Preguntas comunes del operador

### "¿Por qué no ha aparecido una nueva hipótesis hoy?"

El límite del grupo ya no es una compuerta de rechazo — es una válvula de
presión. Las creaciones siempre tienen éxito en condiciones normales. Si no ha
aparecido una nueva hipótesis:

1. **El agente no está intentando.** Verifica que
   `forven-hypothesis-promotion-loop` esté habilitado y ejecutándose en el
   scheduler.
2. **Rotación del grupo al límite.** Si `active_pool_cap` es demasiado pequeño
   en relación a la tasa de nuevas hipótesis, cada creación desaloja una
   anterior — revisa el registro de hipótesis en busca de líneas repetidas de
   `pool at cap (N); evicted ...`. Aumenta el límite o reduce la tasa de
   creación.
3. **Rechazo defensivo de grupo lleno.** Muy raro: `HypothesisPoolFullError`
   ahora solo se activa cuando la consulta de desalojo no encuentra víctima.
   Inspecciona los logs en busca de códigos de error `hypothesis_pool_full`
   devueltos desde la ruta de la herramienta.

### "¿Por qué una hipótesis está recibiendo todas las estrategias?"

No es así, después de la compuerta round-robin. La consulta de puntuación del
bucle de promoción calcula `strategies_since_last_pick` por hipótesis y omite
cualquier hipótesis que:
- haya sido seleccionada al menos una vez (`last_dispatched_at IS NOT NULL`) Y
- tenga menos de `min_per_pick` estrategias desde ese envío.

Si ves esta queja, mira `last_dispatched_at` y el conteo de estrategias
creadas después de esa marca de tiempo.

### "El bucle de promoción registró `no_eligible: 1` — ¿qué significa?"

La compuerta de profundidad filtró a todos los candidatos. Esto es normal,
brevemente: significa que cada hipótesis activa ha sido seleccionada
recientemente y aún no ha acumulado suficientes estrategias nuevas. Si es
persistente, o bien:
- Los workers son lentos → la cola de backtesting upstream está atascada.
- `min_per_pick` está configurado demasiado alto en relación a la tasa real de
  creación de estrategias.

### "¿Cómo fuerzo un pase de investigación fresco en una hipótesis graduada?"

Las hipótesis graduadas están en la pestaña **Graduated**. Abre una y presiona
el botón **Revisit** (o `POST /api/hypotheses/{id}/revisit`). Esto:
- Auto-desaloja la hipótesis activa más débil si el grupo está al límite (la
  misma válvula de presión que create_hypothesis) para que la revisita siempre
  tenga éxito.
- Transiciona la hipótesis a `manager_state='active'`,
  `status='researching'`, incrementa `revisit_count` y limpia
  `last_dispatched_at` para que la compuerta de profundidad no la suprima
  inmediatamente.

El prompt del agente para hipótesis revisitadas incluye una instrucción
"supera la canónica" con las estrategias canónicas como objetivos a superar.

### "¿Qué significa la insignia canónica?"

Una estrategia canónica es el mejor hijo por celda de una hipótesis graduada.
Es:
- Etiquetada en verde ("Canonical") en el encabezado del detalle de la
  estrategia y en la lista de estrategias vinculadas del detalle de la
  hipótesis.
- Protegida de transiciones `archive` y `reject` incluso cuando
  `force=True`.

Hay como máximo una canónica por celda `(asset, timeframe)` por hipótesis.

### "¿Cómo sé si el piso matemático del veredicto cambió un veredicto del LLM?"

El memo del veredicto registra tanto `verdict` (final, después del piso
matemático) como `llm_verdict` (salida cruda del LLM). Si difieren, el piso
anuló al LLM. El memo también almacena `signals` con `mathematical_verdict`,
`hit_rate`, `diversity_cells`, etc.

### "¿Por qué el pase de revisita diario no está promoviendo nada?"

Tres verificaciones, en orden:
1. ¿Hay alguna hipótesis graduada con `next_revisit_at <= now`? La mayoría aún
   no si `revisit_interval_days` es 30 y la graduación es reciente.
2. ¿El grupo activo está lleno? El pase se detiene temprano si el límite está
   al máximo y registra `revisit_pass.pool_full`.
3. ¿El trabajo `forven-hypothesis-revisit-pass` está habilitado? Está
   registrado en estado deshabilitado por `scripts/register_hypothesis_jobs.py`.

---

## Líneas clave de registro

```
revisit_pass.pool_full active=N cap=N remaining=N      # límite detuvo revisita a medio camino (barrido batch aún cortocircuita en el límite)
revisit_pass.summary evaluated=N revisited=N skipped_pool_full=BOOL
hypothesis.graduated id=HYP-... canonicals=N demoted=N already_graduated=BOOL
promotion.no_eligible n=0 (depth gate filtró todos los candidatos)
hypothesis pool at cap (N); evicted HYP-... (strategies=K) to admit new hypothesis
force_revisit pressure valve: evicted HYP-... to revisit HYP-...
```

---

## Decisión de despliegue: grupo de hipótesis existente

Con el modelo de válvula de presión no hay requisito de triaje en el
despliegue — las creaciones siempre tendrán éxito y desalojarán la hipótesis
activa más débil cuando el grupo esté al límite. Si ya tienes cientos de
hipótesis activas, considera aumentar `active_pool_cap` (predeterminado 100,
máximo 500) para mantener baja la rotación de desalojo mientras te pones al
día.

Habilitar:
- `forven-hypothesis-promotion-loop` (intervalo de 5 min)
- `forven-hypothesis-verdict-loop` (intervalo de 5 min)
- `forven-hypothesis-revisit-pass` (diario — el barrido batch aún
  cortocircuita cuando el grupo está lleno; confía en force_revisit por
  solicitud para revisiones prioritarias)
