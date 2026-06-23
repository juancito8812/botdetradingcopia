#!/usr/bin/env bash

# Configuración Reforzada de Forven
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

echo "=== Verificaciones Previas de Forven ==="

# 1. Verificar versión de Python
python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "Python detectado: $python_version"
if [[ $(echo "$python_version < 3.10" | bc -l) -eq 1 ]]; then
    echo "ERROR: Se requiere Python >= 3.10."
    exit 1
fi

# 2. Verificar SQLite
if ! command -v sqlite3 &> /dev/null; then
    echo "ADVERTENCIA: No se encontró el comando sqlite3. La inspección de la base de datos requerirá herramientas de Python."
fi

# 3. Instalar dependencias del backend
echo "Instalando dependencias del backend..."
pip install -e .

# 4. Ejecutar migraciones de la base de datos
echo "Ejecutando migraciones de la base de datos..."
python3 -c "from forven.db import init_db; init_db()"

# 5. Instalar dependencias del frontend
if [ -d "frontend" ]; then
    echo "Instalando dependencias del frontend de Forven..."
    cd frontend
    if command -v npm &> /dev/null; then
        npm install
    else
        echo "ADVERTENCIA: npm no encontrado. Omitiendo instalación de dependencias del frontend."
    fi
    cd ..
fi

echo "=== Configuración completada. ==="
