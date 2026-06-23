"""MiniMax OAuth — Device code flow with PKCE."""

import time

import httpx
from rich.console import Console

from forven.util import generate_pkce, generate_state

console = Console()

CLIENT_ID = "78257093-7e40-4613-99e0-527b14b39113"
CODE_URL = "https://api.minimax.io/oauth/code"
TOKEN_URL = "https://api.minimax.io/oauth/token"
SCOPES = "group_id profile model.completion"


def login() -> dict:
    """Run MiniMax device code OAuth flow. Returns credential dict."""
    verifier, challenge = generate_pkce()
    state = generate_state()

    # Step 1: Request device code
    console.print("[bold]MiniMax OAuth — Flujo de Código de Dispositivo[/bold]\n")

    resp = httpx.post(
        CODE_URL,
        data={
            "response_type": "code",
            "client_id": CLIENT_ID,
            "scope": SCOPES,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "state": state,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=30,
        follow_redirects=True,
    )
    resp.raise_for_status()
    data = resp.json()

    verification_url = data.get("verification_url") or data.get("verification_uri")
    user_code = data["user_code"]
    poll_interval = data.get("interval", 2000) / 1000.0 if data.get("interval", 2) > 100 else data.get("interval", 2)

    console.print(f"Visite: [bold cyan]{verification_url}[/bold cyan]")
    console.print("[dim]El código de usuario está pre-llenado en la URL. Just click 'Authorize'.[/dim]\n")
    console.print(f"Su código (si es necesario): [bold yellow]{user_code}[/bold yellow]\n")
    console.print("[dim]Esperando autorización...[/dim]")

    # Step 2: Poll for token
    poll_interval_ms = poll_interval * 1000
    max_attempts = 300  # 10 minutes at 2s intervals

    for attempt in range(max_attempts):
        time.sleep(poll_interval_ms / 1000)

        try:
            token_resp = httpx.post(
                TOKEN_URL,
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:user_code",
                    "client_id": CLIENT_ID,
                    "user_code": user_code,
                    "code_verifier": verifier,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=30,
                follow_redirects=True,
            )

            if token_resp.status_code == 200:
                token_data = token_resp.json()
                if token_data.get("access_token"):
                    console.print("[bold green]¡Autorizado![/bold green]")

                    expires = token_data.get("expired_in")  # MiniMax: unix ms timestamp
                    if not expires and token_data.get("expires_in"):
                        expires = int(time.time() * 1000 + token_data["expires_in"] * 1000)

                    return {
                        "type": "oauth",
                        "provider": "minimax",
                        "access": token_data["access_token"],
                        "refresh": token_data.get("refresh_token", ""),
                        "expires": expires,
                    }

            # Not ready yet — back off
            error = token_resp.json().get("error", "") if token_resp.status_code == 400 else ""
            if error == "authorization_pending":
                pass  # Keep polling
            elif error == "slow_down":
                poll_interval_ms = min(poll_interval_ms * 1.5, 10000)
            elif error == "expired_token":
                raise RuntimeError("El código de dispositivo expiró. Intente de nuevo.")
            elif error == "access_denied":
                raise RuntimeError("Autorización denegada by el usuario.")

        except httpx.HTTPError:
            pass  # Network error, retry

    raise RuntimeError("Tiempo de espera agotado para autorización de MiniMax.")
