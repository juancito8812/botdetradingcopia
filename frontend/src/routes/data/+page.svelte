<script lang="ts">
	import { onMount } from 'svelte';
	import DataPanel from '$lib/components/research/DataPanel.svelte';
	import DataInspector from '$lib/components/research/DataInspector.svelte';
	import CoverageMatrix from '$lib/components/research/CoverageMatrix.svelte';
	import SourceHealth from '$lib/components/research/SourceHealth.svelte';
	import QualityLeaderboard from '$lib/components/research/QualityLeaderboard.svelte';
	import StorageMaintenance from '$lib/components/research/StorageMaintenance.svelte';
	import SeriesDrillDown from '$lib/components/research/SeriesDrillDown.svelte';
	import DataActivityLog from '$lib/components/research/DataActivityLog.svelte';
	import {
		getConjuntos de Datos,
		getIngestionRuns,
		getDataQualityExtended,
		getDataEngineStatus,
		planDataEngineBackfill,
		executeDataEngineBackfill,
		getConfiguración,
		type Dataset,
		type DataQualityExtended,
		type DataEngineStatus,
		type DataEngineBackfillPlan,
		type DataEngineBackfillResult,
		type IngestionRun,
		type ForvenConfiguración,
	} from '$lib/api';
	import { dataFetchState, clearDataFetchTask } from '$lib/stores/dataFetch';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';

	let loading = true;
	let refreshing = false;
	let error: string | null = null;
	let remoteDataConfigured = false;
	let drillSeries: { symbol: string; timeframe: string } | null = null;
	let remoteDataUrl: string | null = null;
	let remoteDataError: string | null = null;

	let Conjuntos de Datos: Dataset[] = [];
	let runs: IngestionRun[] = [];
	let runsReconstructed = false;
	let seleccionadasDataset: Dataset | null = null;
	let quality: DataQualityExtended | null = null;
	let dataEngineStatus: DataEngineStatus | null = null;
	let dataEnginePlan: DataEngineBackfillPlan | null = null;
	let qualityLoading = false;
	let dataEngineLoading = false;
	let dataEngineError: string | null = null;
	let dataEngineExecuting = false;
	let dataEngineExecResult: DataEngineBackfillResult | null = null;
	let inspectorMode: 'Detalles' | 'fetch' = 'Detalles';

	type DataTab = 'Reanudarn' | 'Conjuntos de Datos' | 'maintenance' | 'data-log';
	const TABS: { id: DataTab; label: string }[] = [
		{ id: 'Reanudarn', label: 'Reanudarn' },
		{ id: 'Conjuntos de Datos', label: 'Conjuntos de Datos' },
		{ id: 'maintenance', label: 'Maintenance' },
		{ id: 'data-log', label: 'Data Log' },
	];
	const initialTab = $page.url.searchParams.get('tab');
	let activeTab: DataTab = TABS.some((t) => t.id === initialTab) ? (initialTab as DataTab) : 'Reanudarn';

	function selectTab(tab: DataTab): void {
		activeTab = tab;
		const url = new URL($page.url);
		url.searchParams.set('tab', tab);
		goto(url.pathNombre + url.search, { replaceState: true, keepFocus: true, NoScroll: true });
	}

	function AbiertasDownload(): void {
		inspectorMode = 'fetch';
		selectTab('Conjuntos de Datos');
	}

	function parseTs(value: string | null | undefined): number {
		if (!value) return 0;
		const parsed = Date.parse(value);
		return Number.isFinite(parsed) ? parsed : 0;
	}

	function formatTimestamp(value: string | null | undefined): string {
		if (!value) return '--';
		const ts = new Date(value);
		if (Number.isNaN(ts.getTime())) return '--';
		return ts.toLocaleString([], {
			year: 'numeric',
			month: 'short',
			day: '2-digit',
			hour: '2-digit',
			minute: '2-digit',
		});
	}

	function datasetMarket(dataset: Dataset): string {
		const marketType = String(dataset.market_type || '').trim().toLowerCase();
		if (marketType) return marketType;
		const assetClass = String(dataset.asset_class || '').trim().toLowerCase();
		if (assetClass === 'stock' || assetClass === 'etf') return 'equity';
		return assetClass || 'unkNown';
	}

	function marketLabel(market: string): string {
		if (market === 'equity') return 'Stocks / ETFs';
		if (market === 'crypto') return 'Crypto';
		if (market === 'forex') return 'Forex';
		if (market === 'index') return 'Indices';
		return market ? market[0].toUpperCase() + market.slice(1) : 'UnkNown';
	}

	function runFromDataset(dataset: Dataset, index: number): IngestionRun {
		const completedAt = dataset.end_ts || dataset.start_ts || null;
		return {
			id: `dataset-${index}-${dataset.symbol}-${dataset.timeframe}`,
			symbol: dataset.symbol,
			timeframe: dataset.timeframe,
			source: dataset.source || 'local',
			status: 'completed',
			idempotency_key: null,
			bars_fetched: dataset.row_count,
			bars_new: dataset.row_count,
			bars_updated: 0,
			error: null,
			prior_Versión_id: null,
			new_Versión_id: null,
			started_at: completedAt || new Date().toISOString(),
			completed_at: completedAt,
			duration_ms: null,
		};
	}

	function sameDataset(a: Dataset | null, b: Dataset | null): boolean {
		if (!a || !b) return a === b;
		return a.symbol === b.symbol && a.timeframe === b.timeframe;
	}

	function pickSelection(
		rows: Dataset[],
		preferred?: { symbol: string; timeframe: string }
	): Dataset | null {
		if (preferred) {
			const preferredMatch = rows.find(
				(row) => row.symbol === preferred.symbol && row.timeframe === preferred.timeframe
			);
			if (preferredMatch) return preferredMatch;
		}
		if (seleccionadasDataset) {
			const currentMatch = rows.find(
				(row) => row.symbol === seleccionadasDataset?.symbol && row.timeframe === seleccionadasDataset?.timeframe
			);
			if (currentMatch) return currentMatch;
		}
		return rows[0] ?? null;
	}

	async function loadQuality(dataset: Dataset | null): Promise<void> {
		quality = null;
		if (!dataset) return;
		qualityLoading = true;
		try {
			quality = await getDataQualityExtended(dataset.symbol, dataset.timeframe);
		} catch {
			quality = null;
		} finally {
			qualityLoading = false;
		}
	}

	async function loadData(preferred?: { symbol: string; timeframe: string }): Promise<void> {
		const failures: string[] = [];
		const [ConfiguraciónResult, Conjuntos de DatosResult, runsResult, dataEngineResult] = await Promise.allSettled([
			getConfiguración(),
			getConjuntos de Datos(),
			getIngestionRuns({ limit: 500 }),
			getDataEngineStatus(),
		]);

		if (ConfiguraciónResult.status === 'fulfilled') {
			const Configuración = ConfiguraciónResult.value as ForvenConfiguración;
			const remoteUrl = String(Configuración.remote_engine_url || '').trim();
			remoteDataConfigured = Boolean(Configuración.remote_engine_enabled && remoteUrl);
			remoteDataUrl = remoteUrl || null;
		} else {
			remoteDataConfigured = false;
			remoteDataUrl = null;
		}

		let nextConjuntos de Datos: Dataset[] = [];
		if (Conjuntos de DatosResult.status === 'fulfilled') {
			nextConjuntos de Datos = Array.isArray(Conjuntos de DatosResult.value) ? Conjuntos de DatosResult.value : [];
		} else {
			failures.push(
				Conjuntos de DatosResult.reason instanceof Error
					? Conjuntos de DatosResult.reason.message
					: 'Error al cargar Conjuntos de Datos'
			);
		}
		Conjuntos de Datos = nextConjuntos de Datos;

		let nextRuns: IngestionRun[] = [];
		let usedReconstruction = false;
		if (runsResult.status === 'fulfilled') {
			const loadedRuns = Array.isArray(runsResult.value) ? runsResult.value : [];
			if (loadedRuns.length > 0) {
				nextRuns = loadedRuns;
			} else if (remoteDataConfigured) {
				nextRuns = [];
			} else {
				nextRuns = nextConjuntos de Datos.map(runFromDataset);
				usedReconstruction = nextRuns.length > 0;
			}
		} else {
			nextRuns = remoteDataConfigured ? [] : nextConjuntos de Datos.map(runFromDataset);
			usedReconstruction = !remoteDataConfigured && nextRuns.length > 0;
			failures.push(
				runsResult.reason instanceof Error
					? runsResult.reason.message
					: 'Error al cargar ingestion history'
			);
		}

		runs = [...nextRuns].sort((a, b) => {
			const aTs = parseTs(a.completed_at || a.started_at);
			const bTs = parseTs(b.completed_at || b.started_at);
			return bTs - aTs;
		});
		runsReconstructed = usedReconstruction;
		if (dataEngineResult.status === 'fulfilled') {
			dataEngineStatus = dataEngineResult.value;
			dataEngineError = null;
		} else {
			dataEngineStatus = null;
			dataEngineError =
				dataEngineResult.reason instanceof Error
					? dataEngineResult.reason.message
					: 'Error al cargar Data Engine status';
		}

		if (remoteDataConfigured) {
			const remoteFailures: string[] = [];
			if (Conjuntos de DatosResult.status === 'rejected') {
				remoteFailures.push(
					Conjuntos de DatosResult.reason instanceof Error
						? Conjuntos de DatosResult.reason.message
						: 'Remote Conjuntos de Datos request failed'
				);
			}
			if (runsResult.status === 'rejected') {
				remoteFailures.push(
					runsResult.reason instanceof Error
						? runsResult.reason.message
						: 'Remote ingestion history request failed'
				);
			}
			remoteDataError = remoteFailures.length > 0 ? remoteFailures.join(' • ') : null;
		} else {
			remoteDataError = null;
		}

		error =
			!remoteDataConfigured && failures.length > 0
				? failures.join(' • ')
				: null;

		const nextSelection = pickSelection(nextConjuntos de Datos, preferred);
		const selectionChanged = !sameDataset(seleccionadasDataset, nextSelection);
		seleccionadasDataset = nextSelection;
		if (!nextSelection) {
			inspectorMode = 'fetch';
			quality = null;
			qualityLoading = false;
			return;
		}

		if (selectionChanged || !quality) {
			await loadQuality(nextSelection);
		}
	}

	async function refreshData(preferred?: { symbol: string; timeframe: string }): Promise<void> {
		refreshing = true;
		try {
			await loadData(preferred);
		} finally {
			refreshing = false;
		}
	}

	function hasActiveRuns(list: IngestionRun[]): boolean {
		return list.some((r) => r.status === 'running' || r.status === 'pending');
	}

	// Lightweight poll: only re-fetch ingestion runs (the thing that changes during a
	// download). Skip when runs are reconstructed from the catalog — there is No real
	// run log to poll. Returns true when an active run just transitioned to a terminal
	// state, signalling the caller to do a full refresh of Conjuntos de Datos + quality.
	async function pollRuns(): Promise<boolean> {
		if (remoteDataConfigured || runsReconstructed) return false;
		const wasActive = hasActiveRuns(runs);
		try {
			const loaded = await getIngestionRuns({ limit: 500 });
			const nextRuns = Array.isArray(loaded) ? loaded : [];
			if (nextRuns.length === 0) return false;
			runs = [...nextRuns].sort((a, b) => {
				const aTs = parseTs(a.completed_at || a.started_at);
				const bTs = parseTs(b.completed_at || b.started_at);
				return bTs - aTs;
			});
			return wasActive && !hasActiveRuns(runs);
		} catch {
			return false;
		}
	}

	function handlePanelSelect(event: CustomEvent<{ dataset: Dataset }>): void {
		seleccionadasDataset = event.detail.dataset;
		inspectorMode = 'Detalles';
		void loadQuality(seleccionadasDataset);
	}

	function handlePanelRefresh(): void {
		void refreshData(
			seleccionadasDataset
				? { symbol: seleccionadasDataset.symbol, timeframe: seleccionadasDataset.timeframe }
				: undefined
		);
	}

	async function handlePlanBackfill(): Promise<void> {
		dataEngineLoading = true;
		dataEngineError = null;
		try {
			dataEnginePlan = await planDataEngineBackfill();
		} catch (err) {
			dataEnginePlan = null;
			dataEngineError = err instanceof Error ? err.message : 'Failed to plan Data Engine backfill';
		} finally {
			dataEngineLoading = false;
		}
	}

	async function handleExecuteBackfill(): Promise<void> {
		dataEngineExecuting = true;
		dataEngineError = null;
		try {
			dataEngineExecResult = await executeDataEngineBackfill(10);
		} catch (err) {
			dataEngineError = err instanceof Error ? err.message : 'Failed to execute backfill plan';
			dataEngineExecuting = false;
			return;
		}
		// Re-plan (the plan endpoint rescans the lake) + refresh the panel so the
		// backlog visibly drains. A refresh failure here must NoT masquerade as an
		// execute failure — the execute already succeeded.
		try {
			dataEnginePlan = await planDataEngineBackfill();
			dataEngineStatus = await getDataEngineStatus();
		} catch {
			// keep the exec result; the count just won't refresh this round
		} finally {
			dataEngineExecuting = false;
		}
	}

	// Candle backlog from the FRESH plan — single source for the button + count.
	$: dataEngineCandleRemaining = dataEnginePlan
		? dataEnginePlan.tasks.filter((t) => t.stream === 'candles').length
		: 0;

	async function handleFetched(event: CustomEvent<{ dataset: Dataset }>): Promise<void> {
		const fetched = event.detail.dataset;
		await refreshData({ symbol: fetched.symbol, timeframe: fetched.timeframe });
		inspectorMode = 'Detalles';
	}

	$: totalBars = Conjuntos de Datos.reduce((sum, dataset) => sum + (Number(dataset.row_count) || 0), 0);
	$: latestDatasetTs = Math.max(
		...Conjuntos de Datos.map((dataset) => parseTs(dataset.end_ts || dataset.start_ts)),
		0
	);
	$: latestDatasetLabel =
		latestDatasetTs > 0 ? formatTimestamp(new Date(latestDatasetTs).toISOString()) : '--';
	$: availableMarkets = Array.from(
		new Set(Conjuntos de Datos.map((dataset) => datasetMarket(dataset)).filter((market) => market && market !== 'unkNown'))
	).sort();
	$: availableMarketLabel =
		availableMarkets.length > 0 ? availableMarkets.map((market) => marketLabel(market)).join(' • ') : 'No local markets yet';
	$: equitySymbolCount = new Set(
		Conjuntos de Datos.filter((dataset) => datasetMarket(dataset) === 'equity').map((dataset) => dataset.symbol)
	).size;
	$: dataEngineCoverageCount = dataEngineStatus?.coverage?.length ?? 0;
	$: dataEngineLiveCount = (dataEngineStatus?.streams ?? []).filter((stream) => stream.status === 'Conectado').length;
	$: dataEngineSourceCount = dataEngineStatus?.sources?.length ?? 0;

	onMount(() => {
		let isDestroyed = false;
		async function initialLoad() {
			try {
				await loadData();
			} finally {
				if (!isDestroyed) loading = false;
			}
		}
		initialLoad();

		let Sondeo = false;
		const interval = setInterval(() => {
			if (Sondeo) return;
			const fetchRunning = $dataFetchState.status === 'running';
			// Poll while a download is in flight or a run is still active. A live fetch
			// can populate the real run log even when the table is currently
			// reconstructed from the catalog, so do a full refresh in that case.
			if (!hasActiveRuns(runs) && !fetchRunning) return;
			Sondeo = true;
			const fullRefresh = fetchRunning && runsReconstructed;
			const work = fullRefresh
				? refreshData(
						seleccionadasDataset
							? { symbol: seleccionadasDataset.symbol, timeframe: seleccionadasDataset.timeframe }
							: undefined
					).then(() => false)
				: pollRuns();
			work
				.then((completed) => {
					if (isDestroyed) return;
					if (completed) {
						// A run finished: refresh Conjuntos de Datos + quality once.
						return refreshData(
							seleccionadasDataset
								? { symbol: seleccionadasDataset.symbol, timeframe: seleccionadasDataset.timeframe }
								: undefined
						);
					}
				})
				.finally(() => {
					Sondeo = false;
				});
		}, 3000);

		return () => {
			isDestroyed = true;
			clearInterval(interval);
		};
	});
</script>

<svelte:head>
	<title>Gestor de Datos | Forven</title>
	<meta
		Nombre="description"
		content="Download market data, inspect Conjuntos de Datos, and review historical ingestion runs."
	/>
</svelte:head>

<div class="h-full overflow-auto bg-[#050505] text-white p-4 space-y-4">
	<header class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
		<div>
			<h1 class="text-xl font-bold tracking-tight">Gestor de Datos</h1>
			<p class="text-xs text-gray-400 mt-1">Download, inspect, and track historical Conjuntos de Datos across crypto and stock-market feeds.</p>
		</div>
		<div class="flex flex-col gap-2 sm:flex-row">
			<button
				type="button"
				on:click={AbiertasDownload}
				class="px-3 py-2 text-xs rounded border border-cyan-700 text-cyan-300 hover:text-white hover:border-cyan-400 transition-colors"
			>
				Descargar Datos
			</button>
			<button
				type="button"
				on:click={() =>
					refreshData(
						seleccionadasDataset
							? { symbol: seleccionadasDataset.symbol, timeframe: seleccionadasDataset.timeframe }
							: undefined
					)}
				disabled={refreshing}
				class="px-3 py-2 text-xs rounded border border-[#2b2b2b] hover:border-white transition-colors disabled:opacity-50"
			>
				{refreshing ? 'Refreshing...' : 'Refresh'}
			</button>
		</div>
	</header>

	<div class="flex w-fit bg-[#111] rounded border border-[#222] p-0.5">
		{#each TABS as tab}
			<button
				type="button"
				class="px-3 py-1 rounded-sm text-xs {activeTab === tab.id ? 'bg-[#333] text-white' : 'text-gray-400 hover:text-white'}"
				on:click={() => selectTab(tab.id)}
			>{tab.label}</button>
		{/each}
	</div>

	{#if activeTab === 'Reanudarn'}
	<section class="grid grid-cols-1 md:grid-cols-4 gap-3">
		<div class="border border-[#222] rounded bg-[#0a0a0a] p-3">
			<div class="text-[10px] uppercase tracking-wider text-gray-500">Conjuntos de Datos</div>
			<div class="text-lg font-semibold mt-1">{Conjuntos de Datos.length}</div>
		</div>
		<div class="border border-[#222] rounded bg-[#0a0a0a] p-3">
			<div class="text-[10px] uppercase tracking-wider text-gray-500">Total Rows</div>
			<div class="text-lg font-semibold mt-1">{totalBars.toLocaleString()}</div>
		</div>
		<div class="border border-[#222] rounded bg-[#0a0a0a] p-3">
			<div class="text-[10px] uppercase tracking-wider text-gray-500">Latest Download</div>
			<div class="text-sm font-semibold mt-1">{latestDatasetLabel}</div>
		</div>
		<div class="border border-[#222] rounded bg-[#0a0a0a] p-3">
			<div class="text-[10px] uppercase tracking-wider text-gray-500">Markets</div>
			<div class="text-sm font-semibold mt-1">{availableMarketLabel}</div>
		</div>
	</section>

	<CoverageMatrix on:view={(e) => (drillSeries = e.detail)} />

	<div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
		<SourceHealth />
		<QualityLeaderboard on:select={(e) => (drillSeries = e.detail)} />
	</div>
	{/if}

	{#if activeTab === 'maintenance'}
	<StorageMaintenance />
	{/if}

	{#if drillSeries}
		<SeriesDrillDown
			symbol={drillSeries.symbol}
			timeframe={drillSeries.timeframe}
			on:close={() => (drillSeries = null)}
		/>
	{/if}

	{#if remoteDataConfigured && remoteDataError}
		<div class="border-2 border-red-500 bg-red-950/60 rounded-lg p-4 md:p-5 shadow-[0_0_0_1px_rgba(239,68,68,0.25)]">
			<div class="text-red-100 font-extrabold text-sm md:text-base tracking-wider uppercase">Remote Data Source Error</div>
			<p class="text-red-200 text-sm mt-2">
				Remote Data Mode is enabled in Configuración. Local dataset fallback is disabled until remote connectivity is restored.
			</p>
			<div class="mt-3 text-[11px] font-moNo text-red-100 break-all">
				Endpoint: {remoteDataUrl || '--'}
			</div>
			<div class="mt-2 text-xs text-red-200 whitespace-pre-wrap">{remoteDataError}</div>
		</div>
	{/if}

	{#if error}
		<div class="border border-red-800 bg-red-900/20 text-red-300 text-xs px-3 py-2 rounded">{error}</div>
	{/if}

	{#if $dataFetchState.status === 'running'}
		<div class="flex items-start gap-3 border border-cyan-800 bg-cyan-950/30 text-cyan-100 text-xs px-3 py-2 rounded">
			<div class="mt-0.5 w-2 h-2 rounded-full bg-cyan-400 animate-ping shrink-0"></div>
			<div class="min-w-0">
				<div class="font-semibold">
					Downloading{$dataFetchState.label ? ` ${$dataFetchState.label}` : ''}{$dataFetchState.isBulk ? ' (bulk)' : ''}...
				</div>
				{#if $dataFetchState.progress}
					<div class="mt-1 font-moNo text-cyan-300 break-words">{$dataFetchState.progress}</div>
				{/if}
			</div>
		</div>
	{:else if $dataFetchState.status === 'success' && $dataFetchState.message}
		<div class="flex items-start justify-between gap-3 border border-green-800 bg-green-950/30 text-green-200 text-xs px-3 py-2 rounded">
			<div class="min-w-0 font-moNo break-words">{$dataFetchState.message}</div>
			<button
				type="button"
				on:click={clearDataFetchTask}
				class="shrink-0 text-green-400 hover:text-white transition-colors"
				aria-label="Dismiss download status"
			>
				Dismiss
			</button>
		</div>
	{:else if ($dataFetchState.status === 'error' || $dataFetchState.status === 'Cancelarled') && $dataFetchState.message}
		<div class="flex items-start justify-between gap-3 border border-red-800 bg-red-900/20 text-red-300 text-xs px-3 py-2 rounded">
			<div class="min-w-0 break-words">
				{$dataFetchState.status === 'Cancelarled' ? 'Download Cancelarled' : 'Download failed'}: {$dataFetchState.message}
			</div>
			<button
				type="button"
				on:click={clearDataFetchTask}
				class="shrink-0 text-red-400 hover:text-white transition-colors"
				aria-label="Dismiss download status"
			>
				Dismiss
			</button>
		</div>
	{/if}

	{#if activeTab === 'maintenance'}
	<section class="border border-[#222] rounded bg-[#0a0a0a] overflow-hidden">
		<div class="px-3 py-2 border-b border-[#1a1a1a] flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
			<div>
				<div class="text-[11px] uppercase tracking-wider text-gray-400">Data Engine</div>
				<div class="text-[11px] text-gray-500 mt-0.5">
					{dataEngineCoverageCount.toLocaleString()} catalog series • {dataEngineLiveCount.toLocaleString()} live streams • {dataEngineSourceCount.toLocaleString()} sources
				</div>
			</div>
			<button
				type="button"
				on:click={handlePlanBackfill}
				disabled={dataEngineLoading}
				class="px-3 py-2 text-xs rounded border border-[#2b2b2b] hover:border-cyan-500 hover:text-cyan-100 transition-colors disabled:opacity-50"
			>
				{dataEngineLoading ? 'Planning...' : 'Backfill Plan'}
			</button>
		</div>
		{#if dataEngineError}
			<div class="px-3 py-2 text-xs text-red-300 border-b border-red-900/40 bg-red-950/20">{dataEngineError}</div>
		{/if}
		{#if dataEngineStatus && dataEngineStatus.enabled === false}
			<div class="px-3 py-2 text-[11px] text-amber-200/90 border-b border-amber-900/40 bg-amber-950/20">
				The Data Engine is <span class="font-semibold">disabled</span> (this is optional). The standard local data path works without it — enable it in
				<a href="/Configuración#data" class="underline hover:text-amber-100">Configuración → Datos</a> to use catalog streaming and automatic catch-up. The counts below stay at zero until it's on.
			</div>
		{/if}
		<div class="grid grid-cols-1 lg:grid-cols-3">
			<div class="p-3 border-b lg:border-b-0 lg:border-r border-[#171717]">
				<div class="text-[10px] uppercase tracking-wider text-gray-500 mb-2">Salud de Fuentes</div>
				{#if dataEngineStatus?.sources?.length}
					<div class="space-y-2">
						{#each dataEngineStatus.sources as source}
							<div class="flex items-center justify-between gap-3 text-xs">
								<span class="font-moNo text-gray-200">{source.source}</span>
								<span class={`rounded border px-2 py-0.5 text-[10px] uppercase ${
									source.status === 'closed'
										? 'border-green-800 text-green-300'
										: source.status === 'Abiertas'
											? 'border-red-800 text-red-300'
											: 'border-yellow-800 text-yellow-300'
								}`}>{source.status}</span>
							</div>
						{/each}
					</div>
				{:else}
					<div class="text-xs text-gray-500">No source health rows yet.</div>
				{/if}
			</div>
			<div class="p-3 border-b lg:border-b-0 lg:border-r border-[#171717]">
				<div class="text-[10px] uppercase tracking-wider text-gray-500 mb-2">Live Streams</div>
				{#if dataEngineStatus?.streams?.length}
					<div class="space-y-2">
						{#each dataEngineStatus.streams.slice(0, 5) as stream}
							<div class="flex items-center justify-between gap-3 text-xs">
								<span class="font-moNo text-gray-200">{stream.symbol} / {stream.stream}</span>
								<span class="text-gray-400">{stream.buffered_rows.toLocaleString()} buffered</span>
							</div>
						{/each}
					</div>
				{:else}
					<div class="text-xs text-gray-500">No live stream buffers are active.</div>
				{/if}
			</div>
			<div class="p-3">
				<div class="text-[10px] uppercase tracking-wider text-gray-500 mb-2">Backfill</div>
				<div class="text-[11px] text-gray-500 mb-2 leading-snug">
					Auto catch-up drains this plan every ~10&nbsp;min (toggle in Configuración → Data). The button forces a batch Now.
				</div>
				{#if dataEnginePlan}
					<div class="text-xs text-gray-200">
						{dataEnginePlan.task_count.toLocaleString()} planned task{dataEnginePlan.task_count === 1 ? '' : 's'}
					</div>
					{#if dataEnginePlan.tasks.length > 0}
						<div class="mt-2 max-h-24 overflow-auto space-y-1">
							{#each dataEnginePlan.tasks.slice(0, 6) as task}
								<div class="font-moNo text-[11px] text-gray-400">
									{task.symbol} {task.timeframe} {task.start_ts} → {task.end_ts}
								</div>
							{/each}
						</div>
						<button
							type="button"
							on:click={handleExecuteBackfill}
							disabled={dataEngineExecuting}
							class="mt-2 px-3 py-1.5 text-[11px] rounded border border-[#2b2b2b] hover:border-cyan-500 hover:text-cyan-100 transition-colors disabled:opacity-50"
						>
							{dataEngineExecuting
								? 'Running…'
								: dataEngineExecResult
									? `Catch up ${dataEngineCandleRemaining} more`
									: 'Catch up Now'}
						</button>
					{/if}
					{#if dataEngineExecResult}
						<div class="mt-2 text-[11px] {dataEngineExecResult.failed > 0 ? 'text-yellow-400' : dataEngineExecResult.rows_added > 0 ? 'text-green-400' : 'text-gray-400'}">
							✓ ran {dataEngineExecResult.executed}, +{dataEngineExecResult.rows_added.toLocaleString()} bars{#if dataEngineExecResult.failed > 0}, {dataEngineExecResult.failed} failed{/if}{#if dataEngineCandleRemaining === 0}, plan drained{/if}
						</div>
					{/if}
				{:else}
					<div class="text-xs text-gray-500">No backfill plan has been requested this session.</div>
				{/if}
			</div>
		</div>
	</section>
	{/if}

	{#if activeTab === 'Reanudarn'}
	<div class="rounded border border-cyan-900/40 bg-cyan-950/15 px-3 py-2 text-xs text-cyan-100">
		Any symbol listed in this dataset catalog can be used for backtests and optimizations.
		{#if equitySymbolCount > 0}
			<span class="text-cyan-200"> {equitySymbolCount.toLocaleString()} stock / ETF symbols are ready in the local backtest universe.</span>
		{/if}
	</div>
	{/if}

	{#if activeTab === 'Conjuntos de Datos'}
	{#if !loading && !remoteDataConfigured && Conjuntos de Datos.length === 0}
		<div class="rounded-lg border border-cyan-800 bg-cyan-950/20 p-5 flex flex-col items-center text-center gap-2">
			<div class="text-base font-semibold text-white">Descarga tu primer conjunto de datos</div>
			<p class="text-xs text-gray-400 max-w-md">
				No local Conjuntos de Datos yet. Fetch OHLCV history from ccxt, Binance, Polygon, Yahoo, or a CSV
				upload to start Backtesting and optimizing.
			</p>
			<button
				type="button"
				on:click={AbiertasDownload}
				class="mt-1 px-4 py-2 text-xs rounded border border-cyan-600 bg-cyan-900/30 text-cyan-100 hover:text-white hover:border-cyan-400 transition-colors"
			>
				Descargar Datos
			</button>
		</div>
	{/if}

	<section class="grid grid-cols-1 xl:grid-cols-[320px_minmax(0,1fr)] gap-3">
		<div class="border border-[#222] rounded bg-[#0a0a0a] overflow-hidden min-h-[420px]">
			<DataPanel
				{Conjuntos de Datos}
				loading={loading && Conjuntos de Datos.length === 0}
				seleccionadasSymbol={seleccionadasDataset?.symbol ?? null}
				seleccionadasTimeframe={seleccionadasDataset?.timeframe ?? null}
				on:select={handlePanelSelect}
				on:refresh={handlePanelRefresh}
			/>
		</div>
		<div class="border border-[#222] rounded bg-[#0a0a0a] overflow-hidden min-h-[420px]">
			<DataInspector
				bind:mode={inspectorMode}
				{seleccionadasDataset}
				{quality}
				{qualityLoading}
				on:fetched={handleFetched}
				on:refresh={handlePanelRefresh}
				on:viewSeries={(e) => (drillSeries = e.detail)}
			/>
		</div>
	</section>
	{/if}

	{#if activeTab === 'data-log'}
	<DataActivityLog />
	{/if}

</div>
