"""FastAPI routes for the unified, page-aware in-app assistant."""

import json
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from forven.api_security import require_operator_access
from forven.assistant_db import (
    archive_thread,
    create_or_get_active_thread,
    get_thread,
    list_messages,
)
from forven.assistant_session import confirm_action, run_turn

router = APIRouter(tags=["assistant"], dependencies=[Depends(require_operator_access)])


class CreateThreadBody(BaseModel):
    scope_kind: str | None = "global"
    scope_id: str | None = None
    page_route: str | None = None


@router.post("/api/assistant/threads")
def create_or_get(body: CreateThreadBody):
    kind = (body.scope_kind or "global").strip() or "global"
    if kind == "strategy":
        sid = (body.scope_id or "").strip()
        if not sid:
            raise HTTPException(status_code=400, detail="scope_id es requerido para un hilo con alcance de estrategia")
        from forven.db import get_db
        with get_db() as conn:
            row = conn.execute("SELECT id FROM strategies WHERE id = ?", (sid,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail=f"Estrategia {sid} no encontrada")
    return create_or_get_active_thread(kind, body.scope_id, page_route=body.page_route)


@router.post("/api/assistant/threads/{thread_id}/archive")
def archive(thread_id: str):
    if not get_thread(thread_id):
        raise HTTPException(status_code=404, detail="hilo no encontrado")
    archive_thread(thread_id)
    return {"ok": True}


@router.get("/api/assistant/threads/{thread_id}/messages")
def messages(thread_id: str):
    if not get_thread(thread_id):
        raise HTTPException(status_code=404, detail="hilo no encontrado")
    return {"messages": list_messages(thread_id)}


class SendBody(BaseModel):
    user_text: str
    page_context: dict[str, Any] | None = None
    allow_actions: bool = True


@router.post("/api/assistant/threads/{thread_id}/send")
async def send(thread_id: str, body: SendBody):
    t = get_thread(thread_id)
    if not t:
        raise HTTPException(status_code=404, detail="hilo no encontrado")
    if t["archived_at"]:
        raise HTTPException(status_code=409, detail="el hilo está archivado")

    async def _stream():
        async for event in run_turn(
            thread_id,
            user_text=body.user_text,
            page_context=body.page_context,
            allow_actions=body.allow_actions,
        ):
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(_stream(), media_type="text/event-stream")


class ConfirmBody(BaseModel):
    approve: bool = True


@router.post("/api/assistant/threads/{thread_id}/actions/{action_id}/confirm")
async def confirm(thread_id: str, action_id: str, body: ConfirmBody):
    if not get_thread(thread_id):
        raise HTTPException(status_code=404, detail="hilo no encontrado")
    result = await confirm_action(thread_id, action_id, approve=body.approve)
    if not result.get("ok") and result.get("status") == "error":
        raise HTTPException(status_code=404, detail=result.get("message") or "acción no encontrada")
    return result


class CapBody(BaseModel):
    cap_usd: float


@router.get("/api/assistant/cost-cap")
def get_cost_cap():
    from forven.assistant_session import _cost_cap_usd
    return {"cap_usd": _cost_cap_usd()}


@router.put("/api/assistant/cost-cap")
def set_cost_cap(body: CapBody):
    if body.cap_usd < 0:
        raise HTTPException(status_code=400, detail="el límite debe ser >= 0")
    from forven.db import kv_set
    kv_set("assistant.cost_cap_usd", body.cap_usd)
    return {"cap_usd": body.cap_usd}
