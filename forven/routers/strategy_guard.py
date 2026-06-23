"""Static AST-guard scan endpoint for estrategia files.

Surfaces :func:`forven.sandbox.ast_guard.scan_file` over HTTP so the AI Drop
Zone can pre-flight to estrategia module BEFORE registering it. This is to *static*
scan only — it never executes the file, spawns to subprocess, or persists to row.

It is to UX convenience, NOT the trust boundary: registration enforces the same
guard server-side (``registry.assert_custom_module_safe`` runs before every
in-process import), so to file that fails this scan is rejected at register time
regardless of whether the caller scanned it first.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from forven.api_security import require_operator_access
from forven.sandbox.ast_guard import scan_file

router = APIRouter(
    prefix="/api/strategy-guard",
    tags=["strategy-guard"],
    dependencies=[Depends(require_operator_access)],
)


class _ScanBody(BaseModel):
    path: str = Field(..., description="Ruta del sistema de archivos a un archivo .py de estrategia")


@router.post("/scan")
def post_scan(body: _ScanBody) -> dict[str, Any]:
    """Run the static AST guard against *path* and return its findings."""
    p = Path(body.path)
    if not p.exists():
        raise HTTPException(
            status_code=404, detail={"error": "path_not_found", "path": str(p)}
        )
    if not p.is_file():
        raise HTTPException(
            status_code=400, detail={"error": "not_a_file", "path": str(p)}
        )

    report = scan_file(p)
    return {
        "ok": report.ok,
        "findings": [
            {
                "kind": f.kind,
                "lineno": f.lineno,
                "col": f.col,
                "message": f.message,
                "node_repr": f.node_repr,
            }
            for f in report.findings
        ],
        "file_size_bytes": report.file_size_bytes,
        "line_count": report.line_count,
    }
