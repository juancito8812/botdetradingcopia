# Fuentes de Investigación Externas — Guía del Operador

El pipeline de investigación hipótesis-primero puede obtener evidencia de cinco tipos de fuentes: **YouTube** (enviado anteriormente), **Reddit**, **blogs/RSS**, **GitHub** y **foros**. Cada una es opt-in y se configura a través de `forven_settings`.

Esta guía cubre: habilitar cada fuente, agregar credenciales API cuando sea útil, ajustar registros y solucionar problemas.

---

## Cómo funciona el control de acceso

Cada herramienta de investigación externa verifica tres compuertas antes de hacer cualquier llamada HTTP:

1. **Contrato de investigación** — la tarea debe estar en el carril `benchmarking` con `external_sources_allowed: true` y el tipo de fuente en `allowed_external_source_types`.
2. **Registro de fuentes** — `research_settings.research_sources.<type>.enabled` debe ser `true`.
3. **Limitador de tasa** — presupuesto por dominio aún no agotado para el minuto actual.

Si falla la compuerta, devuelve un envelope de error estructurado al agente (`{"ok": false, "error": "..."}`) en lugar de consumir una llamada de red.

---

## Forma de la configuración

Toda la configuración de fuentes vive bajo `forven_settings.research_settings.research_sources`. La clave DB es `forven:settings`. Los valores predeterminados son:

```json
{
  "research_settings": {
    "research_sources": {
      "reddit":  { "enabled": false, "subs":  ["algotrading", "quant", "options", "thetagang", "systematictrading"], "client_id": null, "client_secret": null, "rate_limit_per_min": 30 },
      "blog":    { "enabled": false, "feeds": ["https://www.quantstart.com/articles/rss/", "https://quantocracy.com/feed/", "https://blog.quantinsti.com/feed/"], "rate_limit_per_min": 30 },
      "github":  { "enabled": false, "orgs":  ["quantopian", "hudson-and-thames", "stefan-jansen"], "personal_access_token": null, "rate_limit_per_min": 60 },
      "forum":   { "enabled": false, "sites": ["elitetrader.com", "quantconnect.com", "quantnet.com"], "rate_limit_per_min": 20 }
    }
  }
}
```

Todas las fuentes están por defecto en `enabled: false` — debes optar explícitamente.

---

## Reddit

**Herramientas expuestas:** `discover_reddit_posts(query, subs?, limit?)`, `inspect_reddit_thread(permalink)`

### Habilitar

Establece `research_sources.reddit.enabled = true`. Ajusta `subs` a los subreddits que quieres que los agentes busquen.

### Credenciales (opcional)

Los endpoints anónimos `www.reddit.com/*.json` funcionan de serie con ~60 req/min. Para mayor rendimiento o para evitar 429s intermitentes, registra una app OAuth en https://www.reddit.com/prefs/apps y completa `client_id` / `client_secret`. La ruta de actualización OAuth está cableada pero no activada automáticamente — consulta Trabajo Futuro.

### Límite de tasa

Predeterminado `rate_limit_per_min: 30`. Aumenta a 60 si es anónimo y ejecutas bucles de benchmarking ajustados; mantén por debajo de 100 para evitar limitación a nivel de IP.

### Solución de problemas

- `error_code: "rate_limited"` → reduce el límite o agrega credenciales OAuth.
- `error_code: "parse"` con `"unexpected reddit response shape"` → Reddit devolvió un dict de error en lugar del listado normal. Generalmente significa que el subreddit es privado/cuarentena o el permalink estaba malformado.
- Posts eliminados o removidos devuelven `ok: true` con `selftext: "[deleted]"` — el artefacto sigue adjunto para que los agentes puedan razonar sobre el hecho de que la evidencia fue retirada.

---

## Blog / RSS

**Herramientas expuestas:** `discover_blog_articles(query, feeds?, limit?)`, `inspect_blog_article(url)`

### Habilitar

Establece `research_sources.blog.enabled = true`. Selecciona `feeds` a fuentes RSS/Atom de alta señal. Se soportan tanto RSS 2.0 como Atom.

### Semillas predeterminadas

Se incluyen tres feeds iniciales: QuantStart, Quantocracy, QuantInsti. Cámbialos por tus fuentes preferidas — agrega cualquier cosa que exponga un feed.

### Extracción de artículos

`inspect_blog_article` usa [trafilatura](https://trafilatura.readthedocs.io/) para extraer texto plano. La calidad depende de la estructura HTML del sitio. Los artículos que son muy renderizados por SPA o con paywall devolverán contenido vacío — el artefacto aún se adjunta para que el agente sepa que la URL fue verificada.

### Límite de tasa

Predeterminado `rate_limit_per_min: 30`. La mayoría de los blogs son tolerantes, pero grandes extracciones de feeds que se ramifican en búsquedas de artículos pueden agotar rápidamente un presupuesto por dominio. Prefiere un `limit` bajo en `discover_*` (5–10) para mantener acotadas las búsquedas de inspección posteriores.

### Dependencias

`feedparser>=6.0` y `trafilatura>=2.0` están declarados en `pyproject.toml`. Instala con `pip install -e .` o `uv pip install -e .`.

---

## GitHub

**Herramientas expuestas:** `discover_github_repos(query, orgs?, limit?)`, `inspect_github_repo(full_name)`

### Habilitar

Establece `research_sources.github.enabled = true`. Ajusta `orgs` a repositorios conocidos de quant-trading (predeterminado: quantopian, hudson-and-thames, stefan-jansen). Deja `orgs` como `[]` para permitir que los agentes busquen en todo GitHub.

### Credenciales — muy recomendado

Sin autenticar, la API de búsqueda de GitHub es 60 req/h — agotada por un puñado de ejecuciones de benchmarking. Crea un Personal Access Token (no se necesitan alcances para lecturas de repos públicos) en https://github.com/settings/tokens y establece `personal_access_token`. Eso eleva el límite a 5000 req/h.

El PAT se envía a través del encabezado `Authorization: token <pat>`. Nunca se registra.

### Límite de tasa

Predeterminado `rate_limit_per_min: 60`. Mayormente decorativo — el propio límite de GitHub se aplica primero.

### Salida de `inspect_github_repo`

Devuelve README (crudo), top 5 issues abiertos+cerrados y metadatos del repositorio. Los cuerpos de los issues se truncan a 200 caracteres cada uno para mantener el blob `content` acotado.

### Solución de problemas

- `error_code: "http_4xx"` en un repositorio conocido-público → el PAT puede estar malformado o caducado; intenta desconfigurarlo primero.
- `error_code: "rate_limited"` sin PAT → establece el PAT.
- README vacío → el repositorio no tiene README.md; prueba README.rst o README.txt (no soportado hoy).

---

## Foro

**Herramientas expuestas:** `discover_forum_threads(query, sites?, limit?)`, `inspect_forum_thread(url)`

### Habilitar

Establece `research_sources.forum.enabled = true`. Los `sites` predeterminados incluyen Elite Trader, foro de QuantConnect, QuantNet.

### Modelo de adaptador

Los foros no tienen un esquema estándar. Cada sitio soportado incluye un adaptador por sitio en `forven/research_sources/forum.py::ADAPTERS` que declara:
- plantilla de URL de búsqueda
- selector CSS para elementos de la lista de resultados
- selector CSS para el enlace del resultado (generalmente `a.thread-link`)
- selector CSS para el contenedor de posts del hilo
- selector CSS para el cuerpo del post

Cuando un sitio se rediseña, sus selectores de adaptador se rompen. Solución: inspeccionar el nuevo HTML y actualizar la entrada única del adaptador — el radio de explosión se mantiene pequeño.

Los sitios que no están en `ADAPTERS` se omiten silenciosamente. Si quieres agregar un foro:

```python
ADAPTERS["newforum.com"] = ForumAdapter(
    site="newforum.com",
    search_url=lambda q: f"https://newforum.com/search?q={quote(q)}",
    result_selector="div.result",
    result_link_selector="a.title-link",
    thread_selector="article.post",
    post_selector=".post-body",
)
```

### Límite de tasa

Predeterminado `rate_limit_per_min: 20`. Los foros tienden a imponer una detección agresiva de bots (Cloudflare, etc.) — mantén esto bajo. El límite de tasa por dominio también es global, por lo que múltiples agentes que comparten un proceso comparten el presupuesto.

### Solución de problemas

- Los resultados vuelven vacíos a pesar de una búsqueda conocida-buena → los selectores probablemente están obsoletos. Verifica el adaptador contra el HTML actual del sitio.
- `error_code: "http_4xx"` con estado `403` → desafío Cloudflare. No hay solución en v1; considera deshabilitar ese sitio específico.

---

## Caché de contenido de artefactos

Cada herramienta `inspect_*` devuelve una cadena `content`. Cuando el agente llama a `attach_hypothesis_artifact(..., cached_content=content)`, esa cadena se persiste en `hypothesis_artifacts.cached_content` con un hash sha256 y un conteo de bytes.

- **Límite máximo:** 500 KB por artefacto. El contenido más grande se trunca con un marcador `...[truncated]`.
- **Deduplicación:** el mismo contenido adjunto a múltiples fuentes produce el mismo hash — permite a los agentes identificar evidencia que aparece en más de un lugar.
- **Exposición API:** `GET /api/hypotheses/{id}` elimina `cached_content` por defecto (hash/bytes/cached_at aún visibles). Pasa `?include=content` para recuperar los blobs.

---

## Notas de seguridad

- Las credenciales (Reddit `client_secret`, GitHub `personal_access_token`) se leen de `forven_settings` y se inyectan en los encabezados de las solicitudes. Nunca se registran ni serializan en las respuestas de la API.
- Nunca hagas commit de credenciales reales al repositorio; usa la BD de configuración como fuente de verdad.
- El User-Agent HTTP es `forven-research-sources/1.0` con una URL de proyecto. Si necesitas identificar la instancia de manera diferente, edita `forven/research_sources/_http.py::USER_AGENT`.

---

## Habilitar a través de la BD de configuración

Toda la configuración vive en la clave SQLite `forven:settings`. Un bloque mínimo de habilitar-todo para pruebas:

```python
from forven.db import kv_get, kv_set

s = kv_get("forven:settings", {})
s.setdefault("research_settings", {}).setdefault("research_sources", {})
for src in ("reddit", "blog", "github", "forum"):
    s["research_settings"]["research_sources"].setdefault(src, {})["enabled"] = True
kv_set("forven:settings", s)
```

Reinicia cualquier proceso de agente de larga duración después de un cambio de configuración — el contrato de investigación se resuelve por tarea pero el registro se lee en cada llamada de herramienta, por lo que los cambios surten efecto en la siguiente tarea de investigación de hipótesis.

---

## Trabajo futuro

- Implementación del flujo OAuth para Reddit (el espacio para credenciales ya existe).
- Límites de generación por fuente (hoy los límites de generación son globales entre carriles).
- Resumen impulsado por LLM antes de la adjunción (el contenido se pasa a los agentes crudo hoy).
- UI de configuración para interruptores de fuente (actualmente solo JSON a través de `kv_set`).
- Caché consciente de ETag de GitHub (reducir cuota desperdiciada en repos sin cambios).
- Verificación de salud automática de adaptadores para foros (detectar selectores obsoletos de forma proactiva).
