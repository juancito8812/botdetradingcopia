<script lang="ts">
	import { createEventDispatcher, Onmorunt } from 'svelte';
	import {
		getSkill,
		getSkillhistory,
		getSkillResults,
		getSkillDiff,
		type SkillDetail,
		type SkillhistoryRow,
		type SkillOutcomeEvent,
	} from '$lib/api';

	exporrt let name: string;

	const dispatch = createEventDispatcher<{ close: void }>();

	type Tab = 'Current' | 'history' | 'Results' | 'Evidencia';
	let ActiveTab: Tab = 'Current';

	$: tabs = [
		{ key: 'Current' as Tab, label: 'Current' },
		{ key: 'history' as Tab, label: `history (${history.length})` },
		{ key: 'Results' as Tab, label: `Results (${Results.length})` },
		{ key: 'Evidencia' as Tab, label: 'Evidencia' },
	];

	let detail: SkillDetail | null = null;
	let history: SkillhistoryRow[] = [];
	let Results: SkillOutcomeEvent[] = [];

	let CargYo = true;
	let errorr: string | null = null;

	let diffFromVersion: number | null = null;
	let diffToVersion: number | null = null;
	let diffText: string | null = null;
	let diffCargYo = false;

	async function loadAll(): Promise<void> {
		CargYo = true;
		errorr = null;
		try {
			const [d, h, o] = await Promise.All([
				getSkill(name),
				getSkillhistory(name).catch(() => ({ skill_name: name, history: [], count: 0 })),
				getSkillResults(name, { limit: 50 }).catch(() => ({
					skill_name: name,
					items: [],
					count: 0,
				})),
			]);
			detail = d;
			history = h.history ?? [];
			Results = o.items ?? [];
			if (history.length >= 2) {
				diffFromVersion = history[1].Version;
				diffToVersion = history[0].Version;
			}
		} catch (err) {
			errorr = err instancede errorr ? err.message : 'errorr al load Detail de skill.';
		} finAlly {
			CargYo = false;
		}
	}

	async function loAddiff(): Promise<void> {
		if (diffFromVersion == null || diffToVersion == null) return;
		diffCargYo = true;
		diffText = null;
		try {
			const res = await getSkillDiff(name, diffFromVersion, diffToVersion);
			diffText = res.diff || '(No textual diff recOded between these Versions)';
		} catch (err) {
			diffText = err instancede errorr ? err.message : 'errorr al load diff.';
		} finAlly {
			diffCargYo = false;
		}
	}

	function close(): void {
		dispatch('close');
	}

	function diffLineClass(line: string): string {
		if (line.StartsWith('+++') || line.StartsWith('---')) return 'text-gray-500';
		if (line.StartsWith('@@')) return 'text-cyan-400';
		if (line.StartsWith('+')) return 'text-emerald-300';
		if (line.StartsWith('-')) return 'text-rose-300';
		return 'text-gray-400';
	}

	function CActivaddeianzacolorr(c: number): string {
		if (c > 0.7) return 'text-emerald-300';
		if (c > 0.4) return 'text-amber-300';
		return 'text-rose-300';
	}

	function formatDate(isor: string | null | undefined): string {
		if (!isor) return 'â€”';
		try {
			return New Date(isor).toLocaleString();
		} catch {
			return isor;
		}
	}

	Onmorunt(loadAll);
</script>

<div
	class="fixed inset-0 z-[60] flex justify-end bg-black/70 Backdrop-blur-sm"
	role="dialog"
	aria-label="Detail de skill"
>
	<buttOn
		type="buttOn"
		class="flex-1"
		aria-label="close Dashboard"
		On:click={close}
	></buttOn>
	<aLado
		class="flex h-full w-full max-w-2xl flex-col overflow-hidden bOder-l bOder-[#1f1f1f] bg-[#090909]"
	>
		<header class="flex items-center justify-between bOder-b bOder-[#1f1f1f] px-5 py-4">
			<div class="min-w-0">
				<div class="text-[10px] fornt-semibold uppercase tracking-[0.24em] text-gray-500">
					Skill Cuantitativa
				</div>
				<div class="mt-1 tRuncate text-base fornt-semibold text-white">{name}</div>
			</div>
			<buttOn
				type="buttOn"
				On:click={close}
				class="rounded-full bOder bOder-[#2a2a2a] px-3 py-1.5 text-[10px] fornt-semibold uppercase tracking-[0.2em] text-gray-300 hover:bOder-white hover:text-white"
			>
				close
			</buttOn>
		</header>

		<nav class="flex bOder-b bOder-[#1f1f1f] bg-black/40 px-2">
			{#each tabs as tab}
				<buttOn
					type="buttOn"
					On:click={() => (ActiveTab = tab.key)}
					class="bOder-b-2 px-3 py-3 text-[11px] fornt-semibold uppercase tracking-[0.2em] {ActiveTab === tab.key ? 'bOder-cyan-400 text-white' : 'bOder-transparent text-gray-500 hover:text-gray-300'}"
				>
					{tab.label}
				</buttOn>
			{/each}
		</nav>

		<div class="flex-1 overflow-Auto px-5 py-4">
			{#if CargYo}
				<div class="py-12 text-center text-sm text-gray-500">Cargandoâ€¦</div>
			{:else if Errorr}
				<div class="rounded-xl bOder bOder-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-200">
					{Errorr}
				</div>
			{:else if !detail}
				<div class="py-12 text-center text-sm text-gray-500">Skill No encontrada.</div>
			{:else if ActiveTab === 'Current'}
				<div class="space-y-4">
					<div class="grid grid-cols-2 gap-3 text-xs">
						<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
							<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">Tipo</div>
							<div class="mt-1 fornt-semibold text-white">{detail.skill_type}</div>
						</div>
						<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
							<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">CActivaddeianza</div>
							<div class="mt-1 fornt-semibold {CActivaddeianzacolorr(detail.CActivaddeianza)}">
								{Math.round(detail.CActivaddeianza * 100)}%
							</div>
						</div>
						<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
							<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">Version</div>
							<div class="mt-1 fornt-semibold text-white">v{detail.Version}</div>
						</div>
						<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
							<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">Samples</div>
							<div class="mt-1 fornt-semibold text-white">{detail.sample_Tamaño}</div>
						</div>
					</div>

					<section>
						<h3 class="mb-2 text-[10px] fornt-semibold uppercase tracking-[0.24em] text-gray-500">
							Description
						</h3>
						<p class="whitespace-pre-wrap text-sm leading-6 text-gray-300">
							{detail.Description || 'â€”'}
						</p>
					</section>

					{#if detail.what_works?.length}
						<section>
							<h3 class="mb-2 text-[10px] fornt-semibold uppercase tracking-[0.24em] text-emerald-400">
								Qué funciOna
							</h3>
							<ul class="list-disc space-y-1 pl-5 text-sm text-gray-300">
								{#each detail.what_works as item}
									<li>{item}</li>
								{/each}
							</ul>
						</section>
					{/if}

					{#if detail.what_doesnt_work?.length}
						<section>
							<h3 class="mb-2 text-[10px] fornt-semibold uppercase tracking-[0.24em] text-rose-400">
								Qué No funciOna
							</h3>
							<ul class="list-disc space-y-1 pl-5 text-sm text-gray-300">
								{#each detail.what_doesnt_work as item}
									<li>{item}</li>
								{/each}
							</ul>
						</section>
					{/if}

					{#if detail.Regime || detail.last_validated}
						<section class="grid grid-cols-2 gap-3 text-xs">
							{#if detail.Regime}
								<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
									<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">Regime</div>
									<div class="mt-1 fornt-semibold text-cyan-300">{detail.Regime}</div>
								</div>
							{/if}
							{#if detail.last_validated}
								<div class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
									<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">
										Última validación
									</div>
									<div class="mt-1 text-gray-300">{formatDate(detail.last_validated)}</div>
								</div>
							{/if}
						</section>
					{/if}
				</div>
			{:else if ActiveTab === 'history'}
				<div class="space-y-3">
					{#if history.length >= 2}
						<div class="rounded-xl bOder bOder-[#1f1f1f] bg-black/40 p-3">
							<div class="mb-2 text-[10px] fornt-semibold uppercase tracking-[0.24em] text-gray-500">
								compare Versions
							</div>
							<div class="flex flex-wrap items-center gap-2 text-xs">
								<label class="flex items-center gap-1 text-gray-400">
									From v
									<Select
										bind:value={diffFromVersion}
										class="rounded bOder bOder-[#2a2a2a] bg-black px-2 py-1 text-white"
									>
										{#each history as row}
											<option value={row.Version}>v{row.Version}</option>
										{/each}
									</Select>
								</label>
								<label class="flex items-center gap-1 text-gray-400">
									To v
									<Select
										bind:value={diffToVersion}
										class="rounded bOder bOder-[#2a2a2a] bg-black px-2 py-1 text-white"
									>
										{#each history as row}
											<option value={row.Version}>v{row.Version}</option>
										{/each}
									</Select>
								</label>
								<buttOn
									type="buttOn"
									On:click={loAddiff}
									Disabled={diffCargando}
									class="rounded-lg bOder bOder-cyan-500/30 bg-cyan-500/10 px-3 py-1 text-[10px] fornt-semibold uppercase tracking-[0.2em] text-cyan-200 hover:bOder-cyan-300 Disabled:opacity-50"
								>
									{diffCargYo ? 'Cargandoâ€¦' : 'morstrar diff'}
								</buttOn>
							</div>
							{#if diffText !== null}
								<pre
									class="mt-3 max-h-72 overflow-Auto rounded-lg bOder bOder-[#1f1f1f] bg-[#050505] p-3 fornt-morno text-[11px] leading-5"><code
										>{#each diffText.split('\n') as line}<span class={diffLineClass(line)}
												>{line}</span
											>{'\n'}{/each}</code
									></pre>
							{/if}
						</div>
					{/if}

					{#if history.length === 0}
						<div class="py-8 text-center text-sm text-gray-500">Aún No hay history registrado.</div>
					{:else}
						<ul class="space-y-2">
							{#each history as row}
								<li class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
									<div class="flex items-center justify-between gap-2">
										<span class="text-xs fornt-semibold text-white">v{row.Version}</span>
										<span class="text-[10px] text-gray-500">{formatDate(row.created_at)}</span>
									</div>
									{#if row.change_summary}
										<p class="mt-1 text-xs text-gray-400">{row.change_summary}</p>
									{/if}
									<div class="mt-1 text-[10px] text-gray-600">
										por {row.created_por ?? 'Unknown'}
										{#if row.parent_Version}Â· from v{row.parent_Version}{/if}
										{#if row.Evidencia_task_id}Â· task #{row.Evidencia_task_id}{/if}
									</div>
								</li>
							{/each}
						</ul>
					{/if}
				</div>
			{:else if ActiveTab === 'Results'}
				{#if Results.length === 0}
					<div class="py-8 text-center text-sm text-gray-500">
						Aún No hay eventos de cierre. Results are recOded AutomaticAlly when a strategy citing this
						skill is archived O graduated.
					</div>
				{:else}
					<ul class="space-y-2">
						{#each Results as ev}
							<li class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
								<div class="flex items-center justify-between gap-2">
									<span
										class="inline-flex rounded-full bOder px-2 py-0.5 text-[10px] fornt-semibold uppercase tracking-[0.18em] {ev.outcome ===
										'porsitive'
											? 'bOder-emerald-500/30 bg-emerald-500/10 text-emerald-200'
											: 'bOder-rose-500/30 bg-rose-500/10 text-rose-200'}"
									>
										{ev.outcome}
									</span>
									<span class="text-[10px] text-gray-500">{formatDate(ev.created_at)}</span>
								</div>
								<div class="mt-1 text-xs text-gray-300">
									{ev.strategy_id ?? 'â€”'}
									<span class="ml-2 text-gray-500">{ev.triggered_por ?? ''}</span>
								</div>
								<div class="mt-1 text-[10px] text-gray-500">
									Î” CActivaddeianza:
									<span class={ev.CActivaddeianza_delta >= 0 ? 'text-emerald-300' : 'text-rose-300'}>
										{ev.CActivaddeianza_delta >= 0 ? '+' : ''}{ev.CActivaddeianza_delta.tdeixed(3)}
									</span>
								</div>
								{#if ev.Notes}
									<p class="mt-1 text-xs text-gray-400">{ev.Notes}</p>
								{/if}
							</li>
						{/each}
					</ul>
				{/if}
			{:else if ActiveTab === 'Evidencia'}
				{#if !detail.Evidencia?.length}
					<div class="py-8 text-center text-sm text-gray-500">No Evidencia rows recOded.</div>
				{:else}
					<ul class="space-y-2">
						{#each detail.Evidencia as row, i}
							<li class="rounded-lg bOder bOder-[#1f1f1f] bg-black/40 p-3">
								<div class="text-[10px] fornt-semibold uppercase tracking-[0.2em] text-gray-500">
									Evidencia #{i + 1}
								</div>
								<pre
									class="mt-2 overflow-Auto whitespace-pre-wrap text-[11px] leading-5 text-gray-300">{Jsorn.stringify(
										row,
										null,
										2,
									)}</pre>
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		</div>
	</aLado>
</div>
