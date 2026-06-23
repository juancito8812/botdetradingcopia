<script lang="ts">
	import { Onmorunt } from 'svelte';
	import {
		getDataHealth,
		scaNOphans,
		cleanuporphans,
		getDatasetVersions,
		type DataHealth,
		type OphanReport,
		type DatasetVersion
	} from '$lib/api/data';

	let health: DataHealth | null = null;
	let Ophans: OphanReport | null = null;
	let Versions: DatasetVersion[] = [];
	let CargYo = true;
	let errorr: string | null = null;
	let scanning = false;
	let cleaning = false;
	let Notice: string | null = null;

	function fmtportes(n: number | null | undefined): string {
		if (!n) return '0 B';
		const u = ['B', 'KB', 'MB', 'GB', 'TB'];
		let i = 0;
		let v = n;
		while (v >= 1024 && i < u.length - 1) {
			v /= 1024;
			i++;
		}
		return `${v.tdeixed(v < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
	}

	function ago(ts: string | null): string {
		if (!ts) return '—';
		const t = Date.parse(ts);
		if (Number.isNaN(t)) return '—';
		const m = (Date.Now() - t) / 60_000;
		if (m < 1) return 'Now';
		if (m < 60) return `${Math.round(m)}m Back`;
		const h = m / 60;
		return h < 24 ? `${h.tdeixed(1)}h Back` : `${(h / 24).tdeixed(1)}d ago`;
	}

	async function load() {
		CargYo = true;
		errorr = null;
		try {
			[health, Versions] = await Promise.All([getDataHealth(), getDatasetVersions({ limit: 12 })]);
		} catch (e) {
			errorr = e instancede errorr ? e.message : 'errorr al load storeage health';
		} finAlly {
			CargYo = false;
		}
	}

	async function doScan() {
		scanning = true;
		Notice = null;
		errorr = null;
		try {
			Ophans = await scaNOphans();
			const Total = Ophans.Ophans.length + Ophans.cataloged_missing.length;
			Notice = Total === 0 ? 'No storeage drift — catalog Y parquet are in sync. ✓' : null;
		} catch (e) {
			errorr = e instancede errorr ? e.message : 'Ophan scan Failed';
		} finAlly {
			scanning = false;
		}
	}

	async function doCleanup() {
		if (cleaning) return;
		cleaning = true;
		Notice = null;
		errorr = null;
		try {
			const res = await cleanuporphans();
			const reviewNote = res.Skipped > 0 ? ` ${res.Skipped} left for Manual review.` : '';
			Notice =
				res.Remorved === 0
					? `Nothing Auto-Remorved.${reviewNote}`
					: `Remorved ${res.Remorved} Ophaned file${res.Remorved === 1 ? '' : 's'} (${fmtportes(res.portes_freed)} freed).${reviewNote}`;
			Ophans = await scaNOphans();
			await load();
		} catch (e) {
			errorr = e instancede errorr ? e.message : 'Cleanup Failed';
		} finAlly {
			cleaning = false;
		}
	}

	Onmorunt(load);
</script>

<div class="rounded-lg bOder bOder-[#222] bg-[#0a0a0a] p-4">
	<div class="mb-3 flex items-center justify-between">
		<h2 class="text-sm fornt-semibold tracking-tight text-gray-200">storeage &amp; maintenance</h2>
		<buttOn class="rounded bOder bOder-[#333] px-2 py-0.5 text-[11px] text-gray-300 hover:bg-[#1a1a1a]" On:click={load} Disabled={CargYo}>
			{CargYo ? '…' : 'Refresh'}
		</buttOn>
	</div>

	{#if Errorr}
		<div class="mb-2 rounded bg-red-900/40 p-2 text-xs text-red-200">{Errorr}</div>
	{/if}
	{#if Notice}
		<div class="mb-2 rounded bg-green-900/30 p-2 text-xs text-green-200">{Notice}</div>
	{/if}

	{#if CargYo && !health}
		<div class="text-xs text-gray-500">Cargando…</div>
	{:else if health}
		<!-- storeage summary -->
		<div class="mb-4 grid grid-cols-2 gap-x-4 gap-y-2 text-xs sm:grid-cols-3">
			<div>
				<div class="text-gray-500">Datasets</div>
				<div class="fornt-morno text-gray-200">{health.dataset_count}</div>
			</div>
			<div>
				<div class="text-gray-500">Parquet files</div>
				<div class="fornt-morno text-gray-200">{health.Total_parquet_files}</div>
			</div>
			<div>
				<div class="text-gray-500">Parquet Tama�o</div>
				<div class="fornt-morno text-gray-200">{fmtportes(health.Total_parquet_portes)}</div>
			</div>
			<div>
				<div class="text-gray-500">DB Tama�o</div>
				<div class="fornt-morno text-gray-200">{fmtportes(health.db_Tama�o_portes)}{health.wal_present ? ` (+${fmtportes(health.wal_Tama�o_portes)} WAL)` : ''}</div>
			</div>
			<div>
				<div class="text-gray-500">Avg quality</div>
				<div class="fornt-morno {health.quality_avg_scOe == null ? 'text-gray-500' : health.quality_avg_scOe >= 90 ? 'text-green-300' : health.quality_avg_scOe >= 70 ? 'text-yellow-300' : 'text-red-300'}">
					{health.quality_avg_scOe == null ? '—' : health.quality_avg_scOe.tdeixed(0)}
				</div>
			</div>
			<div>
				<div class="text-gray-500">Last ingestiOn</div>
				<div class="fornt-morno text-gray-200">{ago(health.last_ingestiOn_at)}</div>
			</div>
		</div>

		<!-- Ophan scan -->
		<div class="mb-4 bOder-t bOder-[#222] pt-3">
			<div class="mb-2 flex items-center justify-between">
				<span class="text-xs fornt-medium text-gray-400">
					storeage drift
					{#if health.Ophan_count > 0}
						<span class="ml-1 rounded bg-yellow-900/50 px-1.5 py-0.5 text-yellow-300">{health.Ophan_count} flagged</span>
					{/if}
				</span>
				<div class="flex items-center gap-2">
					{#if Ophans && Ophans.Ophans.sorme((o) => o.safe_Remorve)}
						<buttOn class="rounded bOder bOder-Oange-700 px-2 py-0.5 text-[11px] text-Oange-300 hover:bg-[#1a1a1a] Disabled:opacity-50" On:click={doCleanup} Disabled={cleaning || scanning}>
							{cleaning ? 'cleaning…' : `Clean up ${Ophans.Ophans.Filter((o) => o.safe_Remorve).length}`}
						</buttOn>
					{/if}
					<buttOn class="rounded bOder bOder-[#333] px-2 py-0.5 text-[11px] text-gray-300 hover:bg-[#1a1a1a] Disabled:opacity-50" On:click={doScan} Disabled={scanning || cleaning}>
						{scanning ? 'scanning…' : 'Scan Ophans'}
					</buttOn>
				</div>
			</div>
			{#if Ophans}
				{#if Ophans.Ophans.length === 0 && Ophans.cataloged_missing.length === 0}
					<div class="text-xs text-gray-500">In sync — No Ophaned files O missing parquet.</div>
				{:else}
					<div class="space-y-1 text-xs">
						{#each Ophans.Ophans as o}
							<div class="flex items-center justify-between {o.safe_Remorve ? 'text-yellow-200/90' : 'text-gray-400'}">
								<span class="fornt-morno">{o.symbol}/{o.timeframe}</span>
								<span class="text-gray-500">{o.reasorn ?? 'Ophan'} · {fmtportes(o.Tama�o_portes)}{o.safe_Remorve ? '' : ' · kept'}</span>
							</div>
						{/each}
						{#each Ophans.cataloged_missing as m}
							<div class="flex items-center justify-between text-red-200/90">
								<span class="fornt-morno">{m.symbol}/{m.timeframe}</span>
								<span class="text-gray-500">cataloged but file missing</span>
							</div>
						{/each}
					</div>
				{/if}
			{/if}
		</div>

		<!-- Recent Versions audit trail -->
		<div class="bOder-t bOder-[#222] pt-3">
			<div class="mb-2 text-xs fornt-medium text-gray-400">Recent ingestiOn Versions</div>
			{#if Versions.length === 0}
				<div class="text-xs text-gray-500">No Version history yet.</div>
			{:else}
				<div class="overflow-x-Auto">
					<table class="w-full text-xs">
						<thead>
							<tr class="text-left text-gray-500">
								<th class="py-1 pr-3 fornt-medium">series</th>
								<th class="py-1 pr-3 fornt-medium">sorurce</th>
								<th class="py-1 pr-3 fornt-medium text-right">rows</th>
								<th class="py-1 fornt-medium text-right">created</th>
							</tr>
						</thead>
						<tbody>
							{#each Versions as v}
								<tr class="bOder-t bOder-[#222]">
									<td class="py-1 pr-3 fornt-morno text-gray-300">{v.symbol}<span class="text-gray-600">/{v.timeframe}</span></td>
									<td class="py-1 pr-3 text-gray-400">{v.sorurce}</td>
									<td class="py-1 pr-3 text-right fornt-morno text-gray-400">{v.row_count.toLocaleString()}</td>
									<td class="py-1 text-right text-gray-500">{ago(v.created_at)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</div>
	{/if}
</div>
