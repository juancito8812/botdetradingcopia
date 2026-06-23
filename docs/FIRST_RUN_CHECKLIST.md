# Lista de Verificación del Primer Inicio

Usa esta lista cuando clones Forven en una máquina nueva.

## 1. Instalar requisitos previos

- [ ] Python 3.11+ está instalado
- [ ] Node.js 20+ está instalado
- [ ] Git está instalado
- [ ] Tienes acceso al repositorio y puedes clonarlo exitosamente

## 2. Clonar el repositorio

- [ ] `git clone https://github.com/judder659/Forven.git`
- [ ] `cd Forven`

## 3. Elegir una ruta de arranque

### Windows

- [ ] Establecer valores predeterminados seguros en el shell actual:

```powershell
$env:START_BOT = '0'
$env:START_DAEMON = '0'
```

- [ ] Iniciar el stack:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_all.ps1
```

Notas:

- `start_all.ps1` crea `.venv`, instala paquetes faltantes, inicializa la BD e inicia los servicios del backend/frontend.
- `start_all.ps1` lee las variables de entorno del shell actual. No carga `.env` automáticamente.

### macOS / Linux

- [ ] Crear y activar un entorno virtual:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

- [ ] Instalar dependencias del backend:

```bash
python -m pip install --upgrade pip
python -m pip install -e .
```

- [ ] Instalar dependencias del frontend:

```bash
cd frontend && npm install && cd ..
```

- [ ] Copiar la plantilla de entorno si quieres configuraciones de entorno locales del repositorio:

```bash
cp .env.example .env
```

- [ ] Iniciar el stack:

```bash
START_BOT=0 START_DAEMON=0 bash start_all.sh
```

Notas:

- `start_all.sh` carga `.env` automáticamente si existe.

## 4. Confirmar que el stack está saludable

- [ ] El frontend abre en `http://127.0.0.1:5173`
- [ ] La salud del backend devuelve `ok` en `http://127.0.0.1:8003/api/health`
- [ ] El panel se carga en `/`
- [ ] `/settings` se carga sin errores de API

## 5. Configurar autenticación y secretos

- [ ] Revisar `.env.example`
- [ ] Mantener `FORVEN_EXECUTION_MODE=paper`
- [ ] Establecer `FORVEN_ENCRYPTION_KEY` si quieres secretos cifrados portátiles
- [ ] Establecer `FORVEN_API_KEY` y `FORVEN_OPERATOR_KEY` si la API se usará más allá de localhost
- [ ] Iniciar sesión en los proveedores de IA según sea necesario:

```powershell
python -m forven configure
python -m forven auth login openai
python -m forven auth login minimax
python -m forven auth status
```

- [ ] En la UI, revisa Settings para autenticación de proveedores, configuración del exchange, claves API, notificaciones y configuración del pipeline

## 6. Realizar una prueba de humo básica

- [ ] Abrir `/data` y confirmar que los datasets o el estado de ingesta se carguen
- [ ] Abrir `/lab` y `/ai-dropzone`
- [ ] Abrir `/runs` y confirmar que la página se renderice
- [ ] Abrir `/risk`, `/approval`, `/tasks`, `/ops` y `/memory`
- [ ] Ejecutar un pequeño backtest o acción de investigación ligera en la UI

## 7. Ejecutar verificaciones de calidad locales

- [ ] Tests del backend:

```powershell
python -m pytest tests -q
```

- [ ] Linting del backend:

```powershell
python -m ruff check forven tests
```

- [ ] Tests y verificaciones del frontend:

```powershell
cd frontend
npm test
npm run check
```

## 8. Saber dónde mirar si el inicio falla

- [ ] Logs de Windows: `.tmp\logs\unified_backend.log` y `.tmp\logs\unified_frontend.log`
- [ ] Logs de Unix: `.tmp/logs/unified_backend.log` y `.tmp/logs/unified_frontend.log`
- [ ] Ruta del estado del runtime: `~/.forven` a menos que se establezca `FORVEN_HOME`
- [ ] Recuerda que `python -m forven` abre la CLI; el inicio solo del backend usa `python -m uvicorn --app-dir . forven.api:app`
