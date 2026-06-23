# Lista de Verificación de Recuperación ante Reinicio de Hyperliquid

Última actualización: 2026-03-12

## Propósito

Usa esta lista de verificación para endurecer la recuperación ante reinicio de Hyperliquid para que un reinicio del daemon/backend no pueda dejar la exposición del exchange en vivo sin gestionar, invisible o desprotegida.

## Cómo usar este archivo

- Mantén los elementos completados marcados.
- Agrega una nota con fecha cada vez que implementemos una corrección, cambiemos el comportamiento del runtime o validemos un escenario de recuperación.
- No re-habilitar nuevas entradas hasta que todos los elementos de aceptación `P0` estén marcados.

## Ancla del Incidente

- Hyperliquid testnet mantenía un BTC largo abierto mientras Forven mostraba `0` posiciones abiertas.
- El tamaño residual en vivo coincidía con el trade `E0095` (`0.00471 BTC`).
- La orden stop reduce-only en vivo `49994803084` de Hyperliquid coincidía con `E0095.signal_data.exchange_stop_order_id`.
- El reconciliador del daemon detectó `missing_in_sqlite` pero no adoptó la posición del exchange de vuelta a la gestión activa.
- Un reinicio en medio de este ciclo de vida se considera un escenario crítico de seguridad.

## Decisiones Bloqueadas

- [x] La pausa del operador y el bloqueo de recuperación permanecen independientes.
- [x] La finalización de la recuperación no debe limpiar automáticamente una pausa del operador.
- [x] El orden de auto-coincidencia es estricto: primero ID de orden exacto, luego asset/dirección/tamaño normalizados exactos, luego tiempo solo como desempate.
- [x] Si quedan múltiples candidatos, la recuperación debe detenerse y requerir revisión del operador.
- [x] Las posiciones recuperadas obtienen una nueva fila de trade OPEN con `source='exchange_recovered'`; no mutamos silenciosamente trades cerrados históricos.
- [x] La adopción de recuperación y el registro de riesgo deben ser atómicos.
- [x] Cada pase de recuperación obtiene un `recovery_batch_id` para rollback.
- [x] Las posiciones recuperadas sin protección mantienen el trading bloqueado hasta que se adjunte protección o un operador resuelva el incidente.

## P0 - Prevenir Deriva de Exposición por Reinicio

### Consistencia de Compuertas

- [x] Estandarizar la compuerta de trading en `system_state.paused` y mantener lecturas compatibles hacia atrás para claves de pausa heredadas.
- [x] Hacer que `daemon_state.recovery_active` sea un bloqueo duro independiente dentro de `is_trading_allowed()`.
- [x] Confirmar que `pausa del operador + recuperación activa` bloquea el trading.
- [x] Confirmar que `recuperación resuelta + pausa del operador aún activa` permanece bloqueada.
- [x] Exponer ambos estados claramente en las respuestas del panel/control-plane.

### Verificación Previa al Inicio

- [x] Agregar una verificación previa de recuperación al inicio en `forven.daemon.run()` antes de entrar al bucle principal.
- [x] Obtener posiciones de Hyperliquid antes de que se reanude la ejecución del scanner.
- [x] Obtener órdenes abiertas de Hyperliquid antes de que se reanude la ejecución del scanner.
- [x] Obtener instantánea de la cuenta de Hyperliquid antes de que se reanude la ejecución del scanner.
- [x] Persistir el estado de recuperación en `daemon_state`:
- [x] `recovery_active`
- [x] `recovery_status`
- [x] `recovery_started_at`
- [x] `recovery_position_count`
- [x] `recovery_discrepancy_count`
- [x] `recovery_requires_operator`
- [x] `recovery_batch_id`
- [x] Bloquear nuevas entradas hasta que la recuperación de inicio se resuelva limpiamente.
- [x] Confirmar que el daemon/backend residente está ejecutando el código en disco previsto antes de validar el comportamiento.

### Instantánea del Exchange y Coincidencia

- [x] Dividir la reconciliación en ayudantes explícitos para instantánea, coincidencia, adopción y validación de protección.
- [x] Coincidir por `entry_exchange_order_id` exacto cuando esté presente.
- [x] Coincidir por `exchange_stop_order_id` exacto cuando esté presente.
- [x] Coincidir por `asset + direction + size` normalizados exactos solo cuando el candidato sea único.
- [x] Usar proximidad de tiempo solo para romper empates entre candidatos ya válidos.
- [x] Rechazar la adopción automática cuando la coincidencia siga siendo ambigua.
- [x] Registrar el motivo de la coincidencia en los metadatos de recuperación.

### Adopción Atómica

- [x] Crear un solo ayudante que escriba la fila de trade OPEN recuperada y la fila de `portfolio_positions` en una transacción.
- [x] Sellar filas recuperadas con `source='exchange_recovered'`.
- [x] Sellar filas recuperadas con `signal_data.recovery_batch_id`.
- [x] Sellar filas recuperadas con `signal_data.recovery_reason`.
- [x] Sellar filas recuperadas con `signal_data.recovered_from_trade_id` cuando se haya coincidido un trade anterior.
- [x] Reconstruir el estado de riesgo de los trades abiertos después de que se complete la adopción de recuperación.
- [x] Confirmar que ninguna ruta de lectura pueda observar un trade recuperado sin una fila `portfolio_positions` coincidente.

### Validación de Protección

- [x] Reutilizar una orden stop reduce-only en vivo existente si ya hay una en el exchange.
- [x] Si no existe un stop en vivo, reutilizar el stop anterior del trade coincidente de `signal_data` cuando aún sea sensato.
- [x] Definir e implementar una política de stop de emergencia determinista para posiciones recuperadas.
- [x] Limitar la colocación del stop de emergencia con una configuración de seguridad de distancia máxima dedicada.
- [x] Si no se puede derivar un stop sensato, mantener la recuperación bloqueada y requerir acción del operador.
- [x] Registrar la procedencia del stop en los metadatos de recuperación.

### Visibilidad de la Recuperación

- [x] Forzar verificación del exchange en `read_open_trades()` cada vez que la recuperación esté activa.
- [x] Forzar verificación del exchange en `read_open_trades()` cada vez que haya problemas de reconciliación.
- [x] Mostrar posiciones recuperadas en las vistas de posiciones abiertas del panel.
- [x] Mostrar posiciones recuperadas en el espacio de trabajo de trades.
- [x] Agregar etiquetas de UI para:
- [x] `Recovered`
- [x] `Recovery blocking entries`
- [x] `Needs protection`
- [x] `Exchange-backed`
- [x] Agregar resúmenes de recuperación visibles para el operador a `ops_manual_action_state`.

### Rollback

- [x] Agregar un ayudante de rollback clave por `recovery_batch_id`.
- [x] El rollback debe pausar las entradas antes de revertir las filas de recuperación.
- [x] El rollback debe limpiar las filas OPEN recuperadas del lote objetivo.
- [x] El rollback debe reconstruir `portfolio_positions` de los trades OPEN restantes.
- [x] El rollback debe limpiar los marcadores de recuperación obsoletos del estado del daemon.

### Tests P0

- [x] Inicio del daemon con posición del exchange y SQLite vacío adopta la posición antes de que se reanuden las entradas.
- [x] Inicio del daemon con posición del exchange y `portfolio_positions` faltante restaura el registro de riesgo.
- [x] Inicio del daemon con posición del exchange y stop en vivo existente vincula la protección correctamente.
- [x] Inicio del daemon con posición del exchange y sin stop permanece bloqueado y marca `recovery_requires_operator=true`.
- [x] Inicio del daemon con candidatos de coincidencia ambiguos requiere revisión del operador.
- [x] Caso huérfano inverso: SQLite muestra OPEN mientras el exchange está plano.
- [x] Caso de compuerta combinada: pausa del operador más recuperación activa.
- [x] Rollback de recuperación por `recovery_batch_id`.

### Criterios de Aceptación P0

- [x] Después del reinicio, cualquier posición en vivo de Hyperliquid es visible en Forven en segundos.
- [x] Después del reinicio, cualquier posición recuperada vuelve a estar bajo gestión de riesgo antes de que se permitan nuevas entradas.
- [x] El reinicio no puede dejar la exposición del exchange invisible mientras la UI muestra `0` posiciones abiertas.
- [x] El reinicio no puede reanudar nuevas entradas mientras una posición recuperada carezca de protección.
- [x] El estado de recuperación es visible tanto en los payloads de estado del backend como en la UI.

## P1 - Veracidad de la Ruta de Cierre

- [x] Agregar manejo de `pending_close_reconcile` para solicitudes de cierre.
- [x] Dejar de tratar los precios de cierre solicitados como fills de salida confirmados.
- [x] Dejar de finalizar cierres locales hasta que el exchange esté plano o se confirme un fill de salida real.
- [x] Preservar la lógica de recuperación/adopción entre reinicios cuando un cierre aún esté pendiente de reconciliación.
- [x] Cancelar o retirar órdenes vinculadas de stop/take-profit en cierre confirmado.
- [x] Agregar tests de regresión para reinicio durante la reconciliación de cierre pendiente.
- [x] Agregar tests de regresión para limpieza de exchange-plano pero SQLite-abierto.

## P2 - Reportes y Claridad para el Operador

- [x] Persistir una instantánea completa de la cuenta respaldada por el exchange, no solo `account_equity`.
- [x] Separar `Account Equity`, `Available To Trade` y `Margin Used` en el panel.
- [x] Unificar la resolución de red para que los diagnósticos siempre indiquen la red real utilizada.
- [x] Mostrar problemas de reconciliación y resúmenes de recuperación en el panel principal y vistas de operaciones.
- [x] Confirmar que las posiciones de paper respaldadas por el exchange permanezcan visibles por defecto.

## P3 - Reingreso y Endurecimiento del Scanner

- [x] Preservar el estado de bloqueo de reingreso en la misma barra cuando se actualicen las huellas de entrada.
- [x] Verificar que una estrategia no pueda reabrir en la misma barra después de una posición recuperada o cerrada recientemente.
- [x] Considerar un enfriamiento a nivel de activo para que múltiples estrategias de paper no puedan reabrir en serie el mismo activo en una barra sin política explícita.

## Notas

- `2026-03-12 - Lista de verificación creada para impulsar el endurecimiento de la recuperación ante reinicio de Hyperliquid.`
- `2026-03-12 - Implementada capa backend P0 para compuerta de trading consciente de recuperación, verificación previa de inicio del daemon y exposición del estado de recuperación. Tests específicos pasados para compuerta de recuperación, payload de recuperación del panel y ayudantes de verificación previa de inicio del daemon.`
- `2026-03-12 - Agregada adopción estricta del exchange al inicio: coincidencia de orden stop y tamaño exacto, bloqueo de coincidencia ambigua, registro atómico de trade recuperado + portafolio, y tests de reinicio para adopción/restauración de riesgo.`
- `2026-03-12 - Agregado bloqueo de recuperación consciente de protección y verificación automática del exchange para vistas de trades abiertos durante recuperación o problemas de reconciliación.`
- `2026-03-12 - Mostrado estado de recuperación en la UI del panel/trades con banners de recuperación más insignias de Recuperado, Respaldado por Exchange y Necesita protección.`
- `2026-03-12 - Corregido manejo de inicio huérfano inverso para que los trades OPEN de SQLite se cierren automáticamente y se traten como resueltos cuando Hyperliquid ya está plano.`
- `2026-03-12 - Agregados resúmenes de recuperación orientados a operaciones en ops_manual_action_state, reconciliación manual del exchange consciente de recuperación, y rollback por recovery_batch_id con pausa forzada + reconstrucción de portafolio.`
- `2026-03-12 - Agregada reparación de protección en tiempo de reinicio: reutilizar stops anteriores sensatos, colocar stops de emergencia deterministas cuando sea necesario, y mantener la recuperación bloqueada si falla la restauración del stop.`
- `2026-03-12 - Implementada reconciliación de cierre pendiente para que las solicitudes de cierre permanezcan OPEN hasta la confirmación de exchange plano, y la limpieza de cierre confirmado ahora retira las órdenes de protección reduce-only vinculadas.`
- `2026-03-12 - Agregada coincidencia estricta de recuperación por entry_exchange_order_id, ayudantes explícitos de instantánea del exchange, y una salvaguarda de ruta de lectura que reconstruye las filas de riesgo del portafolio antes de que se muestren los trades recuperados.`
- `2026-03-12 - Almacenadas en caché instantáneas completas de la cuenta de Hyperliquid en el estado del daemon, resolución de red unificada en rutas de daemon/scanner/trading/soak, y mostrado equity vs disponible vs margen en el panel.`
- `2026-03-12 - Agregadas huellas de código de runtime al estado del backend más endurecimiento de misma barra del scanner que preserva bloqueos de estrategia y bloquea el reingreso serial de activos en la misma vela, incluyendo verificaciones de respaldo DB conscientes de reinicio.`
