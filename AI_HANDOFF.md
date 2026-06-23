# Documento de Traspaso — Bot de Trading Copia

> **Traducción completa al español del proyecto Forven v0.1.34**

## 📌 Resumen

| Item | Detalle |
|------|---------|
| **Proyecto original** | [Forven](https://github.com/judder659/Forven) — Trading algorítmico autónomo |
| **Este repo** | Traducción 1:1 al español de toda la interfaz visible |
| **Idioma original** | Inglés |
| **Idioma actual** | Español (~98% traducido) |

## 📊 Traducción aplicada

| Capa | Archivos | Estado |
|------|:--------:|:------:|
| Documentación (README, docs/, templates/) | 33 .md | ✅ Español |
| Scripts (start_all, setup) | 3 | ✅ Español |
| Frontend rutas | 37 .svelte | ✅ Español |
| Frontend componentes | 128 .svelte | ✅ Español |
| Frontend API clients + stores | 6 .ts | ✅ Español |
| Backend routers | 22 .py | ✅ Español |
| Backend CLI + core | 10+ .py | ✅ Español |

**Total: ~98% del texto visible en español**

## 🚀 Para ejecutar

```powershell
cd botdetradingcopia
$env:START_BOT='0'; $env:START_DAEMON='0'
powershell -ExecutionPolicy Bypass -File .\start_all.ps1
# Abrir http://127.0.0.1:5173
```
