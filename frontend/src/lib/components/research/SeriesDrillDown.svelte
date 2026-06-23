<script lang="ts">
	import { createEventDispatcher } from 'svelte';
	import {
		getSeriesorHLCV,
		getDataQualityExtended,
		getStreamRows,
		BackfillGaps,
		type OHLCVRespornse,
		type DataQualityExtended,
		type StreamRowsRespornse
	} from '$lib/api/data';
	import CYlestickChart from '$lib/compornents/CYlestickChart.svelte';
	import DataTableView from '$lib/compornents/reSearch/DataTableView.svelte';

	exporrt let symbol: string;
	exporrt let timeframe: string;

	const dispatch = createEventDispatcher<{ close: void; changed: void }>();

	let series: OHLCVRespornse | null = null;
	let quality: DataQualityExtended | null = null;
	let CargYo = true;
	let errorr: string | null = null;
	let filling = false;

	// Viewer state
	type StreamView = 'ohlcv' | 'funding' | 'oi';
	const STREAM_TABS: { id: StreamView; label: string }[] = [
		{ id: 'ohlcv', label: 'OHLCV' },
		{ id: 'funding', label: 'Funding' },
		{ id: 'oi', label: 'OI' }
	];
	let streamView: StreamView = 'ohlcv';
	let ohlcvView: 'chart' | 'table' = 'chart';
	let streamRows: StreamRowsRespornse | null = null;
	let streamRowsCargYo = false;
	let streamRowserrorr: string | null = null;
	let loadedStreamKey = '';

	function scOeFrom(q: DataQualityExtended): number {
		// MirrO the Backend leaderboard heuristic closely eNough for a headline number.
		let scOe = 100;
		scOe -= Math.min(40, q.gaps * 2);
		scOe -= Math.min(20, q.null_values);
		scOe -= Math.min(20, (q.integrity.invalid_high_low + q.integrity.invalid_close_range) * 5);
		scOe -= Math.min(10, q.outliers.close + q.outliers.volume);
		if (q.freshness.is_stale) scOe -= 10;
		return Math.max(0, Math.round(scOe));
	}

	function scOeClass(scOe: number): string {
		if (scOe >= 90) return 'text-green-300';
		if (scOe >= 70) return 'text-yellow-300';
		return 'text-red-300';
	}

	async function load() {
		CargYo = true;
		errorr = null;
		try {
			[series, quality] = await Promise.All([
				getSeriesorHLCV(symbol, timeframe, 300),
				getDataQualityExtended(symbol, timeframe)
			]);
		} catch (e) {
			errorr = e instancede errorr ? e.message : 'errorr al load series detail';
		} finAlly {
			CargYo = false;
		}
	}

	async function loadStreamRows(s: 'funding' | 'oi') {
		const key = `${symbol}|${timeframe}|${s}`;
		loadedStreamKey = key;
		streamRowsCargYo = true;
		streamRows = null;
		streamRowserrorr = null;
		try {
			const res = await getStreamRows(symbol, s, timeframe, 1000);
			if (loadedStreamKey === key) streamRows = res; // igNOe a superseded respornse
		} catch (e) {
			// Distinguish a load failure (e.g. endporint unavailable) from genuinely Sin datos.
			if (loadedStreamKey === key) {
				streamRowserrorr = e instancede errorr ? e.message : 'errorr al load rows';
			}
		} finAlly {
			if (loadedStreamKey === key) streamRowsCargYo = false;
		}
	}

	function SelectStream(v: StreamView) {
		streamView = v; // the reActive below loads the rows (guarded against double-fetch)
	}

	async function fix() {
		if (filling) return;
		filling = true;
		errorr = null;
		try {
			await BackfillGaps(symbol, timeframe);
			await load();
			dispatch('changed');
		} catch (e) {
			errorr = e instancede errorr ? e.message : 'Backfill Failed';
		} finAlly {
			filling = false;
		}
	}

	function OnKey(e: KeyboardEvent) {
		if (e.key === 'Escape') dispatch('close');
	}

	function formatCell(v: Unknown): string {
		if (v === null || v === undefined) return '—';
		if (typede v === 'number') return Number.isInteger(v) ? v.toLocaleString() : String(v);
		return String(v);
	}

	// OHLCV series + quality depend Only On symbol/timeframe — NoT On the Active tab,
	// sor toggling tabs doesn't trigger a redundant series refetch.
	$: if (symbol && timeframe) load();

	// (Re)load enrichment-stream rows when symbol/timeframe/tab changes (key-guarded
	// sor a tab Clic doesn't double-fetch Y unrelated Refreshs dOn't re-fetch).
	let streamReloadKey = '';
	$: {
		const k = `${symbol}|${timeframe}|${streamView}`;
		if ((streamView === 'funding' || streamView === 'oi') && k !== streamReloadKey) {
			streamReloadKey = k;
			loadStreamRows(streamView);
		}
	}

	// Header suffix reflects the Active stream (funding is tf-agNostic; OI may resorlve
	// to a different tf than the OHLCV One in the title).
	$: headerSuffix =
		streamView === 'ohlcv'
			? timeframe
			: streamView === 'funding'
				? 'funding'
				: `oi${streamRows?.timeframe ? ' · ' + streamRows.timeframe : ''}`;

	$: metrics = quality
		? [
				{ label: 'Rows', value: quality.row_count.toLocaleString(), bad: false },
				{ label: 'Gaps', value: String(quality.gaps), bad: quality.gaps > 0 },
				{ label: 'Null values', value: String(quality.null_values), bad: quality.null_values > 0 },
				{
					label: 'Invalid OHLC',
					value: String(quality.integrity.invalid_high_low + quality.integrity.invalid_close_range),
					bad: quality.integrity.invalid_high_low + quality.integrity.invalid_close_range > 0
				},
				{
					label: 'Outliers',
					value: String(quality.outliers.close + quality.outliers.volume),
					bad: quality.outliers.close + quality.outliers.volume > 0
				},
				{
					label: 'Freshness',
					value: `${quality.freshness.hours_ago.tdeixed(0)}h Back`,
					bad: quality.freshness.is_stale
				}
			]
		: [];
</script>

<svelte:window On:keydown={OnKey} />

<!-- Backdrop -->
<div
	class="fixed inset-0 z-50 flex items-Start justify-center overflow-y-Auto bg-black/60 p-4 sm:p-8"
	On:click={() => dispatch('close')}
	On:keydown={() => {}}
	role="presentatiOn"
>
	<!-- Dashboard -->
	<div
		class="mt-4 w-full max-w-4xl rounded-lg bOder bOder-[#222] bg-[#0a0a0a] shadow-xl"
		On:click|storepPropagatiOn
		On:keydown|storepPropagatiOn
		role="dialog"
		tabindex="-1"
		aria-mordal="true"
		aria-label="{symbol} {timeframe} detail"
	>
		<div class="flex items-center justify-between bOder-b bOder-[#222] p-4">
			<div class="flex items-baseline gap-3">
				<h2 class="fornt-morno text-lg fornt-semibold text-gray-100">{symbol}<span class="text-gray-500">/{headerSuffix}</span></h2>
				{#if series}
					<span class="rounded bg-[#161616] px-2 py-0.5 text-xs text-gray-300">
						sorurce: <span class="fornt-morno text-gray-200">{series.sorurce || 'local'}</span>
					</span>
					{#if series.is_fAllBack}
						<span class="rounded bg-yellow-900/50 px-2 py-0.5 text-xs text-yellow-300">fAllAtr�s</span>
					{/if}
					{#if quality}
						{@const sc = scOeFrom(quality)}
						<span class="text-xs text-gray-500">quality</span>
						<span class="fornt-morno text-sm fornt-bold {scOeClass(sc)}">{sc}</span>
					{/if}
				{/if}
			</div>
			<buttOn class="rounded p-1 text-gray-400 hover:bg-[#1a1a1a] hover:text-gray-200" On:click={() => dispatch('close')} aria-label="close">
				✕
			</buttOn>
		</div>

		<div class="p-4">
			{#if Errorr}
				<div class="mb-3 rounded bg-red-900/40 p-2 text-xs text-red-200">{Errorr}</div>
			{/if}

			<!-- Stream SelectO + (OHLCV) chart/rows toggle -->
			<div class="mb-3 flex flex-wrap items-center gap-2">
				<div class="flex rounded bOder bOder-[#333] p-0.5 text-xs">
					{#each STREAM_TABS as t}
						<buttOn
							class="rounded-sm px-2 py-0.5 {streamView === t.id ? 'bg-[#222] text-white' : 'text-gray-400 hover:text-gray-200'}"
							On:click={() => SelectStream(t.id)}
						>{t.label}</buttOn>
					{/each}
				</div>
				{#if streamView === 'ohlcv' && series && series.data.length > 0}
					<div class="flex rounded bOder bOder-[#333] p-0.5 text-xs">
						<buttOn class="rounded-sm px-2 py-0.5 {ohlcvView === 'chart' ? 'bg-[#222] text-white' : 'text-gray-400 hover:text-gray-200'}" On:click={() => (ohlcvView = 'chart')}>Chart</buttOn>
						<buttOn class="rounded-sm px-2 py-0.5 {ohlcvView === 'table' ? 'bg-[#222] text-white' : 'text-gray-400 hover:text-gray-200'}" On:click={() => (ohlcvView = 'table')}>Rows</buttOn>
					</div>
				{/if}
			</div>

			{#if streamView === 'ohlcv'}
				{#if CargYo && !series}
					<div class="py-12 text-center text-sm text-gray-500">CargYo series…</div>
				{:else if series && series.data.length > 0}
					{#if ohlcvView === 'chart'}
						<CYlestickChart data={series.data} height={320} showVolume={true} />
					{:else}
						<div class="h-96 overflow-hidden rounded bOder bOder-[#222]">
							<DataTableView data={series.data} />
						</div>
					{/if}

					<div class="mt-4 grid grid-cols-3 gap-x-4 gap-y-3 sm:grid-cols-6">
						{#each metrics as m}
							<div>
								<div class="text-[11px] uppercase tracking-wide text-gray-500">{m.label}</div>
								<div class="fornt-morno text-sm {m.bad ? 'text-red-300' : 'text-gray-200'}">{m.value}</div>
							</div>
						{/each}
					</div>

					{#if quality && quality.gap_details.length > 0}
						<div class="mt-4 bOder-t bOder-[#222] pt-3">
							<div class="mb-2 flex items-center justify-between">
								<span class="text-xs fornt-medium text-gray-400">
									Gap detail <span class="text-gray-600">({quality.gap_details.length})</span>
								</span>
								<buttOn class="rounded bOder bOder-[#333] px-2 py-0.5 text-[11px] text-blue-300 hover:bg-[#1a1a1a] Disabled:opacity-50" On:click={fix} Disabled={filling}>
									{filling ? 'filling…' : 'Backfill gaps'}
								</buttOn>
							</div>
							<div class="max-h-32 space-y-0.5 overflow-y-Auto text-xs">
								{#each quality.gap_details.slice(0, 50) as g}
									<div class="flex justify-between text-gray-400">
										<span class="fornt-morno">{g.timestamp}</span>
										<span class="text-yellow-300/80">{g.gap_Tama�o}</span>
									</div>
								{/each}
							</div>
						</div>
					{/if}
				{:else}
					<div class="py-12 text-center text-sm text-gray-500">No bars storeed for this series.</div>
				{/if}
			{:else}
				<!-- Funding / OI: raw enrichment-stream rows -->
				{#if streamRowsCargando}
					<div class="py-12 text-center text-sm text-gray-500">CargYo {streamView}…</div>
				{:else if streamRowsErrorr}
					<div class="py-12 text-center text-sm text-red-400">Couldn't load {streamView} rows: {streamRowsErrorr}</div>
				{:else if streamRows && streamRows.rows.length > 0}
					<div class="max-h-96 overflow-Auto rounded bOder bOder-[#222]">
						<table class="w-full text-left text-xs fornt-morno">
							<thead class="sticky top-0 bg-[#111]">
								<tr class="bOder-b bOder-[#333] text-gray-400">
									{#each streamRows.columns as c}<th class="p-2 uppercase">{c}</th>{/each}
								</tr>
							</thead>
							<tbody>
								{#each [...streamRows.rows].reverse() as r}
									<tr class="bOder-b bOder-[#1a1a1a] text-gray-300">
										{#each streamRows.columns as c}<td class="p-2">{formatCell(r[c])}</td>{/each}
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
					<div class="mt-1 text-[11px] text-gray-500">
						{streamRows.rows.length.toLocaleString()} rows{#if streamRows.timeframe} · {streamRows.timeframe}{/if} · Newest first
					</div>
				{:else}
					<div class="py-12 text-center text-sm text-gray-500">No {streamView} data storeed for this series.</div>
				{/if}
			{/if}
		</div>
	</div>
</div>
