"""OpenAI OAuth — PKCE Authorization Code flow with local HTTP callback."""

import http.server
import threading
import time
import urllib.parse
import webbrowser

import httpx
from rich.console import Console
from rich.prompt import Prompt

from forven.util import generate_pkce, generate_state, is_remote

console = Console()

CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
AUTH_URL = "https://auth.openai.com/oauth/authorize"
TOKEN_URL = "https://auth.openai.com/oauth/token"
REDIRECT_URI = "http://localhost:1455/auth/callback"
CALLBACK_PORT = 1455
SCOPES = "openid profile email offline_access"


def _first_query_value(params: dict[str, list[str]], key: str) -> str | None:
    value = params.get(key)
    if not isinstance(value, list) or not value:
        return None
    first = value[0]
    if first is None:
        return None
    return str(first)


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that captures the OAuth callback code."""

    code = None
    state = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        code = _first_query_value(params, "code")

        if parsed.path == "/auth/callback" and code:
            _CallbackHandler.code = code
            _CallbackHandler.state = _first_query_value(params, "state")
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h2>Authenticated! You can close this tab.</h2></body></html>")
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress server logs


def _build_auth_url(state: str, challenge: str) -> str:
    """Build the full authorization URL."""
    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "state": state,
        "id_token_add_organizations": "true",
        "codex_cli_simplified_flow": "true",
    }
    return f"{AUTH_URL}?{urllib.parse.urlencode(params)}"


def login() -> dict:
    """Run OpenAI PKCE OAuth flow. Returns credential dict."""
    verifier, challenge = generate_pkce()
    state = generate_state()
    auth_url = _build_auth_url(state, challenge)

    console.print("[bold]OpenAI OAuth — Flujo de Código de Autorización[/bold]\n")

    if is_remote():
        # SSH/headless: show URL, prompt for manual paste
        console.print(f"Abra esta URL en su navegador:\n[bold cyan]{auth_url}[/bold cyan]\n")
        console.print("Después de autorizar, será redirigido to localhost (fallará).")
        console.print("Copie la URL de redirección completa from la barra de direcciones.\n")
        redirect_url = Prompt.ask("Paste the redirect URL")
        parsed = urllib.parse.urlparse(redirect_url)
        params = urllib.parse.parse_qs(parsed.query)
        error = _first_query_value(params, "error")
        if error:
            desc = _first_query_value(params, "error_description") or ""
            raise RuntimeError(f"Error OAuth: {error} — {desc}")
        code = _first_query_value(params, "code")
        if not code:
            raise RuntimeError("No se encontró código de autorización en la URL.")
    else:
        # Local: start callback server
        _CallbackHandler.code = None
        _CallbackHandler.state = None
        server = http.server.HTTPServer(("127.0.0.1", CALLBACK_PORT), _CallbackHandler)
        server.timeout = 120

        thread = threading.Thread(target=server.handle_request, daemon=True)
        thread.start()

        console.print("Abriendo navegador para autorización de OpenAI...\n")
        webbrowser.open(auth_url)

        # Wait for callback
        console.print("[dim]Esperando autorización...[/dim]")
        thread.join(timeout=120)
        server.server_close()

        code = _CallbackHandler.code
        if not code:
            # Fallback to manual paste
            console.print("\n[yellow]La respuesta del navegador no llegó. Usando método manual.[/yellow]")
            console.print(f"\nOpen: [bold cyan]{auth_url}[/bold cyan]\n")
            redirect_url = Prompt.ask("Paste the redirect URL")
            parsed = urllib.parse.urlparse(redirect_url)
            params = urllib.parse.parse_qs(parsed.query)
            code = _first_query_value(params, "code")
            if not code:
                raise RuntimeError("No se encontró código de autorización.")

    # Exchange code for tokens
    console.print("[dim]Intercambiando código by tokens...[/dim]")
    resp = httpx.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "client_id": CLIENT_ID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": REDIRECT_URI,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()

    access_token = data["access_token"]
    expires = int(time.time() * 1000 + data.get("expires_in", 86400) * 1000)

    # Extract account ID from JWT (H-S5: validated via safe helper)
    from forven.auth import safe_extract_chatgpt_account_id
    account_id = safe_extract_chatgpt_account_id(access_token)

    profile = {
        "type": "oauth",
        "provider": "openai",
        "access": access_token,
        "refresh": data.get("refresh_token", ""),
        "expires": expires,
    }
    if account_id:
        profile["accountId"] = account_id

    console.print("[bold green]¡Autorizado![/bold green]")
    return profile
