# Política de Seguridad

Forven es un software auto-alojado que almacena **tus** credenciales de exchange
(testnet) y LLM, ejecuta una API local y ejecuta código de estrategia generado
por IA. Por favor, ayuda a mantenerlo seguro reportando vulnerabilidades de
forma responsable.

## Reportar una vulnerabilidad

**Por favor, no abras un issue público de GitHub para problemas de seguridad.**

- **Preferido:** usa el reporte privado de vulnerabilidades de GitHub —
  **Security → Report a vulnerability** en este repositorio.
- **Alternativa:** envía un correo a **judder@forven.app**.

Por favor incluye: una descripción del problema, la versión/commit afectado,
pasos para reproducir (una prueba de concepto si es posible) y el impacto que
prevés. Buscamos acusar recibo de los informes en unos días; este es un proyecto
pequeño, así que por favor permite un tiempo razonable para una corrección antes
de cualquier divulgación pública (divulgación coordinada).

## Versiones compatibles

Las correcciones de seguridad se enfocan en la última versión y la rama `main`.
Las versiones anteriores no reciben mantenimiento — actualiza antes de reportar.

## Alcance y notas de endurecimiento

Las opciones de configuración más relevantes para la seguridad están documentadas
en [`.env.example`](.env.example). Al auto-alojar:

- **Mantén la API en localhost.** No tiene autenticación por defecto. Si
  configuras `FORVEN_BIND_HOST` en una dirección que no sea loopback, la app
  requiere `FORVEN_API_KEY` (e idealmente `FORVEN_OPERATOR_KEY`) o se niega a
  iniciar. Nunca la expongas a internet sin autenticación y un proxy TLS.
- **La herramienta shell del agente está deshabilitada por defecto**
  (`FORVEN_ENABLE_SHELL_TOOL=0`). Activarla permite que contenido dirigido por
  LLM e influenciado por la web ejecute comandos de shell — actívala solo si
  entiendes el riesgo de inyección de prompts.
- **El trading live/mainnet no tiene soporte y está desactivado por defecto.**
  Llegar a una orden con dinero real requiere múltiples aceptaciones explícitas;
  consulta [`DISCLAIMER.md`](DISCLAIMER.md).
- **El código de estrategia generado por IA y personalizado se ejecuta en el
  mismo proceso**, con los mismos privilegios que la app — incluido el acceso a
  tu base de datos local y cualquier credencial API en el entorno. Antes de la
  importación, se examina estáticamente mediante un guardia AST que bloquea las
  construcciones peligrosas obvias (importaciones OS/network/subprocess,
  `eval`/`exec`/`compile`, lecturas de archivos y builtins con alias), pero una
  lista negra estática **no es un sandbox** ni un límite de confianza completo.
  Solo registra código de estrategia en el que confíes y mantén la API en
  localhost.

Gracias por ayudar a mantener seguros a Forven y sus usuarios.
