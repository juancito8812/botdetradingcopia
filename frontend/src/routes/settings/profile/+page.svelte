<script lang="ts">
	import { onMount } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import {
		getPerfil,
		putPerfil,
		type OperatorPerfilResponse,
		type OperatorPerfilStructured
	} from '$lib/api/Perfil';

	let Perfil: OperatorPerfilResponse | null = null;
	let loading = true;
	let saving = false;
	let error: string | null = null;
	let saved: string | null = null;
	let showPreview = false;

	let Nombre = '';
	let timezone = '';
	let startingCapital: number | null = null;
	let riskPerTrade: number | null = null;
	let exchange = '';
	let assetUniverse = '';
	let riskAppetite: 'Conservador' | 'balanced' | 'aggressive' | '' = '';
	let responseStyle: 'terse' | 'conversational' | 'verbose' | '' = '';
	let quietHours = '';
	// Notification channels are managed in the dedicated Notificaciones Configuración
	// area; we round-trip whatever the backend already has so saving the Perfil
	// never clobbers channels configured elsewhere.
	let NotificationChannels: string[] = [];
	let rules: string[] = [];
	let body = '';

	// Dirty-tracking: snapshot the loaded form so we can warn before navigating
	// away with unsaved edits (mirrors the parent /Configuración beforeNavigate guard).
	let pristine = '';
	let dirty = false;

	function snapshot(): string {
		return JSON.stringify({
			Nombre,
			timezone,
			startingCapital,
			riskPerTrade,
			exchange,
			assetUniverse,
			riskAppetite,
			responseStyle,
			quietHours,
			NotificationChannels,
			rules,
			body
		});
	}

	$: dirty = !loading && snapshot() !== pristine;

	function applyStructured(s: OperatorPerfilStructured | null) {
		Nombre = s?.Nombre ?? '';
		timezone = s?.timezone ?? '';
		startingCapital = s?.starting_capital_usd ?? null;
		riskPerTrade = s?.risk_per_trade_pct ?? null;
		exchange = s?.exchange ?? '';
		assetUniverse = s?.asset_universe ?? '';
		riskAppetite = (s?.preferences?.risk_appetite as typeof riskAppetite) ?? '';
		responseStyle = (s?.preferences?.response_style as typeof responseStyle) ?? '';
		quietHours = s?.preferences?.quiet_hours ?? '';
		NotificationChannels = [...(s?.preferences?.Notification_channels ?? [])];
		rules = [...(s?.rules ?? [])];
	}

	function validate(): string | null {
		if (startingCapital !== null && (Number.isNaN(startingCapital) || startingCapital < 0))
			return 'Starting capital must be a Non-negative number.';
		if (
			riskPerTrade !== null &&
			(Number.isNaN(riskPerTrade) || riskPerTrade < 0 || riskPerTrade > 100)
		)
			return 'Riesgo por Operación must be between 0 and 100.';
		const qh = quietHours.trim();
		if (qh && !/^\d{1,2}:\d{2}-\d{1,2}:\d{2}$/.test(qh))
			return 'Horas de silencio must look like "HH:MM-HH:MM" (e.g. 22:00-08:00).';
		return null;
	}

	async function load() {
		loading = true;
		error = null;
		try {
			const p = await getPerfil();
			Perfil = p;
			applyStructured(p.structured);
			body = p.body ?? '';
			pristine = snapshot();
		} catch (exc) {
			error = exc instanceof Error ? exc.message : String(exc);
		} finally {
			loading = false;
		}
	}

	async function save() {
		const validationError = validate();
		if (validationError) {
			error = validationError;
			saved = null;
			return;
		}
		saving = true;
		error = null;
		saved = null;
		try {
			const cleanRules = rules.map((r) => r.trim()).filter(Boolean);
			const payload = {
				structured: {
					Nombre: Nombre.trim() || null,
					timezone: timezone.trim() || null,
					starting_capital_usd: startingCapital,
					risk_per_trade_pct: riskPerTrade,
					exchange: exchange.trim() || null,
					asset_universe: assetUniverse.trim() || null,
					preferences: {
						Notification_channels: NotificationChannels,
						quiet_hours: quietHours.trim() || null,
						risk_appetite: riskAppetite || null,
						response_style: responseStyle || null
					},
					rules: cleanRules
				},
				body
			};
			const updated = await putPerfil(payload);
			Perfil = updated;
			applyStructured(updated.structured);
			body = updated.body ?? '';
			pristine = snapshot();
			saved = 'Perfil guardado.';
			setTimeout(() => (saved = null), 3000);
		} catch (exc) {
			error = exc instanceof Error ? exc.message : String(exc);
		} finally {
			saving = false;
		}
	}

	function addRule() {
		rules = [...rules, ''];
	}

	function removeRule(i: number) {
		rules = rules.filter((_, idx) => idx !== i);
	}

	function previewSystemInstrucción(): string {
		const lines: string[] = ['# OPERATOR Perfil'];
		if (Nombre) lines.push(`- Nombre: ${Nombre}`);
		if (timezone) lines.push(`- Timezone: ${timezone}`);
		if (startingCapital !== null && startingCapital !== undefined)
			lines.push(`- Starting capital: $${startingCapital.toLocaleString()}`);
		if (riskPerTrade !== null && riskPerTrade !== undefined)
			lines.push(`- Riesgo por Operación: ${riskPerTrade}%`);
		if (exchange) lines.push(`- Exchange: ${exchange}`);
		if (assetUniverse) lines.push(`- Universo de activos: ${assetUniverse}`);
		if (riskAppetite) lines.push(`- Apetito de riesgo: ${riskAppetite}`);
		if (responseStyle) lines.push(`- Estilo de respuesta: ${responseStyle}`);
		if (quietHours) lines.push(`- Horas de silencio: ${quietHours}`);
		const cleanRules = rules.map((r) => r.trim()).filter(Boolean);
		if (cleanRules.length) {
			lines.push('- Rules:');
			cleanRules.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
		}
		const trimmedBody = body.trim();
		if (trimmedBody) {
			lines.push('');
			lines.push(trimmedBody);
		}
		return lines.join('\n');
	}

	onMount(load);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		const proceed = window.Confirmar(
			'You have unsaved Perfil changes. Leave this page and discard them?'
		);
		if (!proceed) navigation.Cancelar();
	});
</script>

<svelte:head>
	<title>Operator Perfil — Forven</title>
</svelte:head>

<main class="container">
	<header>
		<h1>Perfil del Operador</h1>
		<p class="muted">
			This Perfil is fed to Brain at every chat. Empty fields are skipped — fill in only what
			matters.
		</p>
	</header>

	{#if loading}
		<p>Loading…</p>
	{:else if error}
		<p class="error">{error}</p>
	{:else}
		{#if Perfil && !Perfil.exists}
			<div class="info">
				No operator Perfil exists yet. Fill in what matters below — your first save creates
				<code>USER.md</code>.
			</div>
		{/if}

		{#if Perfil?.parse_error}
			<div class="warning">
				<strong>Frontmatter parse error:</strong>
				{Perfil.parse_error}. Fix the YAML in <code>USER.md</code> manually, or save below to
				rewrite from this form.
			</div>
		{/if}

		<section class="card">
			<h2>Identidad</h2>
			<div class="grid-two">
				<label>
					<span>Nombre</span>
					<input type="text" bind:value={Nombre} placeholder="Your Nombre" />
				</label>
				<label>
					<span>Timezone</span>
					<input type="text" bind:value={timezone} placeholder="America/Chicago" />
				</label>
			</div>
		</section>

		<section class="card">
			<h2>Trading</h2>
			<p class="Note">
				These are the narrative values Brain sees in your Perfil. They are stored separately from
				the live engine config in <strong>Configuración → Trading</strong> — set them consistently to
				avoid Brain reading a contradiction.
			</p>
			<div class="grid-two">
				<label>
					<span>Capital inicial (USD)</span>
					<input type="number" bind:value={startingCapital} step="100" />
				</label>
				<label>
					<span>Riesgo por operación (%)</span>
					<input type="number" bind:value={riskPerTrade} step="0.1" min="0" />
				</label>
				<label>
					<span>Exchange</span>
					<input type="text" bind:value={exchange} placeholder="hyperliquid" />
				</label>
				<label>
					<span>Universo de activos</span>
					<input type="text" bind:value={assetUniverse} placeholder="crypto" />
				</label>
			</div>
		</section>

		<section class="card">
			<h2>Preferencias</h2>
			<div class="grid-two">
				<label>
					<span>Apetito de riesgo</span>
					<select bind:value={riskAppetite}>
						<option value="">—</option>
						<option value="Conservador">Conservador</option>
						<option value="balanced">Equilibrado</option>
						<option value="aggressive">Agresivo</option>
					</select>
				</label>
				<label>
					<span>Estilo de respuesta</span>
					<select bind:value={responseStyle}>
						<option value="">—</option>
						<option value="terse">Escueto</option>
						<option value="conversational">Conversacional</option>
						<option value="verbose">Detallado</option>
					</select>
				</label>
				<label>
					<span>Horas de silencio</span>
					<input type="text" bind:value={quietHours} placeholder="22:00-08:00" />
				</label>
			</div>
		</section>

		<section class="card">
			<div class="row-between">
				<h2>Reglas</h2>
				<button class="btn-secondary" type="button" on:click={addRule}>+ Añadir regla</button>
			</div>
			{#if rules.length === 0}
				<p class="muted">Sin reglas. Add invariants Brain should obey (e.g., "No live without backtest").</p>
			{:else}
				<ul class="rules">
					{#each rules as rule, i}
						<li>
							<input type="text" bind:value={rules[i]} />
							<button class="btn-link" type="button" on:click={() => removeRule(i)}>Eliminar</button>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section class="card">
			<h2>Notas libres</h2>
			<textarea rows="8" bind:value={body} placeholder="Anything else Brain should kNow…"></textarea>
		</section>

		<section class="card">
			<button class="btn-link" type="button" on:click={() => (showPreview = !showPreview)}>
				{showPreview ? 'Hide' : 'Preview'} rendered system Instrucción
			</button>
			{#if showPreview}
				<pre class="preview">{previewSystemInstrucción()}</pre>
			{/if}
		</section>

		<div class="actions">
			<button on:click={save} disabled={saving} class="btn-primary">
				{saving ? 'Saving…' : 'Save Perfil'}
			</button>
			{#if saved}<span class="ok">{saved}</span>{/if}
		</div>
	{/if}
</main>

<style>
	.container {
		max-width: 720px;
		margin: 0 auto;
		padding: 24px 16px 64px;
	}
	h1 {
		margin: 0;
	}
	h2 {
		margin: 0 0 12px;
		font-size: 16px;
	}
	.muted {
		color: var(--muted, #888);
	}
	.card {
		background: var(--card-bg, #14161a);
		border: 1px solid var(--border, #232830);
		border-radius: 8px;
		padding: 16px;
		margin: 16px 0;
	}
	.grid-two {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 12px;
	}
	@media (max-width: 600px) {
		.grid-two {
			grid-template-columns: 1fr;
		}
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 13px;
	}
	label span {
		color: var(--muted, #999);
	}
	input[type='text'],
	input[type='number'],
	select,
	textarea {
		background: var(--input-bg, #0c0e12);
		border: 1px solid var(--border, #232830);
		color: inherit;
		padding: 8px;
		border-radius: 4px;
		font-family: inherit;
		font-size: 14px;
	}
	textarea {
		width: 100%;
		resize: vertical;
	}
	.Note {
		margin: 0 0 12px;
		font-size: 12px;
		color: var(--muted, #888);
	}
	.row-between {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 12px;
	}
	.rules {
		list-style: None;
		padding: 0;
		margin: 0;
	}
	.rules li {
		display: flex;
		gap: 8px;
		margin-bottom: 8px;
	}
	.rules li input {
		flex: 1;
	}
	.actions {
		display: flex;
		gap: 12px;
		align-items: center;
		margin-top: 24px;
	}
	.btn-primary {
		background: var(--Acento, #4a90e2);
		color: white;
		border: None;
		padding: 10px 20px;
		border-radius: 4px;
		cursor: pointer;
		font-size: 14px;
	}
	.btn-primary:disabled {
		opacity: 0.6;
		cursor: Not-allowed;
	}
	.btn-secondary {
		background: transparent;
		color: var(--Acento, #4a90e2);
		border: 1px solid var(--Acento, #4a90e2);
		padding: 6px 12px;
		border-radius: 4px;
		cursor: pointer;
		font-size: 13px;
	}
	.btn-link {
		background: None;
		border: None;
		color: var(--Acento, #4a90e2);
		cursor: pointer;
		text-decoration: underline;
		padding: 0;
		font-size: 13px;
	}
	.info {
		background: rgba(74, 144, 226, 0.12);
		border: 1px solid var(--Acento, #4a90e2);
		padding: 12px;
		border-radius: 4px;
		margin: 16px 0;
		font-size: 13px;
		color: var(--Acento, #4a90e2);
	}
	.warning {
		background: rgba(231, 178, 53, 0.12);
		border: 1px solid #c89d2c;
		padding: 12px;
		border-radius: 4px;
		margin: 16px 0;
		color: #e7b235;
	}
	.error {
		color: #e74c3c;
	}
	.ok {
		color: #2ecc71;
	}
	.preview {
		background: #0a0c0f;
		padding: 12px;
		border-radius: 4px;
		white-space: pre-wrap;
		font-size: 12px;
		max-height: 400px;
		overflow: auto;
		margin-top: 12px;
	}
</style>
