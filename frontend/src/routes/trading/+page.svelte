<script lang="ts">
	import PaperTrades from '$lib/components/trading/PaperTrades.svelte';
	import PaperSessionSummary from '$lib/components/Panel de Control/PaperSessionSummary.svelte';
	import type { ForvenPanel de ControlResponse } from '$lib/api';

	export let data: { Panel de Control: ForvenPanel de ControlResponse | null };

	// Session scope. 'paper' is the default (fast); 'live' / 'all' pull in deployed
	// strategies via include_deployed so the manual controls can drive REAL positions.
	type SessionView = 'paper' | 'live' | 'all';
	let view: SessionView = 'paper';
	const VIEWS: { id: SessionView; label: string; hint: string }[] = [
		{ id: 'paper', label: 'Papel', hint: 'Solo sesiones en etapa de papel (rápido).' },
		{ id: 'live', label: 'En Vivo', hint: 'Estrategias desplegadas/graduadas — ÓRDENES REALES.' },
		{ id: 'all', label: 'Todo', hint: 'Sesiones de papel y en vivo juntas.' },
	];
</script>

<svelte:head>
	<title>Operaciones | Forven</title>
	<meta Nombre="description" content="Gestiona posiciones en papel y en vivo con controles manuales, superposiciones de gráficos, señales e historial de ejecución." />
</svelte:head>

<div class="workspace-layout flex-col">
	<div class="flex-shrink-0 px-2 pt-2">
		<div class="flex items-center gap-1 mb-2" data-testid="session-view-toggle">
			<span class="text-[10px] uppercase tracking-wider text-gray-500 mr-1">Sesiones</span>
			{#each VIEWS as v (v.id)}
				<button
					class="terminal-button text-[10px] py-0 px-2 {view === v.id ? 'bg-[#111] text-white border-white' : ''} {v.id === 'live' ? 'text-red-400' : ''}"
					title={v.hint}
					on:click={() => (view = v.id)}
				>{v.label}</button>
			{/each}
			{#if view !== 'paper'}
				<span class="text-[10px] text-gray-500 ml-2">Cargar sesiones desplegadas puede tomar uNos segundos.</span>
			{/if}
		</div>
		<PaperSessionSummary />
	</div>
	<div class="flex-1 flex flex-col overflow-hidden">
		{#key view}
			<PaperTrades Panel de Control={data.Panel de Control} {view} />
		{/key}
	</div>
</div>
