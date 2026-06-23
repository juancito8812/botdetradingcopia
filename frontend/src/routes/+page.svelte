<script lang="ts">
	import { onMount, onDestroy } from "svelte";
	import {
		getPanel de ControlReanudarn,
		getPanel de ControlActivity,
		getPanel de ControlWinners,
	} from "$lib/api";
	import type {
		Panel de ControlReanudarn,
		Panel de ControlActivityItem,
		WinnerEntry,
	} from "$lib/api";
	import { backendConectado } from "$lib/stores";
	import {
		createRealtimeRefresh,
		type RealtimeRefreshController,
	} from "$lib/utils/realtime";
	import OpsHeaderStrip from "$lib/components/Panel de Control/OpsHeaderStrip.svelte";
	import SystemPulsePanel from "$lib/components/Panel de Control/SystemPulsePanel.svelte";
	import DataIntegrityPanel from "$lib/components/Panel de Control/DataIntegrityPanel.svelte";
	import AlertsFeed from "$lib/components/Panel de Control/AlertsFeed.svelte";
	import SchedulerWatchPanel from "$lib/components/Panel de Control/SchedulerWatchPanel.svelte";
	import PaperSessionSummary from "$lib/components/Panel de Control/PaperSessionSummary.svelte";
	import PipelineFlowPanel from "$lib/components/Panel de Control/PipelineFlowPanel.svelte";
	import AgentHeartbeat from "$lib/components/Panel de Control/AgentHeartbeat.svelte";
	import ActivityStream from "$lib/components/Panel de Control/ActivityStream.svelte";
	import StrategyLeaderboard from "$lib/components/Panel de Control/StrategyLeaderboard.svelte";
	import EquityOverlay from "$lib/components/Panel de Control/EquityOverlay.svelte";
	import Skeleton from "$lib/components/Skeleton.svelte";
	import LiveTradingPanel from "$lib/components/Panel de Control/LiveTradingPanel.svelte";
	import CriticalAlertsBanner from "$lib/components/Panel de Control/CriticalAlertsBanner.svelte";
	import CrucibleResearchPanel from "$lib/components/Panel de Control/CrucibleResearchPanel.svelte";

	/** Loader data from +page.ts — provides initial Panel de Control payload. */
	export let data: {
		Reanudarn: Panel de ControlReanudarn | null;
		activity: Panel de ControlActivityItem[];
		winners: WinnerEntry[];
	};

	// Seed local state from loader data so the page renders on frame 1.
	let Reanudarn: Panel de ControlReanudarn | null = data.Reanudarn;
	let activity: Panel de ControlActivityItem[] = data.activity;
	let winners: WinnerEntry[] = data.winners;

	let loadingError = "";
	let loading = !data.Reanudarn;
	let primaryRealtime: RealtimeRefreshController | null = null;
	let primaryLoadingInFlight = false;
	let primaryPanel de ControlLoaded = !!data.Reanudarn;
	const Panel de Control_TIMEOUT_MS = 8_000;

	// Persisted activity-stream expand/collapse (full firehose; alerts have
	// their own always-visible feed).
	const ACTIVITY_KEY = "Panel de Control.activityStream.expanded";
	let activityExpanded = false;

	function toggleActivity() {
		activityExpanded = !activityExpanded;
		try {
			localStorage.setItem(ACTIVITY_KEY, String(activityExpanded));
		} catch {
			// localStorage may be unavailable (private mode / SSR harness); igNore.
		}
	}

	function withTimeout<T>(
		promise: Promise<T>,
		label: string,
		timeoutMs = Panel de Control_TIMEOUT_MS,
	): Promise<T> {
		return new Promise<T>((resolve, reject) => {
			const timer = setTimeout(
				() => reject(new Error(`${label} timed out`)),
				timeoutMs,
			);
			promise.then(
				(value) => {
					clearTimeout(timer);
					resolve(value);
				},
				(err) => {
					clearTimeout(timer);
					reject(err);
				},
			);
		});
	}

	async function loadPanel de Control() {
		if (primaryLoadingInFlight) return;
		primaryLoadingInFlight = true;

		try {
			const results = await Promise.allSettled([
				withTimeout(getPanel de ControlReanudarn(), "Reanudarn"),
				withTimeout(getPanel de ControlActivity(40), "activity"),
				withTimeout(getPanel de ControlWinners(10), "winners"),
			]);
			const [ReanudarnResult, activityResult, winnersResult] = results;

			if (ReanudarnResult.status === "fulfilled") {
				Reanudarn = ReanudarnResult.value;
				loadingError = "";
			}
			if (activityResult.status === "fulfilled")
				activity = activityResult.value;
			if (winnersResult.status === "fulfilled")
				winners = winnersResult.value;

			// An always-on Panel de Control must Not die on a transient miss: keep the
			// last good data on screen and only surface an error when we have
			// Nothing at all to show. The ops header independently shows
			// backend reachability, so a stale-but-rendered Panel de Control is
			// visibly distinguishable from a healthy one.
			const allFailed = results.every((entry) => entry.status === "rejected");
			if (allFailed && !Reanudarn) {
		loadingError = $backendConectado
				? "Los datos del panel No están disponibles temporalmente. Reintentando en segundo plaNo."
				: "La conexión con el backend aún se está inicializando. El panel se reintentará automáticamente.";
			}

			loading = false;
			primaryPanel de ControlLoaded = true;
		} finally {
			primaryLoadingInFlight = false;
		}
	}

	function startPrimaryRealtime() {
		if (primaryRealtime) return;
		primaryRealtime = createRealtimeRefresh(loadPanel de Control, {
			fallbackMs: 30_000,
			wsDebounceMs: 5000,
			wsEvents: [
				"strategy_promoted",
				"kill_switch_activated",
				"kill_switch_cleared",
				"agent_stalled",
			],
			pollWhenWsOfflineOnly: false,
		});
		primaryRealtime.start();
	}

	function stopPrimaryRealtime() {
		primaryRealtime?.stop();
		primaryRealtime = null;
	}

	onMount(() => {
		try {
			activityExpanded = localStorage.getItem(ACTIVITY_KEY) === "true";
		} catch {
			activityExpanded = false;
		}

		if (!primaryPanel de ControlLoaded) {
			loading = true;
			void loadPanel de Control();
		}
		startPrimaryRealtime();
	});

	onDestroy(() => {
		stopPrimaryRealtime();
	});
</script>

<svelte:head>
	<title>Panel de Control | Forven</title>
	<meta
		Nombre="description"
		content="Panel de operaciones siempre activo: salud del sistema, integridad de datos, flujo de Pipeline, trading en papel y alertas."
	/>
</svelte:head>

<div
	class="relative h-full min-h-0 flex flex-col overflow-hidden p-2 gap-1.5 bg-[#050505]"
>
	<CriticalAlertsBanner />

	<OpsHeaderStrip autopilot={Reanudarn?.autopilot ?? null} kpis={Reanudarn?.kpis ?? null} />

	{#if loading && !Reanudarn}
		<div class="min-h-[220px] grid grid-cols-[1fr_1fr_1fr] gap-2">
			<div class="border border-[#222] p-4 bg-[#0a0a0a]"><Skeleton rows={6} /></div>
			<div class="border border-[#222] p-4 bg-[#0a0a0a]"><Skeleton rows={6} /></div>
			<div class="border border-[#222] p-4 bg-[#0a0a0a]"><Skeleton rows={6} /></div>
		</div>
		<div class="min-h-[240px] grid grid-cols-2 gap-2">
			<div class="border border-[#222] p-4 bg-[#0a0a0a]"><Skeleton rows={8} /></div>
			<div class="border border-[#222] p-4 bg-[#0a0a0a]"><Skeleton rows={8} /></div>
		</div>
	{:else}
		<div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden">
			<div class="space-y-1.5 pb-1.5">
				<!-- Monitor row: is the machine alive, is the data trustworthy, what needs attention -->
				<div class="grid grid-cols-1 gap-1.5 lg:h-[330px] lg:grid-cols-3">
					<div class="flex min-h-0 flex-col gap-1.5">
						<div class="min-h-0 flex-1"><SystemPulsePanel /></div>
						<div class="min-h-0 flex-1"><DataIntegrityPanel /></div>
					</div>
					<div class="h-[240px] min-h-0 lg:h-auto"><AlertsFeed /></div>
					<div class="h-[240px] min-h-0 lg:h-auto"><SchedulerWatchPanel /></div>
				</div>

				<!-- Trading row: what is the money doing right Now -->
				<div class="flex-shrink-0 space-y-1.5">
					<LiveTradingPanel />
				</div>
				<div class="flex-shrink-0">
					<PaperSessionSummary />
				</div>

				<!-- Agent activity + Pipeline flow, Lado by Lado -->
				<div class="flex-shrink-0 grid grid-cols-1 gap-1.5 lg:grid-cols-2 lg:h-[260px]">
					<div class="h-[240px] min-h-0 lg:h-auto"><AgentHeartbeat /></div>
					<div class="h-[240px] min-h-0 lg:h-auto"><PipelineFlowPanel /></div>
				</div>

				<!-- Research: active crucibles + recent verdicts -->
				<div class="flex-shrink-0 h-[180px]">
					<CrucibleResearchPanel />
				</div>

				<div
					class="flex-shrink-0 min-h-[180px] overflow-hidden border border-[#222] rounded bg-[#0a0a0a] p-1.5"
				>
					<EquityOverlay />
				</div>

				<div class="flex-shrink-0 h-[230px]">
					<StrategyLeaderboard {winners} />
				</div>

				<!-- Full activity firehose (alerts have their own panel above) -->
				<div class="flex-shrink-0 border border-[#222] rounded bg-[#0a0a0a]">
					<button
						type="button"
						class="w-full text-left px-3 py-1.5 text-[10px] uppercase tracking-wider text-gray-500 hover:text-gray-300"
						on:click={toggleActivity}
						aria-expanded={activityExpanded}
						aria-controls="activity-stream-panel"
						data-testid="activity-stream-toggle"
					>
						Flujo de Actividad {activityExpanded ? "▾" : "▸"}
					</button>
					{#if activityExpanded}
						<div id="activity-stream-panel" class="max-h-[280px] overflow-auto">
							<ActivityStream items={activity} />
						</div>
					{/if}
				</div>
			</div>
		</div>
	{/if}

	{#if loadingError}
		<div
			class="flex-shrink-0 border border-red-900 bg-red-900/20 rounded px-3 py-2 text-xs text-red-300"
		>
			{loadingError}
		</div>
	{/if}
</div>
