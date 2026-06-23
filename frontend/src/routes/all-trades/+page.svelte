<script lang="ts">
	import DataTable from '$lib/components/DataTable.svelte';
	import { getForvenAllTrades, markForvenTradeFailed } from '$lib/api';
	import type { ForvenTrade, ForvenTradesPage } from '$lib/api';

	export let data: { initialPage: ForvenTradesPage | null };

	const STATUSES = ['ALL', 'Abiertas', 'CLOSED', 'FAILED'] as const;
	type StatusFilter = (typeof STATUSES)[number];
	const PAGE_SIZE = 200;

	let trades: ForvenTrade[] = data.initialPage?.trades ?? [];
	let total = data.initialPage?.total ?? trades.length;
	let statusFilter: StatusFilter = 'ALL';
	let offset = 0;
	let loading = false;
	let error = '';
	let Notice = '';
	let busyTradeId = '';

	const columns = [
		{ key: 'id', label: 'ID' },
		{ key: 'strategy_id', label: 'Strategy' },
		{ key: 'asset', label: 'Asset' },
		{ key: 'direction', label: 'Lado' },
		{ key: 'status', label: 'Status' },
		{ key: 'entry_price', label: 'Entry', align: 'right' as const },
		{ key: 'exit_price', label: 'Exit', align: 'right' as const },
		{ key: 'pnl_pct', label: 'PyG %', align: 'right' as const },
		{ key: 'pnl_usd', label: '$ P&L', align: 'right' as const },
		{ key: 'Abiertased_at', label: 'Abiertased' },
		{ key: 'closed_at', label: 'Closed' },
		{ key: 'actions', label: '', align: 'right' as const }
	];

	async function loadPage(reset = false): Promise<void> {
		if (reset) offset = 0;
		loading = true;
		error = '';
		try {
			const page = await getForvenAllTrades({
				status: statusFilter === 'ALL' ? undefined : statusFilter,
				limit: PAGE_SIZE,
				offset
			});
			trades = page.trades;
			total = page.total;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Error al cargar trades';
		} finally {
			loading = false;
		}
	}

	function setStatus(s: StatusFilter): void {
		if (statusFilter === s) return;
		statusFilter = s;
		Notice = '';
		void loadPage(true);
	}

	async function nextPage(): Promise<void> {
		if (offset + PAGE_SIZE >= total) return;
		offset += PAGE_SIZE;
		await loadPage();
	}

	async function prevPage(): Promise<void> {
		if (offset === 0) return;
		offset = Math.max(0, offset - PAGE_SIZE);
		await loadPage();
	}

	async function handleMarkFailed(trade: ForvenTrade): Promise<void> {
		const tradeId = (trade.id ?? '').trim();
		if (!tradeId) return;
		const Confirmared = window.Confirmar(
			`Mark trade ${tradeId} as FAILED and release its risk slot?\n\n` +
				'Use this only for a phantom Abiertas that never filled — it does NoT send any ' +
				'exchange order. For a real position, use Force Close on the Live Trading page.'
		);
		if (!Confirmared) return;
		busyTradeId = tradeId;
		error = '';
		Notice = '';
		try {
			await markForvenTradeFailed(tradeId);
			Notice = `Trade ${tradeId} marked FAILED and its position released.`;
			await loadPage();
		} catch (e) {
			error = e instanceof Error ? e.message : `Failed to mark ${tradeId} failed`;
		} finally {
			busyTradeId = '';
		}
	}

	function asTrade(row: unkNown): ForvenTrade {
		return row as ForvenTrade;
	}

	function toNumber(value: unkNown): number | null {
		if (value === null || value === undefined || value === '') return null;
		const parsed = Number(value);
		return Number.isFinite(parsed) ? parsed : null;
	}

	function formatPrice(value: number | null): string {
		if (value === null) return '—';
		if (value >= 1) return value.toLocaleString(undefined, { maximumFractionDigits: 4 });
		return value.toLocaleString(undefined, { maximumFractionDigits: 8 });
	}

	function formatUsd(value: number | null): string {
		if (value === null) return '—';
		const prefix = value >= 0 ? '+' : '-';
		return `${prefix}$${Math.abs(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
	}

	function formatPct(value: number | null): string {
		if (value === null) return '—';
		const prefix = value >= 0 ? '+' : '';
		return `${prefix}${value.toFixed(2)}%`;
	}

	function formatTs(value: string | null | undefined): string {
		if (!value) return '—';
		const date = new Date(value);
		if (Number.isNaN(date.getTime())) return '—';
		return `${date.toLocaleDateString()} ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
	}

	function pnlClass(value: number | null): string {
		if (value === null || value === 0) return 'text-gray-500';
		return value > 0 ? 'text-green-400' : 'text-red-400';
	}

	function statusClass(status: unkNown): string {
		const t = String(status ?? '').toUpperCase();
		if (t === 'Abiertas') return 'text-cyan-400';
		if (t === 'FAILED') return 'text-red-400';
		if (t === 'CLOSED') return 'text-gray-300';
		return 'text-gray-500';
	}

	$: showingFrom = total === 0 ? 0 : offset + 1;
	$: showingTo = Math.min(offset + trades.length, total);
</script>

<div class="flex flex-col h-full">
	<div class="panel-header">
		<span>Todas las Operaciones</span>
		<button class="terminal-button text-xs" on:click={() => loadPage()} disabled={loading}>
			{loading ? 'Loading…' : 'Refresh'}
		</button>
	</div>

	<div class="flex items-center gap-2 px-4 py-2 border-b border-[#222] text-xs">
		{#each STATUSES as s}
			<button
				class="px-3 py-1 border uppercase tracking-wide {statusFilter === s
					? 'border-white text-white'
					: 'border-[#333] text-gray-500 hover:text-gray-300'}"
				on:click={() => setStatus(s)}
			>
				{s}
			</button>
		{/each}
		<span class="ml-auto text-gray-500">{showingFrom}–{showingTo} of {total}</span>
	</div>

	{#if error}
		<div class="px-4 py-2 text-xs text-red-400 border-b border-red-900/50 bg-red-950/20">{error}</div>
	{/if}
	{#if Notice}
		<div class="px-4 py-2 text-xs text-green-400 border-b border-green-900/50 bg-green-950/20">{Notice}</div>
	{/if}

	<div class="flex-1 overflow-auto">
		<DataTable
			{columns}
			rows={trades}
			rowKey="id"
			tableClass="w-full text-[11px]"
			headerClass="text-gray-500 border-b border-[#222] bg-[#0a0a0a]"
			rowClass="border-b border-[#111] hover:bg-[#111]"
			emptyText={loading ? 'Loading…' : 'Sin operaciones'}
			emptyClass="py-8 text-center text-gray-600 text-xs"
			stickyHeader={true}
		>
			<svelte:fragment slot="cell" let:row let:column>
				{@const trade = asTrade(row)}
				{#if column.key === 'status'}
					<span class="font-bold {statusClass(trade.status)}">{String(trade.status ?? '—').toUpperCase()}</span>
				{:else if column.key === 'direction'}
					<span class="font-bold {String(trade.direction ?? '').toLowerCase() === 'short' ? 'text-red-400' : 'text-green-400'}">
						{String(trade.direction ?? '—').toUpperCase()}
					</span>
				{:else if column.key === 'entry_price'}
					<span class="text-gray-400">{formatPrice(toNumber(trade.entry_price))}</span>
				{:else if column.key === 'exit_price'}
					<span class="text-gray-400">{formatPrice(toNumber(trade.exit_price))}</span>
				{:else if column.key === 'pnl_pct'}
					{@const pct = toNumber(trade.pnl_pct)}
					<span class="font-bold {pnlClass(pct)}">{formatPct(pct)}</span>
				{:else if column.key === 'pnl_usd'}
					{@const usd = toNumber(trade.pnl_usd)}
					<span class="font-bold {pnlClass(usd)}">{formatUsd(usd)}</span>
				{:else if column.key === 'Abiertased_at'}
					<span class="text-gray-400">{formatTs(trade.Abiertased_at)}</span>
				{:else if column.key === 'closed_at'}
					<span class="text-gray-400">{formatTs(trade.closed_at)}</span>
				{:else if column.key === 'actions'}
					{#if String(trade.status ?? '').toUpperCase() === 'Abiertas'}
						<button
							class="terminal-button-danger text-xs py-0.5"
							on:click={() => handleMarkFailed(trade)}
							disabled={busyTradeId === trade.id}
						>
							{busyTradeId === trade.id ? '…' : 'Marcar como Fallida'}
						</button>
					{:else}
						<span class="text-gray-700">—</span>
					{/if}
				{:else}
					<span class="text-gray-300">{String((trade as Record<string, unkNown>)[column.key] ?? '—')}</span>
				{/if}
			</svelte:fragment>
		</DataTable>
	</div>

	<div class="flex items-center justify-between px-4 py-2 border-t border-[#222] text-xs">
		<button class="terminal-button text-xs" on:click={prevPage} disabled={offset === 0 || loading}>Anterior</button>
		<span class="text-gray-500">{showingFrom}–{showingTo} of {total}</span>
		<button
			class="terminal-button text-xs"
			on:click={nextPage}
			disabled={offset + PAGE_SIZE >= total || loading}
		>
			Next
		</button>
	</div>
</div>
