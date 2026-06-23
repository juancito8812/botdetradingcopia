# Respaldos y Rollback (Git-first)

El código fuente y el estado del proyecto de Forven viven en un repositorio git local en esta máquina. Los datos de trading y secretos **no** se confirman.

## Qué está cubierto
- Código fuente y estado del proyecto rastreados en git.
- Secretos excluidos vía `.gitignore` (`.env`, llaves, certificados, `*.db`, el espacio de trabajo `.forven_home/`).

## Flujo diario
```powershell
git add -A
git commit -m "checkpoint: <qué cambió>"
```

## Punto de restauración antes de cambios riesgosos
```powershell
git tag -a stable-YYYYMMDD-HHMM -m "Punto de restauración conocido bueno"
```

## Revertir
```powershell
git checkout <tag-o-commit>
```

## Opcional: publicar en un remoto privado
El repositorio es solo local por defecto. Para respaldarlo fuera de la máquina, crea un repositorio vacío **privado** y haz push:
```powershell
git remote add origin <URL_DE_TU_REPO_PRIVADO>
git branch -M main
git push -u origin main --tags
```

## Verificaciones de seguridad
- Nunca hagas commit de `.env`, `*.db`, tokens de autenticación o nada bajo `.forven_home/`.
- Rota las llaves inmediatamente si alguna vez se confirma un secreto.
- Mantén cualquier remoto privado.
