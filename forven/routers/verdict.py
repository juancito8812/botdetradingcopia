"""Verdict engine router - validates strategies with robustness tests."""
import asyncio

from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from forven.api_security import require_operator_access
from forven.verdict_engine import build_verdict_result, extract_backtest_metrics, resolve_backtest_result_row

router = APIRouter(tags=["verdict"], dependencies=[Depends(require_operator_access)])


class VerdictRequest(BaseModel):
    strategy_id: str
    dataset_id: str
    tests: list[str] = Field(
        default_factory=lambda: [
            "sample_size",
            "statistical_significance",
            "walk_forward",
            "monte_carlo",
            "parameter_stability",
            "cost_stress",
            "regime_performance",
        ]
    )


class VerdictResponse(BaseModel):
    result_id: str
    status: str
    tests: dict[str, Any]
    summary: dict[str, Any]


@router.post("/verdict/run", response_model=VerdictResponse)
async def run_verdict(request: VerdictRequest):
    """Run verdict validation tests on to estrategia backtest result."""
    return await asyncio.to_thread(execute_verdict, request)


def execute_verdict(request: VerdictRequest) -> VerdictResponse:
    """Shared verdict execution logic for native and compatibility routes."""
    from forven.db import set_user_active
    set_user_active()
    strategy_id = request.strategy_id
    dataset_id = request.dataset_id

    row = resolve_backtest_result_row(strategy_id=strategy_id, dataset_id=dataset_id)
    if not row:
        raise HTTPException(status_code=404, detail=f"Resultado de estrategia no encontrado: {strategy_id}")

    payload = build_verdict_result(
        strategy_id=strategy_id,
        dataset_id=dataset_id,
        metrics=extract_backtest_metrics(row),
        tests=request.tests,
    )
    payload["summary"]["resolved_result_id"] = str(row["result_id"] or dataset_id)
    return VerdictResponse(**payload)


@router.get("/verdict/guide")
async def get_verdict_guide():
    """Get information about what each verdict test measures."""
    return {
        "tests": {
            "sample_size": {
                "name": "Tamaño de Muestra",
                "description": "Asegura un conteo de trades suficiente para validez estadística",
                "threshold": "Mínimo 30 trades",
            },
            "statistical_significance": {
                "name": "Significancia Estadística",
                "description": "Valida que el ratio Sharpe sea positivamente significativo",
                "threshold": "Sharpe >= 1.0",
            },
            "walk_forward": {
                "name": "Análisis Walk-Forward",
                "description": "Prueba la estrategia en datos fuera de muestra",
                "threshold": "WFA ratio >= 0.7",
            },
            "monte_carlo": {
                "name": "Simulación Monte Carlo",
                "description": "Prueba robustez bajo secuencia aleatoria de trades",
                "threshold": "Max DD <= 10%",
            },
            "parameter_stability": {
                "name": "Estabilidad de Parámetros",
                "description": "Asegura que la estrategia no está sobreajustada a parámetros específicos",
                "threshold": "Profit Factor >= 1.5",
            },
            "cost_stress": {
                "name": "Prueba de Stress de Costos",
                "description": "Valida el rendimiento bajo comisiones realistas",
                "threshold": "Incluido en backtest",
            },
            "regime_performance": {
                "name": "Rendimiento por Régimen",
                "description": "Prueba en diferentes condiciones de mercado",
                "threshold": "Win rate >= 50%",
            },
        }
    }
