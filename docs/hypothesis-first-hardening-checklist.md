# Lista de Verificación de Endurecimiento Hipótesis-Primero

Usa esta lista contra el estado `.forven` en vivo después del inicio, después de al menos un ciclo de investigación fresco, y después de al menos un reinicio.

Cada elemento debe marcarse como uno de:
- `PASS` (PASA)
- `FAIL` (FALLA)
- `NEEDS TUNING` (NECESITA AJUSTE)

## 1. Secuencia de Arranque

- El Brain crea solo un ciclo de arranque después del reinicio.
  Evidencia: cronología del registro de tareas, filas `brain_invoke` más recientes.

- El arranque envía la primera oleada de investigación a los agentes `strategy-developer` habilitados.
  Evidencia: títulos de tareas nuevas e ids de agentes en el registro de tareas.

- Ninguna tarea de ideación de arranque de primera oleada se asigna a `quant-researcher`.
  Evidencia: cronología del registro de tareas inmediatamente después del reinicio.

- El Brain no se queda atascado en `running` sin enviar tareas.
  Evidencia: estado de la tarea de arranque y tareas de agentes descendentes.

## 2. Límites de Propiedad

- Las nuevas hipótesis son creadas solo por agentes con rol `strategy-developer`.
  Evidencia: `/api/hypotheses`, BD en vivo `hypotheses.origin_agent_id`, `hypotheses.origin_role`.

- Los agentes de estrategia personalizada se normalizan a `origin_role = strategy-developer`.
  Evidencia: payloads de hipótesis recientes de `/api/hypotheses`.

- `quant-researcher` es solo de soporte y no genera hipótesis de primera clase.
  Evidencia: registro de tareas, registro de auditoría de tareas, hipótesis recientes.

- Las herramientas de creación de estrategias están disponibles para `strategy-developer` y no para `quant-researcher`.
  Evidencia: comportamiento en runtime más tests de regresión de permisos de herramientas.

## 3. Integridad Hipótesis-a-Estrategia

- Cada nueva estrategia tiene exactamente un `hypothesis_id`.
  Evidencia: `/api/strategies/.../container`, BD en vivo `strategies.hypothesis_id`.

- Las hipótesis retienen ids serializados estables como `H00001` junto con ids crudos.
  Evidencia: `/api/hypotheses`, página de detalle de hipótesis.

- El detalle de la estrategia muestra el enlace de retroceso a la hipótesis padre.
  Evidencia: UI de detalle de estrategia y `/api/strategies/.../container`.

- Los artefactos externos permanecen adjuntos a su hipótesis y son verificables por el operador.
  Evidencia: página de detalle de hipótesis y `/api/hypotheses/{id}`.

- Las brechas de datos pueden adjuntarse a hipótesis y estrategias y acumularse correctamente.
  Evidencia: página de detalle de hipótesis y `/api/data-gaps`.

## 4. Cadencia y Permanencia del Runtime

- Los agentes prefieren hipótesis viables existentes antes de acuñar más.
  Evidencia: descripciones de tareas nuevas y conteos recientes de hipótesis/estrategias.

- Las nuevas hipótesis por agente por ciclo se mantienen acotadas.
  Evidencia: registros de auditoría de tareas recientes, marcas de tiempo de creación de hipótesis.

- Las estrategias por hipótesis prometedora muestran seguimiento acotado.
  Evidencia: conteos de estrategias vinculadas por hipótesis en `/api/hypotheses/{id}`.

- Las hipótesis activas no resueltas no se acumulan sin seguimiento.
  Evidencia: estados de hipótesis y conteos de estrategias vinculadas.

- Las hipótesis débiles o duplicadas se enfrían en lugar de multiplicarse sin fin.
  Evidencia: títulos de hipótesis recientes, mecanismos y dispersión de estrategias.

## 5. Presión de Memoria y Visión de Túnel

- El arranque es determinista y no está impulsado por la memoria del espacio de trabajo saturada.
  Evidencia: cronología de tareas de inicio y ausencia de deriva de arranque moldeada por memoria.

- La exploración no colapsa en familias repetidas con mucho RSI por defecto.
  Evidencia: títulos de hipótesis recientes, mecanismos y mezcla de origen/fuente.

- La memoria de inspiración opcional parece de apoyo, no directiva.
  Evidencia: salidas de tareas de investigación y cronología de auditoría de tareas.

- Las entradas de benchmarking se convierten en artefactos explícitos en la hipótesis.
  Evidencia: listas de artefactos de hipótesis y referencias de fuentes.

## 6. Configuración y Acuerdo del Runtime

- Los pesos de los carriles de investigación en la configuración coinciden con la mezcla de runtime deseada.
  Evidencia: `/settings -> Research`, payload de configuración almacenado, mezcla de carriles asignada en ciclos recientes.

- Los límites de generación en la configuración coinciden con los presupuestos de estrategia observados por hipótesis.
  Evidencia: configuración de investigación más conteos de estrategias vinculadas.

- La configuración de benchmarking externo coincide con si las tareas de benchmarking usan fuentes externas.
  Evidencia: configuración de investigación, descripciones de tareas, artefactos de hipótesis.

- Las selecciones de agente/proveedor en la UI coinciden con el proveedor/modelo real usado en runtime.
  Evidencia: metadatos de tarea/proveedor y configuración de agentes.
