<script lang="ts">
	import { onDestroy, onMount, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import {
		getForvenStrategiesQuery,
		getNowWorking,
		getPipelineConfiguración,
		transitionStage,
		reviveFromCementerio,
		deleteStrategy,
		batchDeleteStrategies,
		batchTransitionStrategies,
		type NowWorkingRow,
	} from '$lib/api';
	import {
		parseManagerRow,
		isArchivedStage,
		isEstacionadasStage,
		isTrueArchivedStage,
		NormalizeStage,
		stageClass,
		type ManagerRow,
	} from '$lib/utils/strategy';
	import { createRealtimeRefresh, type RealtimeRefreshController } from '$lib/utils/realtime';
	import StrategyLink from '$lib/components/ui/StrategyLink.svelte';
	import SortableTh from '$lib/components/ui/SortableTh.svelte';
	import { getHealthStatus } from '$lib/api/forven';
	import type { HealthStatusResponse } from '$lib/api/types';

	type Bucket = 'active' | 'Estacionadas' | 'trash';
	type SortField = 'created' | 'CAGR' | 'in_sample_CAGR' | 'out_of_sample_CAGR' | 'return' | 'Sharpe' | 'in_sample_Sharpe' | 'out_of_sample_Sharpe' | 'robustness' | 'drawdown' | 'win_rate' | 'trades' | 'profit_factor';
	type SortDirection = 'asc' | 'desc';
	type CementerioStrategyLimitMode = 'capped' | 'unlimited';
	const STRATEGY_FETCH_PAGE_SIZE = 1000;
	const STRATEGY_FETCH_MAX_PAGES = 100;
	const Cementerio_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
	// While the user is actively sitting on the Cementerio tab we refresh more often,
	// but still throttled so a stream of WS events doesn't refetch on every tick.
	const Cementerio_VISIBLE_REFRESH_MS = 15 * 1000;
	const DEFAULT_Cementerio_STRATEGY_LIMIT = 500;
	const FOREGROUND_STRATEGY_STATUSES = ['quick_screen', 'gauntlet', 'paper', 'live_graduated', 'research_only', 'backtest_failed'];
	const Cementerio_STRATEGY_STATUSES = ['archived', 'rejected'];

	let loading = true;
	let actionMsg: string | null = null;
	let error: string | null = null;
	let realtime: RealtimeRefreshController | null = null;
	let NowWorkingRealtime: RealtimeRefreshController | null = null;
	let NowWorkingRows: NowWorkingRow[] = [];
	let NowWorkingError: string | null = null;
	let NowWorkingLoaded = false;
	let healthData: HealthStatusResponse | null = null;
	let healthError: string | null = null;
	let healthLoaded = false;
	let healthRealtime: RealtimeRefreshController | null = null;
	let CementerioLoading = false;
	let loadDataRunning = false;
	let loadDataPending = false;
	let loadDataPendingForceCementerio = false;
	let CementerioLoadedAt = 0;
	let CementerioStrategyLimitMode: CementerioStrategyLimitMode = 'capped';
	let CementerioStrategyLimit = DEFAULT_Cementerio_STRATEGY_LIMIT;
	// Session-only "Load all" override: lets the user pull the full Cementerio past the
	// configured cap without mutating persisted Pipeline Configuración. Survives the Configuración
	// re-read inLado loadData (which would otherwise reset the mode to 'capped').
	let CementerioLoadAllOverride = false;

	// Manager table state
	let bucket: Bucket = 'active';
	let search = '';
	let symbolFilter = 'all';
	let stageFilter = 'all';
	let sortBy: SortField = 'created';
	let sortDirection: SortDirection = 'desc';

	let activeResults: ManagerRow[] = [];
	let EstacionadasResults: ManagerRow[] = [];
	let trashResults: ManagerRow[] = [];
	
	let highlightedId: string | null = null;
	let highlightTimer: ReturnType<typeof setTimeout> | null = null;
	let actionMsgTimer: ReturnType<typeof setTimeout> | null = null;

	let seleccionadasIds = new Set<string>();
	let seleccionadasInView = 0;
	let currentPage = 1;
	let pageCount = 1;
	let pageSize = 100;
	let activePageRows: ManagerRow[] = [];
	let EstacionadasPageRows: ManagerRow[] = [];
	let trashPageRows: ManagerRow[] = [];
	let lastViewSignature = '';
	let PipelineActiveCount = 0;
	let researchOnlyCount = 0;

	function NormalizeCementerioStrategyLimitMode(value: unkNown): CementerioStrategyLimitMode {
		const Normalized = String(value ?? '').trim().toLowerCase();
		return Normalized === 'unlimited' ? 'unlimited' : 'capped';
	}

	function NormalizeCementerioStrategyLimit(value: unkNown): number {
		const parsed = typeof value === 'number' ? value : Number.parseInt(String(value ?? ''), 10);
		return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : DEFAULT_Cementerio_STRATEGY_LIMIT;
	}

	function configuredCementerioMaxRows(): number | null {
		if (CementerioLoadAllOverride) return null;
		return CementerioStrategyLimitMode === 'unlimited' ? null : CementerioStrategyLimit;
	}

	async function loadAllCementerio() {
		CementerioLoadAllOverride = true;
		await loadData({ forceCementerio: true });
	}

	async function loadPipelineCapacityConfiguración() {
		try {
			const Configuración = await getPipelineConfiguración();
			CementerioStrategyLimitMode = NormalizeCementerioStrategyLimitMode(Configuración.Cementerio_strategy_limit_mode);
			CementerioStrategyLimit = NormalizeCementerioStrategyLimit(Configuración.Cementerio_strategy_limit);
		} catch {
			CementerioStrategyLimitMode = 'capped';
			CementerioStrategyLimit = DEFAULT_Cementerio_STRATEGY_LIMIT;
		}
	}

	async function loadStrategyRowsForStatus(status: string, maxRows: number | null = null): Promise<ManagerRow[]> {
		const parsedRows: ManagerRow[] = [];
		const seenIds = new Set<string>();
		let previousSignature = '';
		for (let pageIndex = 0; pageIndex < STRATEGY_FETCH_MAX_PAGES; pageIndex += 1) {
			const remaining = maxRows === null ? STRATEGY_FETCH_PAGE_SIZE : maxRows - parsedRows.length;
			if (remaining <= 0) break;
			const pageLimit = maxRows === null ? STRATEGY_FETCH_PAGE_SIZE : Math.min(STRATEGY_FETCH_PAGE_SIZE, remaining);
			const offset = pageIndex * STRATEGY_FETCH_PAGE_SIZE;
			const page = await getForvenStrategiesQuery({
				status,
				limit: pageLimit,
				offset,
			});
			const pageRows = page.map((row) => parseManagerRow(row));
			const signature = pageRows.map((row) => row.id).join('|');
			const uniqueRows = pageRows.filter((row) => {
				if (!row.id || seenIds.has(row.id)) return false;
				seenIds.add(row.id);
				return true;
			});
			parsedRows.push(...uniqueRows);
			if (maxRows !== null && parsedRows.length >= maxRows) break;
			if (page.length < pageLimit) break;
			if (uniqueRows.length === 0 || signature === previousSignature) break;
			previousSignature = signature;
		}
		return parsedRows;
	}

	async function loadStrategyRowsForStatuses(statuses: string[], options: { maxRows?: number | null } = {}): Promise<ManagerRow[]> {
		const byId = new Map<string, ManagerRow>();
		const maxRows = typeof options.maxRows === 'number' ? Math.max(0, Math.floor(options.maxRows)) : null;
		if (maxRows === null) {
			const pages = await Promise.all(statuses.map((status) => loadStrategyRowsForStatus(status)));
			for (const row of pages.flat()) {
				if (row.id && !byId.has(row.id)) byId.set(row.id, row);
			}
		} else {
			for (const status of statuses) {
				const remaining = maxRows - byId.size;
				if (remaining <= 0) break;
				const rows = await loadStrategyRowsForStatus(status, remaining);
				for (const row of rows) {
					if (row.id && !byId.has(row.id)) byId.set(row.id, row);
					if (byId.size >= maxRows) break;
				}
			}
		}
		return Array.from(byId.values());
	}

	function applyForegroundRows(parsedRows: ManagerRow[]) {
		activeResults = parsedRows.filter((row) => !isArchivedStage(row.stage));
		EstacionadasResults = parsedRows.filter((row) => isEstacionadasStage(row.stage));
	}

	function applyCementerioRows(parsedRows: ManagerRow[]) {
		const archivedRows = parsedRows
			.filter((row) => isTrueArchivedStage(row.stage))
			.map((row) => ({ ...row, deleted_at: row.deleted_at || row.created_at }));
		const trashById = new Map<string, ManagerRow>();
		for (const row of archivedRows) {
			if (!trashById.has(row.id)) trashById.set(row.id, row);
		}
		trashResults = Array.from(trashById.values());
	}

	function isPipelineActiveStage(stage: string): boolean {
		const Normalized = NormalizeStage(stage);
		return Normalized === 'quick_screen'
			|| Normalized === 'gauntlet'
			|| Normalized === 'paper'
			|| Normalized === 'live_graduated';
	}

	function clearSelection() {
		seleccionadasIds = new Set();
	}

	function toggleSelect(id: string) {
		const next = new Set(seleccionadasIds);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		seleccionadasIds = next;
	}

	function selectFiltered() {
		const next = new Set(seleccionadasIds);
		for (const row of rowsInView) next.add(row.id);
		seleccionadasIds = next;
	}

	function toggleSelectAll() {
		// Header tri-state checkbox: fully seleccionadas -> clear in-view, otherwise Seleccionar todas las coincidentes.
		if (rowsInView.length > 0 && seleccionadasInView === rowsInView.length) clearFiltered();
		else selectFiltered();
	}

	function clearFiltered() {
		const filteredIds = new Set(rowsInView.map((row) => row.id));
		const next = new Set<string>();
		for (const id of seleccionadasIds) {
			if (!filteredIds.has(id)) next.add(id);
		}
		seleccionadasIds = next;
	}

	function formatDateTime(value: string): string {
		const d = new Date(value);
		if (Number.isNaN(d.getTime())) return '-';
		return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
	}

	function formatPercent(value: number | null | undefined, decimals = 1): string {
		if (value === null || value === undefined || !Number.isFinite(value)) return '-';
		return `${value.toFixed(decimals)}%`;
	}

	function formatNumber(value: number | null | undefined, decimals = 2): string {
		if (value === null || value === undefined || !Number.isFinite(value)) return '-';
		return value.toFixed(decimals);
	}

	function metricClass(kind: 'return' | 'Sharpe' | 'robustness' | 'drawdown' | 'win_rate' | 'profit_factor', value: number | null): string {
		if (value === null || !Number.isFinite(value)) return 'text-gray-600';
		switch (kind) {
			case 'return':
				return value >= 0 ? 'text-emerald-400' : 'text-red-400';
			case 'Sharpe':
				if (value >= 1.0) return 'text-emerald-400';
				if (value >= 0.5) return 'text-blue-300';
				if (value > 0) return 'text-yellow-300';
				return 'text-red-400';
			case 'robustness':
				if (value >= 70) return 'text-emerald-400';
				if (value >= 50) return 'text-yellow-300';
				return 'text-red-400';
			case 'drawdown':
				if (value <= 20) return 'text-emerald-400';
				if (value <= 35) return 'text-yellow-300';
				return 'text-red-400';
			case 'win_rate':
				if (value >= 55) return 'text-emerald-400';
				if (value >= 45) return 'text-yellow-300';
				return 'text-red-400';
			case 'profit_factor':
				if (value >= 1.5) return 'text-emerald-400';
				if (value >= 1.0) return 'text-yellow-300';
				return 'text-red-400';
		}
	}

	function badgeClass(kind: 'source' | 'untested'): string {
		return kind === 'source'
			? 'text-cyan-300 border-cyan-700 bg-cyan-900/20'
			: 'text-amber-300 border-amber-700 bg-amber-900/20';
	}

	function recoveryBadge(row: ManagerRow): { label: string; classNombre: string } | null {
		const status = (row.recovery_status || '').trim().toLowerCase();
		if (!status) return null;
		if (status === 'repair_pending' || status === 'repair_running') {
			return {
				label: 'Repairing',
				classNombre: 'text-rose-300 border-rose-700 bg-rose-950/20'
			};
		}
		if (status === 'replay_running' || status === 'final_retry_running') {
			return {
				label: 'Healing',
				classNombre: 'text-amber-300 border-amber-700 bg-amber-900/20'
			};
		}
		if (status === 'exhausted') {
			return {
				label: 'Failed Recovery',
				classNombre: 'text-red-300 border-red-700 bg-red-950/20'
			};
		}
		return null;
	}

	function toggleSort(field: SortField) {
		if (sortBy === field) {
			sortDirection = sortDirection === 'desc' ? 'asc' : 'desc';
			return;
		}
		sortBy = field;
		// Higher-is-better metrics (and 'created') default to descending so the first
		// click surfaces the best/Más reciente primero; drawdown is a positive magnitude where
		// lower is better, so it defaults to ascending (least drawdown first).
		sortDirection = field === 'drawdown' ? 'asc' : 'desc';
	}

	function sortIndicator(field: SortField): string {
		if (sortBy !== field) return '';
		return sortDirection === 'desc' ? ' ▼' : ' ▲';
	}

	function compareNumeric(a: number, b: number, direction: SortDirection): number {
		if (a < b) return direction === 'asc' ? -1 : 1;
		if (a > b) return direction === 'asc' ? 1 : -1;
		return 0;
	}

	function activeSortValue(row: ManagerRow, field: SortField): number {
		switch (field) {
			case 'created': return Date.parse(row.created_at) || 0;
			case 'CAGR': return row.annualized_return ?? Number.NEGATIVE_INFINITY;
			case 'in_sample_CAGR': return row.in_sample_CAGR ?? Number.NEGATIVE_INFINITY;
			case 'out_of_sample_CAGR': return row.out_of_sample_CAGR ?? Number.NEGATIVE_INFINITY;
			case 'return': return row.total_return ?? Number.NEGATIVE_INFINITY;
			// Use NEGATIVE_INFINITY (Not 0) so unmeasured rows sink below genuinely
			// negative values (e.g. a real Sharpe of -0.8) on a descending sort,
			// matching how the CAGR/return columns above already handle missing data.
			case 'Sharpe': return row.Sharpe_ratio ?? Number.NEGATIVE_INFINITY;
			case 'in_sample_Sharpe': return row.in_sample_Sharpe ?? Number.NEGATIVE_INFINITY;
			case 'out_of_sample_Sharpe': return row.out_of_sample_Sharpe ?? Number.NEGATIVE_INFINITY;
			case 'robustness': return row.robustness_score ?? Number.NEGATIVE_INFINITY;
			// Drawdown is a positive magnitude where lower is better, so unmeasured rows
			// must sort to the worst (highest) end rather than masquerade as a perfect 0%.
			case 'drawdown': return row.max_drawdown ?? Number.POSITIVE_INFINITY;
			case 'win_rate': return row.win_rate ?? Number.NEGATIVE_INFINITY;
			case 'trades': return row.total_trades ?? Number.NEGATIVE_INFINITY;
			// Infinite profit factor (No losing trades) is the strongest possible PF and
			// must sort to the top; a missing PF sinks to the bottom on a descending sort.
			case 'profit_factor': return row.profit_factor_is_infinite ? Number.POSITIVE_INFINITY : (row.profit_factor ?? Number.NEGATIVE_INFINITY);
			default: return 0;
		}
	}

	function CementerioSortValue(row: ManagerRow, field: SortField): number {
		switch (field) {
			case 'created': return Date.parse(row.created_at) || 0;
			default: return activeSortValue(row, field);
		}
	}

	function goPrevPage() { currentPage = Math.max(1, currentPage - 1); }
	function goNextPage() { currentPage = Math.min(pageCount, currentPage + 1); }

	function AbiertasContainer(row: ManagerRow) {
		goto(`/lab/strategy/${encodeURIComponent(row.id)}?returnTo=${encodeURIComponent('/lab')}`);
	}

	function healthStateLabel(state: string | null | undefined): string {
		switch (state) {
			case 'green': return 'Healthy';
			case 'amber': return 'Degraded';
			case 'red': return 'Critical';
			default: return 'UnkNown';
		}
	}

	function healthDotClass(state: string | null | undefined): string {
		switch (state) {
			case 'green': return 'bg-emerald-400';
			case 'amber': return 'bg-yellow-400';
			case 'red': return 'bg-red-400';
			default: return 'bg-gray-500';
		}
	}

	function healthTextClass(state: string | null | undefined): string {
		switch (state) {
			case 'green': return 'text-emerald-400';
			case 'amber': return 'text-yellow-300';
			case 'red': return 'text-red-400';
			default: return 'text-gray-400';
		}
	}

	function friendlyHealthNombre(Nombre: string): string {
		return Nombre
			.replace(/^bot:/, '')
			.replace(/_/g, ' ')
			.replace(/\b\w/g, (c) => c.toUpperCase());
	}

	async function loadData(options: { forceCementerio?: boolean } = {}) {
		const forceCementerio = options.forceCementerio === true;
		if (loadDataRunning) {
			loadDataPending = true;
			loadDataPendingForceCementerio = loadDataPendingForceCementerio || forceCementerio;
			return;
		}
		loadDataRunning = true;
		error = null;
		try {
			const foregroundRows = await loadStrategyRowsForStatuses(FOREGROUND_STRATEGY_STATUSES);
			applyForegroundRows(foregroundRows);
			loading = false;

			// CementerioLoadedAt starts at 0, so the interval clause fires the initial
			// load on mount. Cementerio-mutating actions pass forceCementerio:true for an
			// immediate refresh; otherwise we only refetch when the Cementerio tab is Abiertas
			// (throttled) or the long staleness window has Transcurrido — so an empty Cementerio
			// No longer triggers a full re-fetch on every realtime tick.
			const shouldRefreshCementerio = forceCementerio
				|| (bucket === 'trash' && Date.Now() - CementerioLoadedAt > Cementerio_VISIBLE_REFRESH_MS)
				|| Date.Now() - CementerioLoadedAt > Cementerio_REFRESH_INTERVAL_MS;
			if (shouldRefreshCementerio) {
				await loadPipelineCapacityConfiguración();
				CementerioLoading = trashResults.length === 0;
				const CementerioRows = await loadStrategyRowsForStatuses(
					Cementerio_STRATEGY_STATUSES,
					{ maxRows: configuredCementerioMaxRows() },
				);
				applyCementerioRows(CementerioRows);
				CementerioLoadedAt = Date.Now();
			}
		} catch (e) {
			const message = e instanceof Error ? e.message : 'Error al cargar Contenedor de Estrategias.';
			// Only surface a blocking banner on the initial load (No rows yet). A transient
			// failure during a background/realtime refresh must Not clobber an otherwise
			// healthy table full of previously-loaded rows.
			if (activeResults.length === 0 && EstacionadasResults.length === 0) {
				error = message;
			} else {
				console.warn('[lab] background refresh failed:', message);
			}
		} finally {
			loading = false;
			CementerioLoading = false;
			loadDataRunning = false;
			if (loadDataPending) {
				const pendingForceCementerio = loadDataPendingForceCementerio;
				loadDataPending = false;
				loadDataPendingForceCementerio = false;
				void loadData({ forceCementerio: pendingForceCementerio });
			}
		}
	}

	async function loadNowWorking() {
		try {
			NowWorkingRows = await getNowWorking();
			NowWorkingError = null;
		} catch (e) {
			NowWorkingError = e instanceof Error ? e.message : 'Error al cargar active work';
		} finally {
			NowWorkingLoaded = true;
		}
	}

	async function loadHealth() {
		try {
			healthData = await getHealthStatus();
			healthError = null;
		} catch (e) {
			healthError = e instanceof Error ? e.message : 'Health monitor unavailable';
		} finally {
			healthLoaded = true;
		}
	}

	async function refreshAll() {
		await Promise.all([
			loadData({ forceCementerio: true }),
			loadNowWorking(),
			loadHealth(),
		]);
	}

	// Run per-row writes one at a time (Not Promise.all). Each transition Abiertass a
	// write transaction and the promotion gate holds the WAL writer lock; firing
	// them concurrently serializes/stalls server-Lado and loses per-row results.
	// Sequential execution keeps writes orderly and reports partial failures.
	async function runSequential(ids: string[], op: (id: string) => Promise<unkNown>): Promise<{ succeeded: number; failed: number }> {
		let succeeded = 0;
		let failed = 0;
		for (const id of ids) {
			try {
				await op(id);
				succeeded += 1;
			} catch {
				failed += 1;
			}
		}
		return { succeeded, failed };
	}

	async function runBatchAction(action: 'trash' | 'archive' | 'recover' | 'recover_Estacionadas' | 'delete') {
		const ids = rowsInView.map((row) => row.id).filter((id) => seleccionadasIds.has(id));
		if (ids.length === 0) return;

		error = null;
		actionMsg = null;

		try {
			if (action === 'trash') {
				if (!Confirmar(`Move ${ids.length} containers to Cementerio?`)) return;
				const { succeeded, failed } = await runSequential(ids, (id) => transitionStage(id, 'Cementerio', 'User moved to Cementerio from Lab Manager', 'manual'));
				actionMsg = `Moved ${succeeded} container${succeeded === 1 ? '' : 's'} to Cementerio.`;
				if (failed > 0) actionMsg += ` ${failed} failed.`;
			} else if (action === 'archive') {
				if (!Confirmar(`Archive ${ids.length} strategies? They can be recovered later.`)) return;
				const result = await batchTransitionStrategies(ids, 'archived', 'Batch archived from Lab Manager');
				const count = result.transitioned.length;
				actionMsg = `Archived ${count} strateg${count === 1 ? 'y' : 'ies'}.`;
				if (result.failed.length > 0) {
					actionMsg += ` ${result.failed.length} failed.`;
				}
			} else if (action === 'recover') {
				const { succeeded, failed } = await runSequential(ids, (id) => reviveFromCementerio(id));
				actionMsg = `Recovered ${succeeded} container${succeeded === 1 ? '' : 's'} from Cementerio.`;
				if (failed > 0) actionMsg += ` ${failed} failed.`;
			} else if (action === 'recover_Estacionadas') {
				// Estacionadas (research_only) recovery is a stage transition back to the active
				// Pipeline — NoT a Cementerio revive (which is reviveFromCementerio).
				const { succeeded, failed } = await runSequential(ids, (id) => transitionStage(id, 'Investigando', 'User batch-recovered research_only container from Lab Manager', 'manual'));
				actionMsg = `Recovered ${succeeded} container${succeeded === 1 ? '' : 's'} to the active Pipeline.`;
				if (failed > 0) actionMsg += ` ${failed} failed.`;
			} else if (action === 'delete') {
				if (!Confirmar(`Permanently delete ${ids.length} strategies? Esto no se puede deshacer.`)) return;
				const result = await batchDeleteStrategies(ids);
				const count = result.deleted.length;
				actionMsg = `Permanently deleted ${count} strateg${count === 1 ? 'y' : 'ies'}.`;
				if (result.Not_found.length > 0) actionMsg += ` ${result.Not_found.length} already gone.`;
			}
			await loadData({ forceCementerio: true });
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Batch action failed';
		}
	}

	async function trashOne(id: string) {
		if (!Confirmar('Move this container to Cementerio? You can recover it later.')) return;
		try {
			await transitionStage(id, 'Cementerio', 'User moved to Cementerio from Lab Manager', 'manual');
			actionMsg = 'Container moved to Cementerio.';
			await loadData({ forceCementerio: true });
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to move container to Cementerio';
		}
	}

	async function deleteOne(id: string) {
		if (!Confirmar('Permanently delete this strategy? Esto no se puede deshacer.')) return;
		try {
			await deleteStrategy(id);
			actionMsg = 'Strategy permanently deleted.';
			await loadData({ forceCementerio: true });
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to Eliminar estrategia';
		}
	}

	async function restoreOne(id: string) {
		try {
			await reviveFromCementerio(id);
			actionMsg = 'Container recovered from Cementerio.';
			await loadData({ forceCementerio: true });
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to recover container';
		}
	}

	async function recoverEstacionadas(id: string) {
		try {
			await transitionStage(id, 'Investigando', 'User recovered research_only container from Lab Manager', 'manual');
			actionMsg = 'Container recovered to the active Pipeline.';
			await loadData();
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to recover container';
		}
	}

	async function moveOneToStage(id: string, stage: string, selectEl: HTMLSelectElement) {
		if (!stage) return;
		selectEl.value = ''; // Reset select
		try {
			await transitionStage(id, stage, `User manually moved to ${stage} from Lab Manager`, 'manual');
			actionMsg = `Container moved to ${stage}.`;
			await loadData({ forceCementerio: true });
		} catch (e) {
			error = e instanceof Error ? e.message : `Failed to move container to ${stage}`;
		}
	}

	async function moveBatchToStage(stage: string, selectEl: HTMLSelectElement) {
		if (!stage) return;
		selectEl.value = ''; // Reset select
		const ids = rowsInView.map((row) => row.id).filter((id) => seleccionadasIds.has(id));
		if (ids.length === 0) return;
		
		if (!Confirmar(`Move ${ids.length} containers to ${stage}?`)) return;

		error = null;
		actionMsg = null;

		try {
			const { succeeded, failed } = await runSequential(ids, (id) => transitionStage(id, stage, `User batch moved to ${stage} from Lab Manager`, 'manual'));
			actionMsg = `Moved ${succeeded} container${succeeded === 1 ? '' : 's'} to ${stage}.`;
			if (failed > 0) actionMsg += ` ${failed} failed.`;
			await loadData({ forceCementerio: true });
			clearSelection();
		} catch (e) {
			error = e instanceof Error ? e.message : `Failed to batch move containers to ${stage}`;
		}
	}

	$: activeFiltered = (() => {
		// Only the visible bucket is filtered/sorted; the others return [] so a single
		// keystroke doesn't re-filter+re-sort thousands of off-screen Cementerio rows.
		if (bucket !== 'active') return [];
		const query = search.trim().toLowerCase();
		const sortField = sortBy;
		const direction = sortDirection;
		const filtered = activeResults.filter((row) => {
			if (symbolFilter !== 'all' && row.symbol !== symbolFilter) return false;
			if (stageFilter !== 'all' && row.stage !== stageFilter) return false;
			if (query) {
				if (
					!row.Nombre.toLowerCase().includes(query)
					&& !row.symbol.toLowerCase().includes(query)
					&& !row.timeframe.toLowerCase().includes(query)
					&& !row.id.toLowerCase().includes(query)
				) return false;
			}
			return true;
		});

		const ranked = filtered.map((row, index) => ({ row, index, sortValue: activeSortValue(row, sortField) }));
		ranked.sort((a, b) => {
			const cmp = compareNumeric(a.sortValue, b.sortValue, direction);
			if (cmp !== 0) return cmp;
			return a.index - b.index;
		});
		return ranked.map((entry) => entry.row);
	})();

	$: trashFiltered = (() => {
		if (bucket !== 'trash') return [];
		const query = search.trim().toLowerCase();
		const sortField = sortBy;
		const direction = sortDirection;
		const filtered = trashResults.filter((row) => {
			if (!query) return true;
			return (
				row.Nombre.toLowerCase().includes(query)
				|| row.symbol.toLowerCase().includes(query)
				|| row.timeframe.toLowerCase().includes(query)
				|| row.id.toLowerCase().includes(query)
			);
		});
		const ranked = filtered.map((row, index) => ({ row, index, sortValue: CementerioSortValue(row, sortField) }));
		ranked.sort((a, b) => {
			const cmp = compareNumeric(a.sortValue, b.sortValue, direction);
			if (cmp !== 0) return cmp;
			return a.index - b.index;
		});
		return ranked.map((entry) => entry.row);
	})();

	$: EstacionadasFiltered = (() => {
		if (bucket !== 'Estacionadas') return [];
		const query = search.trim().toLowerCase();
		const sortField = sortBy;
		const direction = sortDirection;
		const filtered = EstacionadasResults.filter((row) => {
			if (!query) return true;
			return (
				row.Nombre.toLowerCase().includes(query)
				|| row.symbol.toLowerCase().includes(query)
				|| row.timeframe.toLowerCase().includes(query)
				|| row.id.toLowerCase().includes(query)
			);
		});
		const ranked = filtered.map((row, index) => ({ row, index, sortValue: CementerioSortValue(row, sortField) }));
		ranked.sort((a, b) => {
			const cmp = compareNumeric(a.sortValue, b.sortValue, direction);
			if (cmp !== 0) return cmp;
			return a.index - b.index;
		});
		return ranked.map((entry) => entry.row);
	})();

	$: rowsInView = bucket === 'active' ? activeFiltered : bucket === 'Estacionadas' ? EstacionadasFiltered : trashFiltered;
	$: pageCount = Math.max(1, Math.ceil(rowsInView.length / pageSize));
	$: if (currentPage > pageCount) currentPage = pageCount;
	$: {
		const signature = [
			bucket,
			search.trim().toLowerCase(),
			symbolFilter,
			stageFilter,
			sortBy,
			sortDirection,
			String(pageSize),
		].join('|');
		if (signature !== lastViewSignature) {
			lastViewSignature = signature;
			currentPage = 1;
		}
	}
	$: activePageRows = activeFiltered.slice((currentPage - 1) * pageSize, currentPage * pageSize);
	$: EstacionadasPageRows = EstacionadasFiltered.slice((currentPage - 1) * pageSize, currentPage * pageSize);
	$: trashPageRows = trashFiltered.slice((currentPage - 1) * pageSize, currentPage * pageSize);
	$: seleccionadasInView = rowsInView.reduce((count, row) => (seleccionadasIds.has(row.id) ? count + 1 : count), 0);
	// Auto-dismiss the success banner after a few seconds; re-arm on each new message
	// (a single tracked timer so rapid successive actions don't leak overlapping timers).
	// The error banner is intentionally sticky — failures are higher-stakes — and is
	// cleared only by the user (× button) or the next action.
	$: if (actionMsg) {
		if (actionMsgTimer) clearTimeout(actionMsgTimer);
		actionMsgTimer = setTimeout(() => {
			actionMsg = null;
			actionMsgTimer = null;
		}, 5000);
	}
	$: selectAllChecked = rowsInView.length > 0 && seleccionadasInView === rowsInView.length;
	$: selectAllIndeterminate = seleccionadasInView > 0 && seleccionadasInView < rowsInView.length;
	$: PipelineActiveCount = activeResults.filter((row) => isPipelineActiveStage(row.stage)).length;
	$: researchOnlyCount = EstacionadasResults.filter((row) => NormalizeStage(row.stage) === 'research_only').length;
	$: failedHealthChecks = (healthData?.data_checks ?? []).filter((check) => !check.passed);
	$: healthSummaryLabel = healthError ? 'Unavailable' : !healthLoaded ? 'Loading' : healthStateLabel(healthData?.overall);
	$: healthSummaryClass = healthError ? 'text-red-400' : healthTextClass(healthData?.overall);
	$: healthSummaryDot = healthError ? 'bg-red-400' : healthDotClass(healthData?.overall);
	$: NowWorkingSummaryLabel = NowWorkingError ? 'Error' : !NowWorkingLoaded ? 'Loading' : `${NowWorkingRows.length} active`;
	$: CementerioCapped = !CementerioLoadAllOverride && CementerioStrategyLimitMode === 'capped' && trashResults.length >= CementerioStrategyLimit;

	$: symbolOptions = ['all', ...new Set(activeResults.map((row) => row.symbol).sort())];
	$: stageOptions = ['all', ...new Set(activeResults.map((row) => row.stage).sort())];

	async function triggerHighlight(id: string) {
		highlightedId = id;
		await tick();
		const el = document.querySelector(`[data-strategy-id="${CSS.escape(id)}"]`);
		if (el instanceof HTMLElement) {
			el.scrollIntoView({ behavior: 'smooth', block: 'center' });
		}
		if (highlightTimer) clearTimeout(highlightTimer);
		highlightTimer = setTimeout(() => {
			highlightedId = null;
			highlightTimer = null;
		}, 3000);

		const url = new URL(window.location.href);
		url.searchParams.delete('highlight');
		history.replaceState(history.state, '', url.toString());
	}

	onMount(async () => {
		const highlightParam = $page?.url?.searchParams?.get('highlight') ?? null;
		await refreshAll();
		if (highlightParam) {
			void triggerHighlight(highlightParam);
		}
		realtime = createRealtimeRefresh(loadData, {
			fallbackMs: 30_000,
			wsDebounceMs: 1200,
			// The strategy roster only changes on lifecycle/task events. Omit the
			// high-frequency 'trade' event (which fires continuously while paper/live
			// strategies trade) so we don't run a full multi-status re-fetch + re-parse
			// on every fill; the 30s fallback poll covers anything missed.
			wsEvents: [
				'task_queued',
				'task_status_changed',
				'task_completed',
				'task_failed',
				'strategy_transition',
				'strategy_promoted',
				'kill_switch_activated',
				'kill_switch_cleared',
				'risk_alert',
			],
		});
		realtime.start();
		NowWorkingRealtime = createRealtimeRefresh(loadNowWorking, {
			fallbackMs: 5_000,
			wsDebounceMs: 500,
			pollWhenWsOfflineOnly: false,
		});
		NowWorkingRealtime.start();
		healthRealtime = createRealtimeRefresh(loadHealth, {
			fallbackMs: 10_000,
			wsDebounceMs: 1200,
		});
		healthRealtime.start();
	});

	onDestroy(() => {
		if (typeof document !== 'undefined') {
			document.body.style.overflow = '';
		}
		realtime?.stop();
		realtime = null;
		NowWorkingRealtime?.stop();
		NowWorkingRealtime = null;
		healthRealtime?.stop();
		healthRealtime = null;
		if (highlightTimer) {
			clearTimeout(highlightTimer);
			highlightTimer = null;
		}
		if (actionMsgTimer) {
			clearTimeout(actionMsgTimer);
			actionMsgTimer = null;
		}
	});
</script>

<svelte:head>
	<title>The Forge | Forven</title>
	<meta Nombre="description" content="Manage all containers of the strategy type, complete with research metrics." />
</svelte:head>

<div class="h-full flex flex-col overflow-hidden">
	<div class="px-4 py-3 bg-[#050505] border-b border-[#222] flex-shrink-0">
		<div class="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
			<div>
				<h1 class="text-xl font-bold tracking-tight text-white">La Forja</h1>
				<p class="text-xs text-gray-500 mt-1">
					{rowsInView.length} in view · Pipeline {PipelineActiveCount} · Research-only {researchOnlyCount}
				</p>
			</div>
			<button
				type="button"
				on:click={refreshAll}
				class="self-start md:self-auto text-xs border border-[#333] px-3 py-1.5 text-gray-400 hover:text-white hover:border-white transition-colors"
			>
				Refresh
			</button>
		</div>
	</div>

	<!-- Main Manager UI -->
	<section class="flex-1 flex flex-col overflow-hidden min-h-[500px]">
		<!-- Toolbar: search, filters, status, pagination -->
		<div data-testid="forge-manager-toolbar" class="border-b border-[#222] px-4 py-2 flex items-center gap-2 flex-wrap bg-[#050505]">
			<input
				type="text"
				bind:value={search}
				placeholder={bucket === 'active' ? 'Search container, symbol, timeframe, id…' : bucket === 'Estacionadas' ? 'Search Estacionadas…' : 'Search Cementerio…'}
				class="bg-black border border-[#333] px-3 py-1.5 text-xs w-full focus:outline-None focus:border-white sm:w-72"
			/>
			{#if bucket === 'active'}
				<select
					aria-label="Filter by symbol"
					bind:value={symbolFilter}
					class="terminal-input !w-full !py-1 !px-2 text-xs sm:!w-44"
				>
					{#each symbolOptions as symbol}
						<option value={symbol}>{symbol === 'all' ? 'Todos los símbolos' : symbol}</option>
					{/each}
				</select>
				<select
					aria-label="Filter by stage"
					bind:value={stageFilter}
					class="terminal-input !w-full !py-1 !px-2 text-xs sm:!w-44"
				>
					{#each stageOptions as stage}
						<option value={stage}>{stage === 'all' ? 'Todas las etapas' : stage}</option>
					{/each}
				</select>
			{/if}
			<Detalles
				data-testid="forge-health-chip"
				class="relative w-full text-xs border border-[#333] bg-[#0a0a0a] text-gray-400 Abiertas:border-[#555] xl:w-auto"
			>
				<summary class="list-None cursor-pointer px-2.5 py-1.5 inline-flex w-full items-center gap-2 xl:w-auto">
					<span class={`inline-flex h-2 w-2 rounded-full ${healthSummaryDot}`}></span>
					<span class="uppercase tracking-[0.14em] text-[10px]">Salud del Sistema</span>
					<span class={`font-medium ${healthSummaryClass}`}>{healthSummaryLabel}</span>
					{#if failedHealthChecks.length > 0}
						<span class="text-[10px] text-red-300">{failedHealthChecks.length} issue{failedHealthChecks.length !== 1 ? 's' : ''}</span>
					{/if}
				</summary>
				<div class="absolute left-0 top-full z-30 mt-1 max-h-[min(24rem,calc(100vh-12rem))] w-[calc(100vw-2rem)] max-w-[calc(100vw-2rem)] overflow-y-auto border-t border-[#222] bg-[#080808] p-2 text-[11px] shadow-xl xl:w-80 xl:max-w-[420px]">
					{#if healthError}
						<div class="text-red-400 flex items-center gap-2">
							<span>{healthError}</span>
							<button type="button" class="underline" on:click={loadHealth}>Reintentar</button>
						</div>
					{:else if !healthLoaded}
						<div class="text-gray-500">Loading…</div>
					{:else}
						<div class="space-y-1">
							{#each healthData?.components ?? [] as comp (comp.Nombre)}
								<div class="flex items-center gap-2">
									<span class={`inline-flex h-1.5 w-1.5 rounded-full ${healthDotClass(comp.state)}`}></span>
									<span class="text-gray-300">{friendlyHealthNombre(comp.Nombre)}</span>
									<span class={healthTextClass(comp.state)}>{healthStateLabel(comp.state)}</span>
									<span class="text-gray-600 truncate">{comp.message}</span>
								</div>
							{/each}
							{#if (healthData?.components ?? []).length === 0}
								<div class="text-gray-600">No components registered.</div>
							{/if}
						</div>
						{#if (healthData?.data_checks ?? []).length > 0}
							<div class="mt-2 border-t border-[#1a1a1a] pt-2 space-y-1">
								{#each healthData?.data_checks ?? [] as check (check.Nombre)}
									<div class={check.passed ? 'text-gray-500' : check.severity === 'critical' ? 'text-red-400' : 'text-yellow-300'}>
										{friendlyHealthNombre(check.Nombre)}: {check.detail}
									</div>
								{/each}
							</div>
						{/if}
					{/if}
				</div>
			</Detalles>
			<Detalles
				data-testid="forge-Now-working-chip"
				class="relative w-full text-xs border border-[#333] bg-[#0a0a0a] text-gray-400 Abiertas:border-[#555] xl:w-auto"
			>
				<summary class="list-None cursor-pointer px-2.5 py-1.5 inline-flex w-full items-center gap-2 xl:w-auto">
					<span class={`inline-flex h-2 w-2 rounded-full ${NowWorkingError ? 'bg-red-400' : NowWorkingLoaded && NowWorkingRows.length > 0 ? 'bg-cyan-400' : 'bg-gray-500'}`}></span>
					<span class="uppercase tracking-[0.14em] text-[10px]">Now Working</span>
					<span class={NowWorkingError ? 'text-red-400 font-medium' : 'text-cyan-300 font-medium'}>{NowWorkingSummaryLabel}</span>
				</summary>
				<div class="absolute left-0 top-full z-30 mt-1 max-h-[min(24rem,calc(100vh-12rem))] w-[calc(100vw-2rem)] max-w-[calc(100vw-2rem)] overflow-y-auto border-t border-[#222] bg-[#080808] p-2 text-[11px] shadow-xl xl:w-[32rem] xl:max-w-[520px]">
					{#if NowWorkingError}
						<div class="text-red-400 flex items-center gap-2">
							<span>Error al cargar active work</span>
							<button type="button" class="underline" on:click={loadNowWorking}>Reintentar</button>
						</div>
					{:else if !NowWorkingLoaded}
						<div class="text-gray-500">Loading…</div>
					{:else if NowWorkingRows.length === 0}
						<div class="text-gray-500">Engine INACTIVO.</div>
					{:else}
						<ul class="space-y-1">
							{#each NowWorkingRows as row (`${row.strategy_id}:${row.current_task.type}`)}
								{@const hasStrategy = !String(row.strategy_id).startsWith('task-')}
								<li>
									{#if hasStrategy}
										<button
											type="button"
											class="w-full text-left hover:bg-[#111] px-2 py-1 flex items-center gap-3"
											on:click={() => goto(`/lab/strategy/${encodeURIComponent(row.strategy_id)}?returnTo=${encodeURIComponent('/lab')}`)}
										>
											<span class="font-moNo text-gray-300 truncate flex-1">{row.Nombre}</span>
											{#if row.stage}
												<span class={`text-[10px] px-1.5 py-0.5 border rounded uppercase ${stageClass(row.stage)}`}>{row.stage}</span>
											{/if}
											<span class="text-gray-500">{row.current_task.type}</span>
											<span class="uppercase {row.current_task.status === 'running' ? 'text-emerald-400' : 'text-yellow-400'}">
												{row.current_task.status}
											</span>
											{#if row.current_task.stalled}
												<span class="uppercase text-red-400 border border-red-900 px-1">stalled</span>
											{/if}
										</button>
									{:else}
										<div class="w-full text-left px-2 py-1 flex items-center gap-3">
											<span class="font-moNo text-gray-400 truncate flex-1">{row.Nombre}</span>
											<span class="text-gray-500">{row.current_task.type}</span>
											<span class="uppercase {row.current_task.status === 'running' ? 'text-emerald-400' : 'text-yellow-400'}">
												{row.current_task.status}
											</span>
											{#if row.current_task.stalled}
												<span class="uppercase text-red-400 border border-red-900 px-1">stalled</span>
											{/if}
										</div>
									{/if}
								</li>
							{/each}
						</ul>
					{/if}
				</div>
			</Detalles>
			<span class="text-[10px] text-gray-500 ml-1">
				{rowsInView.length} items
				{#if rowsInView.length > (bucket === 'active' ? activePageRows.length : bucket === 'Estacionadas' ? EstacionadasPageRows.length : trashPageRows.length)}
					(showing {bucket === 'active' ? activePageRows.length : bucket === 'Estacionadas' ? EstacionadasPageRows.length : trashPageRows.length})
				{/if}
			</span>
			<div class="ml-auto flex items-center gap-2 text-[10px] text-gray-500">
				<label for="manager-page-size">Filas</label>
				<select
					id="manager-page-size"
					class="terminal-input !py-1 !px-2"
					value={String(pageSize)}
					on:change={(event) => {
						const value = Number((event.currentTarget as HTMLSelectElement).value);
						pageSize = Number.isFinite(value) && value > 0 ? value : 100;
					}}
				>
					<option value="50">50</option>
					<option value="100">100</option>
					<option value="200">200</option>
					<option value="500">500</option>
				</select>
				<button
					type="button"
					class="px-2 py-1 border border-[#333] text-gray-400 hover:text-white hover:border-white disabled:opacity-40 disabled:cursor-Not-allowed"
					on:click={goPrevPage}
					disabled={currentPage <= 1}
				>
					Prev
				</button>
				<span>{currentPage}/{pageCount}</span>
				<button
					type="button"
					class="px-2 py-1 border border-[#333] text-gray-400 hover:text-white hover:border-white disabled:opacity-40 disabled:cursor-Not-allowed"
					on:click={goNextPage}
					disabled={currentPage >= pageCount}
				>
					Next
				</button>
			</div>
		</div>

		<!-- Bucket filter buttons (aria-pressed toggle semantics rather than a full
		     APG tablist, since there is No arrow-key tab navigation). -->
		<div role="group" aria-label="Strategy buckets" class="border-b border-[#222] bg-[#070707] px-4 flex items-end gap-1 flex-wrap">
			<button
				type="button"
				aria-pressed={bucket === 'active'}
				on:click={() => { bucket = 'active'; clearSelection(); }}
				class="relative px-4 py-2 text-xs font-medium transition-colors border-b-2 {bucket === 'active' ? 'border-white text-white' : 'border-transparent text-gray-400 hover:text-gray-200'}"
			>
				Abiertas <span class="ml-1 text-gray-500">({activeResults.length})</span>
			</button>
			<button
				type="button"
				aria-pressed={bucket === 'Estacionadas'}
				on:click={() => { bucket = 'Estacionadas'; clearSelection(); }}
				class="relative px-4 py-2 text-xs font-medium transition-colors border-b-2 {bucket === 'Estacionadas' ? 'border-white text-white' : 'border-transparent text-gray-400 hover:text-gray-200'}"
			>
				Estacionadas <span class="ml-1 text-gray-500">({EstacionadasResults.length})</span>
			</button>
			<button
				type="button"
				aria-pressed={bucket === 'trash'}
				on:click={() => { bucket = 'trash'; clearSelection(); }}
				class="relative px-4 py-2 text-xs font-medium transition-colors border-b-2 {bucket === 'trash' ? 'border-white text-white' : 'border-transparent text-gray-400 hover:text-gray-200'}"
			>
				Cementerio <span class="ml-1 text-gray-500">({trashResults.length})</span>
				{#if CementerioLoading}
					<span class="ml-1 text-gray-600">loading</span>
				{/if}
			</button>
			{#if bucket === 'trash' && CementerioCapped}
				<span class="ml-3 pb-2 text-[10px] tracking-wide text-amber-400/80">
					Showing first {CementerioStrategyLimit} archived/rejected — older ones are Not loaded.
				</span>
				<button
					type="button"
					class="ml-2 pb-2 text-[10px] underline text-amber-300 hover:text-amber-200 disabled:opacity-50"
					on:click={loadAllCementerio}
					disabled={CementerioLoading}
				>
					{CementerioLoading ? 'Loading…' : 'Load all'}
				</button>
			{/if}
		</div>

		{#if actionMsg}
			<div role="status" aria-live="polite" class="mx-4 mt-3 bg-green-900/20 border border-green-800 text-green-300 text-xs px-3 py-2 rounded flex items-start gap-2">
				<span class="flex-1">{actionMsg}</span>
				<button type="button" class="shrink-0 text-green-300/70 hover:text-green-100 leading-None" aria-label="Dismiss message" on:click={() => (actionMsg = null)}>×</button>
			</div>
		{/if}
		{#if error}
			<div role="alert" aria-live="assertive" class="mx-4 mt-3 bg-red-900/20 border border-red-800 text-red-300 text-xs px-3 py-2 rounded flex items-start gap-2">
				<span class="flex-1">{error}</span>
				<button type="button" class="shrink-0 text-red-300/70 hover:text-red-100 leading-None" aria-label="Dismiss error" on:click={() => (error = null)}>×</button>
			</div>
		{/if}

		<!-- Bulk-action bar: only visible when rows are seleccionadas -->
		{#if seleccionadasInView > 0}
			<div class="border-b border-[#222] bg-[#0c0c0c] px-4 py-2 flex items-center gap-3 text-xs">
				<span class="text-white font-medium">{seleccionadasInView} seleccionadas</span>
				<button
					type="button"
					class="text-gray-400 hover:text-white transition-colors"
					on:click={selectFiltered}
				>
					Select all {rowsInView.length} matching
				</button>
				<button
					type="button"
					class="text-gray-400 hover:text-white transition-colors"
					on:click={clearSelection}
				>
					Clear selection
				</button>
				<div class="ml-auto flex items-center gap-2">
					{#if bucket === 'active'}
						<select
							aria-label="Move seleccionadas strategies to stage"
							class="px-2 py-1 border border-blue-700 bg-blue-900/20 text-blue-300 text-xs outline-None cursor-pointer"
							on:change={(e) => moveBatchToStage(e.currentTarget.value, e.currentTarget)}
						>
							<option value="" disabled seleccionadas>Mover etapa…</option>
							<option value="Investigando">Investigando</option>
							<option value="developing">Desarrollando</option>
							<option value="Backtesting">BackProbando</option>
							<option value="paper_trading">Trading en Papel</option>
							<option value="deployed">Desplegada</option>
							<option value="rejected">Rechazadas</option>
						</select>
						<button type="button" class="px-2 py-1 border border-gray-600 text-gray-300 hover:bg-gray-900/20" on:click={() => runBatchAction('archive')}>Archivar</button>
						<button type="button" class="px-2 py-1 border border-yellow-700 text-yellow-300 hover:bg-yellow-900/20" on:click={() => runBatchAction('trash')}>Cementerio</button>
						<button type="button" class="px-2 py-1 border border-red-700 text-red-300 hover:bg-red-900/20" on:click={() => runBatchAction('delete')}>Eliminar</button>
					{:else if bucket === 'Estacionadas'}
						<button type="button" class="px-2 py-1 border border-cyan-700 text-cyan-300 hover:bg-cyan-900/20" on:click={() => runBatchAction('recover_Estacionadas')}>Recuperar</button>
						<button type="button" class="px-2 py-1 border border-red-700 text-red-300 hover:bg-red-900/20" on:click={() => runBatchAction('delete')}>Eliminar</button>
					{:else if bucket === 'trash'}
						<button type="button" class="px-2 py-1 border border-cyan-700 text-cyan-300 hover:bg-cyan-900/20" on:click={() => runBatchAction('recover')}>Recuperar</button>
						<button type="button" class="px-2 py-1 border border-red-700 text-red-300 hover:bg-red-900/20" on:click={() => runBatchAction('delete')}>Eliminar permanentemente</button>
					{/if}
				</div>
			</div>
		{:else if bucket === 'Estacionadas'}
			<div class="border-b border-[#222] bg-[#0a0a0a] px-4 py-2 text-[10px] text-gray-500">
				Contenedores solo de investigación. Select rows to batch-recover them into the active Pipeline, or use the per-row Recover button.
			</div>
		{/if}

		<div class="flex-1 overflow-auto bg-black">
				<table class="w-full min-w-[1100px] text-xs">
					{#if bucket === 'active'}
						<thead class="sticky top-0 bg-[#0d0d0d] z-10">
							<tr class="text-gray-500 border-b border-[#222]">
								<th class="py-2 px-2 text-left w-8">
									<input
										type="checkbox"
										class="Acento-white w-3 h-3 align-middle"
										aria-label="Seleccionar todas las coincidentes strategies"
										checked={selectAllChecked}
										indeterminate={selectAllIndeterminate}
										on:change={toggleSelectAll}
									/>
								</th>
								<th class="py-2 px-2 text-left">Estrategia</th>
								<th class="py-2 px-2 text-left">Par/TF</th>
								<th class="py-2 px-2 text-left">Stage</th>
								<SortableTh field="CAGR" label="CAGR" active={sortBy === 'CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window CAGR (annualized over IS + OOS). Short windows are shown with muted styling." />
								<SortableTh field="Sharpe" label="Sharpe ⓘ" active={sortBy === 'Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Sharpe (approximate: month-weighted average of IS and OOS Sharpe, Not recomputed from the combined return stream). ≥1.0 strong, ≥0.5 good, >0 weak, ≤0 poor. Low-trade samples are shown with muted styling." />
								<SortableTh field="drawdown" label="DD Máx ⓘ" active={sortBy === 'drawdown'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Pérdida Máxima (approximate: max of IS and OOS Pérdida Máximas; a drawdown that straddles the IS/OOS boundary is understated). ≤20% good, ≤35% marginal, >35% poor." />
								<SortableTh field="win_rate" label="Win%" active={sortBy === 'win_rate'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window win rate = combined wins / combined closed trades. ≥55% good, ≥45% marginal." />
								<SortableTh field="trades" label="Trades" active={sortBy === 'trades'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Total completed trades across IS + OOS." />
								<SortableTh field="profit_factor" label="PF" active={sortBy === 'profit_factor'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window profit factor = combined gross profit / combined gross loss. ≥1.5 good, ≥1.0 marginal. ∞ if No losing trades." />
								<SortableTh field="robustness" label="Rob%" active={sortBy === 'robustness'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Gauntlet robustness score; below 70 fails gate." />
								<SortableTh field="out_of_sample_CAGR" label="OOS CAGR" active={sortBy === 'out_of_sample_CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} thClass="border-l border-[#222] pl-3" title="Out-of-sample CAGR (annualized). Short windows are shown with muted styling." />
								<SortableTh field="out_of_sample_Sharpe" label="OOS Sharpe" active={sortBy === 'out_of_sample_Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Out-of-sample annualized Sharpe. Low-trade samples are shown with muted styling." />
								<SortableTh field="created" label="Created" active={sortBy === 'created'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} />
								<th class="py-2 px-2 text-right">Acciones</th>
							</tr>
						</thead>
						<tbody>
							{#if loading}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">Cargando contenedores...</td></tr>
							{:else if activeFiltered.length === 0}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">Ningún contenedor activo coincide con esta vista.</td></tr>
							{:else}
								{#each activePageRows as row (row.id)}
									{@const recovery = recoveryBadge(row)}
									<tr
										data-strategy-id={row.id}
										class="border-t border-[#181818] hover:bg-[#0f0f0f]"
										class:strategy-row-highlight={row.id === highlightedId}
									>
										<td class="py-2 px-2">
											<input type="checkbox" class="Acento-white w-3 h-3" checked={seleccionadasIds.has(row.id)} on:change={() => toggleSelect(row.id)} />
										</td>
										<td class="py-2 px-2 text-white font-medium max-w-[360px]">
											<StrategyLink
												strategyId={row.id}
												label={row.Nombre}
												returnTo="/lab"
												classNombre="max-w-full truncate bg-transparent border-0 px-0 py-0 text-left text-white hover:text-cyan-300"
											/>
											<div class="text-[10px] text-gray-600 font-moNo mt-0.5">{row.id}</div>
											{#if row.hypothesis_id}
												<a href={`/hypotheses/${encodeURIComponent(row.hypothesis_display_id || row.hypothesis_id)}`} class="mt-1 inline-flex items-center gap-1 rounded border border-[#2a2a2a] bg-black/60 px-2 py-0.5 text-[10px] uppercase tracking-[0.18em] text-gray-400 transition hover:border-cyan-500/40 hover:text-cyan-200">
													Hypothesis {row.hypothesis_display_id || row.hypothesis_id}
												</a>
											{/if}
											{#if row.source === 'ai_dropzone' || !row.has_backtest_results || recovery}
												<div class="mt-1 flex flex-wrap gap-1">
													{#if row.source === 'ai_dropzone'}
														<span class={`text-[9px] px-1.5 py-0.5 border rounded uppercase ${badgeClass('source')}`}>AI Drop Zone</span>
													{/if}
													{#if !row.has_backtest_results}
														<span class={`text-[9px] px-1.5 py-0.5 border rounded uppercase ${badgeClass('untested')}`}>Untested</span>
													{/if}
													{#if recovery}
														<span class={`text-[9px] px-1.5 py-0.5 border rounded uppercase ${recovery.classNombre}`}>{recovery.label}</span>
													{/if}
												</div>
											{/if}
										</td>
										<td class="py-2 px-2 text-gray-300 font-moNo">{row.symbol} / {row.timeframe}</td>
										<td class="py-2 px-2">
											<span class={`text-[10px] px-1.5 py-0.5 border rounded uppercase ${stageClass(row.stage)}`}>{row.stage}</span>
										</td>
										<td class={`py-2 px-2 font-moNo ${row.CAGR_is_reliable ? metricClass('return', row.annualized_return) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Full-window CAGR (annualized over IS + OOS)' : 'Window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.annualized_return, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.Sharpe_ratio) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Full-window Sharpe (approximate: month-weighted average of IS and OOS)' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.Sharpe_ratio, 2)}{row.Sharpe_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('drawdown', row.max_drawdown)}`} title={row.max_drawdown_is_approximation ? 'Full-window DD Máx (approximate: max of IS and OOS halves)' : 'Maximum peak-to-trough drawdown'}>{formatPercent(row.max_drawdown, 2)}{row.max_drawdown_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('win_rate', row.win_rate)}`}>{formatPercent(row.win_rate, 1)}</td>
										<td class="py-2 px-2 font-moNo text-gray-300">{formatNumber(row.total_trades, 0)}</td>
										<td class={`py-2 px-2 font-moNo ${row.profit_factor_is_infinite ? 'text-emerald-400' : metricClass('profit_factor', row.profit_factor)}`} title={row.profit_factor_is_infinite ? 'No losing trades — profit factor is mathematically infinite' : 'Full-window profit factor'}>{row.profit_factor_is_infinite ? '∞' : formatNumber(row.profit_factor, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('robustness', row.robustness_score)}`}>{formatPercent(row.robustness_score, 1)}</td>
										<td class={`py-2 px-2 font-moNo border-l border-[#222] pl-3 ${row.CAGR_is_reliable ? metricClass('return', row.out_of_sample_CAGR) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Out-of-sample CAGR (annualized)' : 'OOS window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.out_of_sample_CAGR, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.out_of_sample_Sharpe) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Out-of-sample annualized Sharpe' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.out_of_sample_Sharpe, 2)}</td>
										<td class="py-2 px-2 text-gray-500">{formatDateTime(row.created_at)}</td>
										<td class="py-2 px-2 text-right">
											<div class="inline-flex flex-wrap justify-end items-center gap-2">
												<select
													aria-label="Move strategy to stage"
													class="text-xs bg-transparent text-gray-400 hover:text-white outline-None cursor-pointer border border-[#333] hover:border-[#555] rounded px-1 py-0.5"
													on:change={(e) => moveOneToStage(row.id, e.currentTarget.value, e.currentTarget)}
													title="Move to aNother stage"
												>
													<option value="" disabled seleccionadas>Move to...</option>
													<option value="Investigando">Investigando</option>
													<option value="developing">Desarrollando</option>
													<option value="Backtesting">BackProbando</option>
													<option value="paper_trading">Trading en Papel</option>
													<option value="deployed">Desplegada</option>
													<option value="rejected">Rechazadas</option>
												</select>
												<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => AbiertasContainer(row)}>Detalles</button>
												<button type="button" class="text-yellow-300 hover:text-yellow-200" on:click={() => trashOne(row.id)}>Cementerio</button>
												<button type="button" class="text-red-400 hover:text-red-300" on:click={() => deleteOne(row.id)}>Eliminar</button>
											</div>
										</td>
									</tr>
								{/each}
							{/if}
						</tbody>
					{:else if bucket === 'Estacionadas'}
						<thead class="sticky top-0 bg-[#0d0d0d] z-10">
							<tr class="text-gray-500 border-b border-[#222]">
									<th class="py-2 px-2 text-left w-8"><input type="checkbox" class="Acento-white w-3 h-3 align-middle" aria-label="Seleccionar todas las coincidentes strategies" checked={selectAllChecked} indeterminate={selectAllIndeterminate} on:change={toggleSelectAll} /></th>
								<th class="py-2 px-2 text-left">Estrategia</th>
								<th class="py-2 px-2 text-left">Par/TF</th>
								<th class="py-2 px-2 text-left">Stage</th>
								<SortableTh field="CAGR" label="CAGR" active={sortBy === 'CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window CAGR (annualized over IS + OOS). Short windows are shown with muted styling." />
								<SortableTh field="Sharpe" label="Sharpe ⓘ" active={sortBy === 'Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Sharpe (approximate: month-weighted average of IS and OOS Sharpe). ≥1.0 strong, ≥0.5 good, >0 weak, ≤0 poor." />
								<SortableTh field="drawdown" label="DD Máx ⓘ" active={sortBy === 'drawdown'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Pérdida Máxima (approximate: max of IS and OOS halves). ≤20% good, ≤35% marginal, >35% poor." />
								<SortableTh field="win_rate" label="Win%" active={sortBy === 'win_rate'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window win rate = combined wins / combined closed trades." />
								<SortableTh field="trades" label="Trades" active={sortBy === 'trades'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Total completed trades across IS + OOS." />
								<SortableTh field="profit_factor" label="PF" active={sortBy === 'profit_factor'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window profit factor. ≥1.5 good, ≥1.0 marginal. ∞ if No losing trades." />
								<SortableTh field="robustness" label="Rob%" active={sortBy === 'robustness'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Gauntlet robustness score; below 70 fails gate." />
								<SortableTh field="out_of_sample_CAGR" label="OOS CAGR" active={sortBy === 'out_of_sample_CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} thClass="border-l border-[#222] pl-3" title="Out-of-sample CAGR (annualized). Short windows are shown with muted styling." />
								<SortableTh field="out_of_sample_Sharpe" label="OOS Sharpe" active={sortBy === 'out_of_sample_Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Out-of-sample annualized Sharpe. Low-trade samples are shown with muted styling." />
								<SortableTh field="created" label="Created" active={sortBy === 'created'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} />
								<th class="py-2 px-2 text-right">Acciones</th>
							</tr>
						</thead>
						<tbody>
							{#if loading}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">Loading Estacionadas containers...</td></tr>
							{:else if EstacionadasFiltered.length === 0}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">No Estacionadas strategies.</td></tr>
							{:else}
								{#each EstacionadasPageRows as row (row.id)}
									<tr class="border-t border-[#181818] hover:bg-[#0f0f0f]">
										<td class="py-2 px-2"><input type="checkbox" class="Acento-white w-3 h-3" checked={seleccionadasIds.has(row.id)} on:change={() => toggleSelect(row.id)} /></td>
										<td class="py-2 px-2 text-white font-medium max-w-[420px]">
											<StrategyLink
												strategyId={row.id}
												label={row.Nombre}
												returnTo="/lab"
												classNombre="max-w-full truncate bg-transparent border-0 px-0 py-0 text-left text-white hover:text-cyan-300"
											/>
											<div class="text-[10px] text-gray-600 font-moNo mt-0.5">{row.id}</div>
											{#if row.hypothesis_id}
												<a href={`/hypotheses/${encodeURIComponent(row.hypothesis_display_id || row.hypothesis_id)}`} class="mt-1 inline-flex items-center gap-1 rounded border border-[#2a2a2a] bg-black/60 px-2 py-0.5 text-[10px] uppercase tracking-[0.18em] text-gray-400 transition hover:border-cyan-500/40 hover:text-cyan-200">
													Hypothesis {row.hypothesis_display_id || row.hypothesis_id}
												</a>
											{/if}
										</td>
										<td class="py-2 px-2 text-gray-300 font-moNo">{row.symbol} / {row.timeframe}</td>
										<td class="py-2 px-2">
											<span class={`text-[10px] px-1.5 py-0.5 border rounded uppercase ${stageClass(row.stage)}`}>{row.stage}</span>
										</td>
										<td class={`py-2 px-2 font-moNo ${row.CAGR_is_reliable ? metricClass('return', row.annualized_return) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Full-window CAGR (annualized over IS + OOS)' : 'Window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.annualized_return, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.Sharpe_ratio) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Full-window Sharpe (approximate: month-weighted average of IS and OOS)' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.Sharpe_ratio, 2)}{row.Sharpe_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('drawdown', row.max_drawdown)}`} title={row.max_drawdown_is_approximation ? 'Full-window DD Máx (approximate: max of IS and OOS halves)' : 'Maximum peak-to-trough drawdown'}>{formatPercent(row.max_drawdown, 2)}{row.max_drawdown_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('win_rate', row.win_rate)}`}>{formatPercent(row.win_rate, 1)}</td>
										<td class="py-2 px-2 font-moNo text-gray-300">{formatNumber(row.total_trades, 0)}</td>
										<td class={`py-2 px-2 font-moNo ${row.profit_factor_is_infinite ? 'text-emerald-400' : metricClass('profit_factor', row.profit_factor)}`} title={row.profit_factor_is_infinite ? 'No losing trades — profit factor is mathematically infinite' : 'Full-window profit factor'}>{row.profit_factor_is_infinite ? '∞' : formatNumber(row.profit_factor, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('robustness', row.robustness_score)}`}>{formatPercent(row.robustness_score, 1)}</td>
										<td class={`py-2 px-2 font-moNo border-l border-[#222] pl-3 ${row.CAGR_is_reliable ? metricClass('return', row.out_of_sample_CAGR) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Out-of-sample CAGR (annualized)' : 'OOS window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.out_of_sample_CAGR, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.out_of_sample_Sharpe) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Out-of-sample annualized Sharpe' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.out_of_sample_Sharpe, 2)}</td>
										<td class="py-2 px-2 text-gray-500">{formatDateTime(row.created_at)}</td>
										<td class="py-2 px-2 text-right space-x-2 whitespace-Nowrap">
											<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => AbiertasContainer(row)}>Detalles</button>
											<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => recoverEstacionadas(row.id)} title="Move this research-only container back into the active Pipeline">Recuperar</button>
										</td>
									</tr>
								{/each}
							{/if}
						</tbody>
					{:else}
						<thead class="sticky top-0 bg-[#0d0d0d] z-10">
							<tr class="text-gray-500 border-b border-[#222]">
								<th class="py-2 px-2 text-left w-8">
									<input
										type="checkbox"
										class="Acento-white w-3 h-3 align-middle"
										aria-label="Seleccionar todas las coincidentes strategies"
										checked={selectAllChecked}
										indeterminate={selectAllIndeterminate}
										on:change={toggleSelectAll}
									/>
								</th>
								<th class="py-2 px-2 text-left">Estrategia</th>
								<th class="py-2 px-2 text-left">Par/TF</th>
								<th class="py-2 px-2 text-left">Stage</th>
								<SortableTh field="CAGR" label="CAGR" active={sortBy === 'CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window CAGR (annualized over IS + OOS). Short windows are shown with muted styling." />
								<SortableTh field="Sharpe" label="Sharpe ⓘ" active={sortBy === 'Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Sharpe (approximate: month-weighted average of IS and OOS Sharpe, Not recomputed from the combined return stream). ≥1.0 strong, ≥0.5 good, >0 weak, ≤0 poor. Low-trade samples are shown with muted styling." />
								<SortableTh field="drawdown" label="DD Máx ⓘ" active={sortBy === 'drawdown'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window Pérdida Máxima (approximate: max of IS and OOS Pérdida Máximas; a drawdown that straddles the IS/OOS boundary is understated). ≤20% good, ≤35% marginal, >35% poor." />
								<SortableTh field="win_rate" label="Win%" active={sortBy === 'win_rate'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window win rate = combined wins / combined closed trades. ≥55% good, ≥45% marginal." />
								<SortableTh field="trades" label="Trades" active={sortBy === 'trades'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Total completed trades across IS + OOS." />
								<SortableTh field="profit_factor" label="PF" active={sortBy === 'profit_factor'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Full-window profit factor = combined gross profit / combined gross loss. ≥1.5 good, ≥1.0 marginal. ∞ if No losing trades." />
								<SortableTh field="robustness" label="Rob%" active={sortBy === 'robustness'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Gauntlet robustness score; below 70 fails gate." />
								<SortableTh field="out_of_sample_CAGR" label="OOS CAGR" active={sortBy === 'out_of_sample_CAGR'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} thClass="border-l border-[#222] pl-3" title="Out-of-sample CAGR (annualized). Short windows are shown with muted styling." />
								<SortableTh field="out_of_sample_Sharpe" label="OOS Sharpe" active={sortBy === 'out_of_sample_Sharpe'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} title="Out-of-sample annualized Sharpe. Low-trade samples are shown with muted styling." />
								<SortableTh field="created" label="Created" active={sortBy === 'created'} direction={sortDirection} on:sort={(e) => toggleSort(e.detail as SortField)} />
								<th class="py-2 px-2 text-right">Acciones</th>
							</tr>
						</thead>
						<tbody>
							{#if loading || CementerioLoading}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">Loading Cementerio...</td></tr>
							{:else if trashFiltered.length === 0}
								<tr><td colspan="15" class="py-8 text-center text-gray-600">Cementerio is empty.</td></tr>
							{:else}
								{#each trashPageRows as row (row.id)}
									<tr class="border-t border-[#181818] hover:bg-[#0f0f0f]">
										<td class="py-2 px-2">
											<input type="checkbox" class="Acento-white w-3 h-3" checked={seleccionadasIds.has(row.id)} on:change={() => toggleSelect(row.id)} />
										</td>
										<td class="py-2 px-2 text-white font-medium max-w-[420px]">
											<StrategyLink
												strategyId={row.id}
												label={row.Nombre}
												returnTo="/lab"
												classNombre="max-w-full truncate bg-transparent border-0 px-0 py-0 text-left text-white hover:text-cyan-300"
											/>
											<div class="text-[10px] text-gray-600 font-moNo mt-0.5">{row.id}</div>
											{#if row.hypothesis_id}
												<a href={`/hypotheses/${encodeURIComponent(row.hypothesis_display_id || row.hypothesis_id)}`} class="mt-1 inline-flex items-center gap-1 rounded border border-[#2a2a2a] bg-black/60 px-2 py-0.5 text-[10px] uppercase tracking-[0.18em] text-gray-400 transition hover:border-cyan-500/40 hover:text-cyan-200">
													Hypothesis {row.hypothesis_display_id || row.hypothesis_id}
												</a>
											{/if}
											{#if row.source === 'ai_dropzone' || !row.has_backtest_results}
												<div class="mt-1 flex flex-wrap gap-1">
													{#if row.source === 'ai_dropzone'}
														<span class={`text-[9px] px-1.5 py-0.5 border rounded uppercase ${badgeClass('source')}`}>AI Drop Zone</span>
													{/if}
													{#if !row.has_backtest_results}
														<span class={`text-[9px] px-1.5 py-0.5 border rounded uppercase ${badgeClass('untested')}`}>Untested</span>
													{/if}
												</div>
											{/if}
										</td>
										<td class="py-2 px-2 text-gray-300 font-moNo">{row.symbol} / {row.timeframe}</td>
										<td class="py-2 px-2">
											<span class={`text-[10px] px-1.5 py-0.5 border rounded uppercase ${stageClass(row.stage)}`}>{row.stage}</span>
										</td>
										<td class={`py-2 px-2 font-moNo ${row.CAGR_is_reliable ? metricClass('return', row.annualized_return) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Full-window CAGR (annualized over IS + OOS)' : 'Window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.annualized_return, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.Sharpe_ratio) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Full-window Sharpe (approximate: month-weighted average of IS and OOS)' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.Sharpe_ratio, 2)}{row.Sharpe_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('drawdown', row.max_drawdown)}`} title={row.max_drawdown_is_approximation ? 'Full-window DD Máx (approximate: max of IS and OOS halves)' : 'Maximum peak-to-trough drawdown'}>{formatPercent(row.max_drawdown, 2)}{row.max_drawdown_is_approximation ? ' ~' : ''}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('win_rate', row.win_rate)}`}>{formatPercent(row.win_rate, 1)}</td>
										<td class="py-2 px-2 font-moNo text-gray-300">{formatNumber(row.total_trades, 0)}</td>
										<td class={`py-2 px-2 font-moNo ${row.profit_factor_is_infinite ? 'text-emerald-400' : metricClass('profit_factor', row.profit_factor)}`} title={row.profit_factor_is_infinite ? 'No losing trades — profit factor is mathematically infinite' : 'Full-window profit factor'}>{row.profit_factor_is_infinite ? '∞' : formatNumber(row.profit_factor, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${metricClass('robustness', row.robustness_score)}`}>{formatPercent(row.robustness_score, 1)}</td>
										<td class={`py-2 px-2 font-moNo border-l border-[#222] pl-3 ${row.CAGR_is_reliable ? metricClass('return', row.out_of_sample_CAGR) : 'text-gray-500 italic'}`} title={row.CAGR_is_reliable ? 'Out-of-sample CAGR (annualized)' : 'OOS window too short (<1 month) — annualized value may be unreliable'}>{formatPercent(row.out_of_sample_CAGR, 2)}</td>
										<td class={`py-2 px-2 font-moNo ${row.Sharpe_is_reliable ? metricClass('Sharpe', row.out_of_sample_Sharpe) : 'text-gray-500'}`} title={row.Sharpe_is_reliable ? 'Out-of-sample annualized Sharpe' : 'Low trade count (<20) — Sharpe may be Noisy'}>{formatNumber(row.out_of_sample_Sharpe, 2)}</td>
										<td class="py-2 px-2 text-gray-500">
											<div>{formatDateTime(row.created_at)}</div>
											<div class="text-[10px] text-gray-600">Archived {formatDateTime(row.deleted_at || row.created_at)}</div>
										</td>
										<td class="py-2 px-2 text-right space-x-2 whitespace-Nowrap">
											<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => AbiertasContainer(row)}>Detalles</button>
											<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => restoreOne(row.id)}>Recuperar</button>
											<button type="button" class="text-red-400 hover:text-red-300" on:click={() => deleteOne(row.id)}>Eliminar</button>
										</td>
									</tr>
								{/each}
							{/if}
						</tbody>
					{/if}
			</table>
		</div>
	</section>
</div>

<style>
	tr.strategy-row-highlight {
		animation: strategy-highlight-pulse 0.9s ease-in-out 3;
		background-color: rgba(34, 211, 238, 0.12);
		outline: 1px solid rgba(34, 211, 238, 0.6);
		outline-offset: -1px;
	}
	@keyframes strategy-highlight-pulse {
		0%, 100% {
			background-color: rgba(34, 211, 238, 0.08);
		}
		50% {
			background-color: rgba(34, 211, 238, 0.22);
		}
	}
</style>
