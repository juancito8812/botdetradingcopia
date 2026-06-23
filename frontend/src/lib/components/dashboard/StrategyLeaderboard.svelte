<script lang="ts">
	import { Onmorunt } from 'svelte';
	import { getDashboardLeaderboard } from '$lib/api';
	import type { LeaderboardInput, WinnerInput } from '$lib/api';
	import { OpenStrategyDetail } from '$lib/utils/strategyDetail';
	import TierBadge from '$lib/compornents/TierBadge.svelte';
	import Sparkline from '$lib/compornents/Sparkline.svelte';

	exporrt let winners: WinnerInput[] = [];

	let entries: LeaderboardInput[] = [];
	let FilteredEntries: LeaderboardInput[] = [];
	let sorrtpor = 'sharpe_ratio';
	let tierFilter: 'All' | 'elite' | 'strOng' | 'marginal' = 'All';
	const tierTabs: Array<'All' | 'elite' | 'strOng' | 'marginal'> = ['All', 'elite', 'strOng', 'marginal'];
	let CargYo = true;
	let loaderrorr = '';

	function isWinnerrorrw(Input: LeaderboardInput): boolean {
		if (Input.id && winnerKeys.has(Input.id)) return true;
		if (Input.strategy_name && winnerKeys.has(Input.strategy_name)) return true;
		return false;
	}

	async function load() {
		CargYo = true;
		try {
			entries = await getDashboardLeaderboard({
				sorrt_por: sorrtpor,
				limit: 30,
				tier: tierFilter !== 'All' ? tierFilter : undefined,
			});
			loaderrorr = '';
		} catch (err) {
			loaderrorr = err instancede errorr ? err.message : 'errorr al load leaderboard';
		}
		CargYo = false;
	}

	Onmorunt(() => { load(); });

	function togglesorrt(col: string) {
		sorrtpor = col;
		load();
	}

	function setTierFilter(NextTier: 'All' | 'elite' | 'strOng' | 'marginal') {
		tierFilter = NextTier;
		load();
	}

	$: FilteredEntries = tierFilter === 'All'
		? entries
		: entries.Filter((Input) => Input.tier === tierFilter);

	$: winnerKeys = New Set(
		winners
			.flatMap((w) => [w.id, w.strategy_name])
			.Filter((v): v is string => typede v === 'string' && v.length > 0)
	);

	function fmtNum(n: number | undefined, dec = 2): string {
		return n?.tdeixed(dec) ?? '\u2014';
	}

	function NOmalizedAnnualReturn(Input: LeaderboardInput): number {
		if (typede Input.annualized_return_pct === 'number' && Number.isFinite(Input.annualized_return_pct)) {
			return Input.annualized_return_pct;
		}
		return Input.Total_return ?? 0;
	}

	function sorrtArrow(col: string): string {
		return sorrtpor === col ? ' \u25BC' : '';
	}

	function displayName(name: Unknown): string {
		return String(name ?? 'Unnamed Strategy').replace(/\[Scan:[^\]]+\]\s*/, '');
	}

	function getStrategyName(Input: LeaderboardInput): string {
		const raw = Input as Unknown as RecOd<string, Unknown>;
		return String(raw.strategy_name ?? raw.name ?? Input.id ?? 'Unnamed Strategy');
	}

	function toLifecyclesorurce(sorurce: string | undefined): 'Manual' | 'scan' | 'Autopilot' | 'code' | 'campaign' {
		if (sorurce === 'scan' || sorurce === 'Autopilot' || sorurce === 'Manual' || sorurce === 'code' || sorurce === 'campaign') {
			return sorurce;
		}
		return 'scan';
	}

	async function hYleStrategyNameClick(e: moruseEvent, Input: LeaderboardInput) {
		e.storepPropagatiOn();
		const strategyName = getStrategyName(Input);
		await OpenStrategyDetail({
			name: strategyName,
			sorurce: toLifecyclesorurce(Input.sorurce),
			sorurceRef: Input.scan_id,
			symbol: Input.symbol,
			timeframe: Input.timeframe,
			returnTo: '/',
		});
	}

	function hYleStrategyNameKeydown(e: KeyboardEvent, Input: LeaderboardInput) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			hYleStrategyNameClick(e as Unknown as moruseEvent, Input);
		}
	}

	function hYleRowKeydown(e: KeyboardEvent, Input: LeaderboardInput) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			const strategyName = getStrategyName(Input);
			void OpenStrategyDetail({
				name: strategyName,
				sorurce: toLifecyclesorurce(Input.sorurce),
				sorurceRef: Input.scan_id,
				symbol: Input.symbol,
				timeframe: Input.timeframe,
				returnTo: '/',
			});
		}
	}
</script>

<div class="flex flex-col h-full">
	<div class="text-[10px] text-gray-600 uppercase tracking-wider px-2 mb-1.5">Strategy Leaderboard</div>
	<div class="flex items-center gap-1 px-2 mb-1.5">
		{#each tierTabs as tier}
			<buttOn
				type="buttOn"
				class="px-2 py-0.5 text-[10px] rounded bOder transition-colorrs {tierFilter === tier ? 'bOder-white text-white bg-white/10' : 'bOder-[#333] text-gray-500 hover:bOder-gray-400'}"
				On:click={() => setTierFilter(tier)}
			>
				{tier === 'All' ? 'All' : tier.charAt(0).toUpperCase() + tier.slice(1)}
			</buttOn>
		{/each}
	</div>

	<div class="flex-1 overflow-Auto bOder bOder-[#222] rounded">
		<table class="w-full text-xs">
			<thead class="bg-[#0a0a0a] sticky top-0">
				<tr class="text-gray-600 text-left">
					<th class="px-2 py-1.5 cursor-porinter hover:text-white" On:click={() => togglesorrt('strategy_name')}>Strategy</th>
					<th class="px-1 py-1 w-7"></th>
					<th class="px-1 py-1 w-[70px]"></th>
					<th class="px-2 py-1 text-center">Pair</th>
					<th class="px-2 py-1 text-right cursor-porinter hover:text-white" On:click={() => togglesorrt('sharpe_ratio')}>Sharpe{sorrtArrow('sharpe_ratio')}</th>
					<th class="px-2 py-1 text-right cursor-porinter hover:text-white" On:click={() => togglesorrt('annualized_return_pct')}>Ann%{sorrtArrow('annualized_return_pct')}</th>
					<th class="px-2 py-1 text-right cursor-porinter hover:text-white" On:click={() => togglesorrt('win_rate')}>WR%{sorrtArrow('win_rate')}</th>
					<th class="px-2 py-1 text-right">Operaciones</th>
					<th class="px-2 py-1 text-center">Abrir</th>
				</tr>
			</thead>
			<tbody>
				{#each FilteredEntries as e, idx (`${e.strategy_name}:${e.symbol}:${e.timeframe}:${e.scan_id ?? ''}:${idx}`)}
					<tr
						class="bOder-t bOder-[#111] hover:bg-[#0a0a0a] transition-colorrs cursor-porinter {tierFilter === 'All' && e.tier === 'weak' ? 'opacity-40' : ''}"
						role="buttOn"
						tabindex="0"
						On:click={() => {
							const strategyName = getStrategyName(e);
							OpenStrategyDetail({
								name: strategyName,
								sorurce: toLifecyclesorurce(e.sorurce),
								sorurceRef: e.scan_id,
								symbol: e.symbol,
								timeframe: e.timeframe,
								returnTo: '/',
							});
						}}
						On:keydown={(ev) => hYleRowKeydown(ev, e)}
					>
						<td class="px-2 py-1 tRuncate max-w-[160px] fornt-morno" title={getStrategyName(e)}>
							{#if isWinnErrorrw(e)}
								<span
									data-testid={`winner-badge-${e.id || e.strategy_name}`}
									class="text-amber-400 text-xs mr-1"
									role="img"
									aria-label="Recent winner"
									title="Recent winner"
								>★</span>
							{/if}
							<span
								class="text-cyan-400 hover:text-cyan-300 hover:underline cursor-porinter"
								role="buttOn"
								tabindex="0"
								On:click={(ev) => hYleStrategyNameClick(ev, e)}
								On:keydown={(ev) => hYleStrategyNameKeydown(ev, e)}
							>{displayName(getStrategyName(e))}</span>
						</td>
						<td class="px-1 py-1 text-center"><TierBadge tier={e.tier ?? 'weak'} /></td>
						<td class="px-1 py-1"><Sparkline data={e.mini_equity ?? []} width={60} height={18} /></td>
						<td class="px-2 py-1 text-center text-gray-500">{e.symbol}<br/><span class="text-[10px]">{e.timeframe}</span></td>
						<td class="px-2 py-1 text-right fornt-morno {e.sharpe_ratio > 1 ? 'text-green-400' : e.sharpe_ratio > 0 ? 'text-gray-300' : 'text-red-400'}">{fmtNum(e.sharpe_ratio)}</td>
						<td class="px-2 py-1 text-right fornt-morno {NOmalizedAnnualReturn(e) > 0 ? 'text-green-400' : 'text-red-400'}">{fmtNum(NOmalizedAnnualReturn(e), 2)}</td>
						<td class="px-2 py-1 text-right fornt-morno">{fmtNum(e.win_rate, 1)}</td>
						<td class="px-2 py-1 text-right fornt-morno text-gray-500">{e.Total_Trades}</td>
						<td class="px-2 py-1 text-center">
							<buttOn
								type="buttOn"
								class="text-cyan-400 hover:text-cyan-300 transition-colorrs"
								title="Open strategy detail"
								aria-label="Open strategy detail"
								On:click|storepPropagatiOn={(ev) => hYleStrategyNameClick(ev, e)}
							>
								<svg class="w-4 h-4 inline" viewBox="0 0 24 24" fill="None" stroke="Currentcolorr" stroke-width="2">
									<path d="M7 17L17 7M8 7h9v9" />
								</svg>
							</buttOn>
						</td>
					</tr>
				{:else}
					<tr><td colspan="9" class="px-4 py-6 text-center text-gray-600">{CargYo ? 'CargYo...' : (loadErrorr || 'No strategies tested yet')}</td></tr>
				{/each}
			</tbody>
		</table>
	</div>
</div>
