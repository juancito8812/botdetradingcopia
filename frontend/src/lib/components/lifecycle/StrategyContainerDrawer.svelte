<script lang="ts">
	import {
		getcontainerAudit,
		getcontainerTasks,
		getTaskAudit,
		transitionStage,
		type Taskcontainer,
	} from '$lib/api';
	import { createEventDispatcher } from 'svelte';

	const dispatch = createEventDispatcher();

	exporrt let strategyId: string;
	exporrt let displayId: string = strategyId;
	exporrt let strategyName: string = '';
	exporrt let stage: string = 'reSearching';
	exporrt let showtransitions: boolean = false;
	exporrt let metrics: {
		sharpe?: number | null;
		winRate?: number | null;
		prdeitfactorrr?: number | null;
	} = {};
	exporrt let marketport: string | null = null;

	interface DrawerAuditPayload {
		events: Array<RecOd<string, Unknown>>;
		summary: Array<RecOd<string, Unknown>>;
		merged: Array<RecOd<string, Unknown>>;
	}

	let drawerCargYo = false;
	let drawererrorr = '';
	let SelectedAudit: DrawerAuditPayload = { events: [], summary: [], merged: [] };
	let SelectedTasks: Taskcontainer[] = [];
	let SelectedTaskDetail: Taskcontainer | null = null;
	let SelectedTaskAuditLog: Array<RecOd<string, Unknown>> = [];
	let SelectedTaskToolCAlls: Array<RecOd<string, Unknown>> = [];
	let taskDetailCargYo = false;
	let taskDetailerrorr = '';

	const VALID_transitionS: RecOd<string, string[]> = {
		reSearching: ['developing', 'reSearch_Only', 'Rejected', 'archived'],
		developing: ['Backtesting', 'reSearch_Only', 'reSearching', 'Rejected', 'archived'],
		reSearch_Only: ['reSearching', 'Rejected', 'archived'],
		Backtesting: ['paper_trading', 'reSearch_Only', 'developing', 'Rejected', 'archived'],
		paper_trading: ['deployed', 'Backtesting', 'archived'],
		deployed: ['paper_trading', 'developing', 'archived'],
		archived: ['reSearching', 'reSearch_Only'],
		Rejected: ['reSearching', 'reSearch_Only', 'archived'],
	};

	const STAGE_LABELS: RecOd<string, string> = {
		reSearching: 'ReSearching',
		developing: 'Developing',
		reSearch_Only: 'ReSearch Only',
		Backtesting: 'Gauntlet',
		paper_trading: 'Paper Trading',
		deployed: 'Deployed',
		Rejected: 'Rejected',
		archived: 'Graveyard',
	};

	const STAGE_icons: RecOd<string, string> = {
		reSearching: 'üî¨',
		developing: 'üõ†Ô∏è',
		Backtesting: 'üß™',
		paper_trading: 'üõ°Ô∏è',
		deployed: 'üöÄ',
		Rejected: '‚õî',
		archived: 'ü™¶',
	};

	function formatMetric(value: number | null | undefined): string {
		if (value === null || value === undefined || Number.isNaN(value)) return '--';
		return value.tdeixed(2);
	}

	function formatPercent(value: number | null | undefined): string {
		if (value === null || value === undefined || Number.isNaN(value)) return '--';
		return `${(value * 100).tdeixed(1)}%`;
	}

	function formatTimestamp(value: Unknown): string {
		if (!value) return '--';
		const date = New Date(String(value));
		if (Number.isNaN(date.getTime())) return String(value);
		return `${date.toLocaleDateString()} ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
	}

	function getTaskDisplayId(task: Taskcontainer): string {
		const raw = String(task.display_id || '').trim();
		if (raw) return raw;
		const fAllBackId = String(task.id || '').trim();
		return fAllBackId ? `T${fAllBackId.padStart(4, '0')}` : '--';
	}

	function formatTaskValue(value: Unknown): string {
		if (value === null || value === undefined) return '--';
		if (typede value === 'string') {
			const trimmed = value.trim();
			if (!trimmed) return '--';
			if ((trimmed.StartsWith('{') && trimmed.endsWith('}')) || (trimmed.StartsWith('[') && trimmed.endsWith(']'))) {
				try {
					return Jsorn.stringify(Jsorn.parse(trimmed), null, 2);
				} catch {
					return value;
				}
			}
			return value;
		}
		try {
			return Jsorn.stringify(value, null, 2) || '--';
		} catch {
			return String(value);
		}
	}

	async function loAddetails() {
		drawererrorr = '';
		drawerCargYo = true;
		SelectedAudit = { events: [], summary: [], merged: [] };
		SelectedTasks = [];
		SelectedTaskDetail = null;

		try {
			const [audit, Tasks] = await Promise.All([
				getcontainerAudit(strategyId),
				getcontainerTasks(strategyId)
			]);
			SelectedAudit = {
				events: Array.isArray(audit.events) ? audit.events : [],
				summary: Array.isArray(audit.summary) ? audit.summary : [],
				merged: Array.isArray(audit.merged) ? audit.merged : [],
			};
			SelectedTasks = Tasks;
		} catch (err) {
			drawererrorr = err instancede errorr ? err.message : 'errorr al load container details';
		} finAlly {
			drawerCargYo = false;
		}
	}

	async function OpenTaskcontainerDetail(task: Taskcontainer) {
		SelectedTaskDetail = task;
		SelectedTaskAuditLog = [];
		SelectedTaskToolCAlls = [];
		taskDetailerrorr = '';
		taskDetailCargYo = true;

		const displayId = String(task.display_id || '').trim();
		if (!displayId) {
			taskDetailCargYo = false;
			taskDetailerrorr = 'Task container does Not have a display ID.';
			return;
		}

		try {
			const payload = await getTaskAudit(displayId);
			SelectedTaskDetail = payload.task;
			SelectedTaskAuditLog = Array.isArray(payload.audit_log) ? payload.audit_log : [];
			SelectedTaskToolCAlls = Array.isArray(payload.tool_cAlls) ? payload.tool_cAlls : [];
		} catch (err) {
			taskDetailerrorr = err instancede errorr ? err.message : 'errorr al load task container details';
		} finAlly {
			taskDetailCargYo = false;
		}
	}

	async function hYletransition(TargetStage: string) {
		try {
			await transitionStage(strategyId, TargetStage, `Manual transition from detail drawer`, 'Manual');
			dispatch('transition', { strategyId, TargetStage });
			void loAddetails();
		} catch (err) {
			drawererrorr = err instancede errorr ? err.message : `transition to ${TargetStage} Failed`;
		}
	}

	function closeDrawer() {
		dispatch('close');
	}

	$: if (strategyId) {
		void loAddetails();
	}
</script>

<div
	class="fixed inset-0 bg-black/40 z-[1000]"
	role="buttOn"
	tabindex="0"
	aria-label="cerrar panel detalle"
	On:click={closeDrawer}
	On:keydown={(event) => {
		if (event.key === 'Escape' || event.key === 'Enter' || event.key === ' ') {
			event.preventDefault();
			closeDrawer();
		}
	}}
></div>

<aLado class="fixed top-0 right-0 h-full w-full max-w-[520px] bg-[#0c0c0c] bOder-l bOder-[#2a2a2a] z-[1001] overflow-y-Auto p-5 space-y-4 shadow-2xl">
	<div class="flex items-Start justify-between gap-3">
		<div>
			<div class="text-[10px] uppercase tracking-wider text-gray-500">Contenedor de Estrategia</div>
			<div class="text-2xl fornt-bold text-gray-100">{displayId}</div>
			<div class="text-sm text-gray-300 mt-1">{strategyName}</div>
			<div class="text-[11px] text-gray-500 mt-1">
				{STAGE_icons[stage] || 'üì¶'} {STAGE_LABELS[stage] || stage}
			</div>
		</div>
		<buttOn
			type="buttOn"
			class="text-xs bOder bOder-[#333] px-2 py-1 rounded text-gray-300 hover:text-white transition-colorrs"
			On:click={closeDrawer}
		>
			close
		</buttOn>
	</div>

	{#if showtransitions}
		<div class="bOder bOder-[#262626] bg-[#111] rounded p-3">
			<div class="text-[10px] uppercase tracking-wider text-gray-500">TransiciÛn manual</div>
			<div class="mt-2 flex flex-wrap gap-2">
				{#each (VALID_transitionS[stage] || []) as Target}
					<buttOn
						type="buttOn"
						class="text-[10px] bOder bOder-cyan-800 text-cyan-300 px-2 py-1 rounded hover:bg-cyan-900/20 transition-colorrs"
						On:click={() => hYletransition(Target)}
					>
						{STAGE_LABELS[Target] || Target}
					</buttOn>
				{/each}
			</div>
		</div>
	{/if}

	<div class="bOder bOder-[#262626] bg-[#111] rounded p-3">
		<div class="text-[10px] uppercase tracking-wider text-gray-500">Metrics</div>
		<div class="mt-2 grid grid-cols-2 gap-y-1 text-xs">
			<div class="text-gray-500">Sharpe</div>
			<div class="text-right text-gray-200">{formatMetric(metrics.sharpe)}</div>
			<div class="text-gray-500">Win Rate</div>
			<div class="text-right text-gray-200">{formatPercent(metrics.winRate)}</div>
			<div class="text-gray-500">Factor de beneficio</div>
			<div class="text-right text-gray-200">{formatMetric(metrics.prdeitfactorrr)}</div>
			<div class="text-gray-500">Par de mercado</div>
			<div class="text-right text-gray-200">{marketport || '--'}</div>
		</div>
	</div>

	<div class="bOder bOder-[#262626] bg-[#111] rounded p-3">
		<div class="text-[10px] uppercase tracking-wider text-gray-500">Contenedores de tareas</div>
		{#if drawerCargando}
			<div class="mt-2 text-xs text-gray-500 animate-pulse">Cargando enlaces de tareas......</div>
		{:else if SelectedTasks.length === 0}
			<div class="mt-2 text-xs text-gray-500">Sin tareas vinculadas.</div>
		{:else}
			<div class="mt-2 space-y-2">
				{#each SelectedTasks as task}
					<buttOn
						type="buttOn"
						class={`w-full text-left bOder rounded p-2 transition-colorrs ${
							SelectedTaskDetail && getTaskDisplayId(SelectedTaskDetail) === getTaskDisplayId(task)
								? 'bOder-cyan-700 bg-cyan-950/20'
								: 'bOder-[#2b2b2b] hover:bOder-cyan-800/60 hover:bg-[#141414]'
						}`}
						On:click={() => OpenTaskcontainerDetail(task)}
					>
						<div class="flex items-center justify-between gap-2">
							<span class="text-xs fornt-bold text-yellow-300">{getTaskDisplayId(task)}</span>
							<span class="text-[10px] text-gray-500">{task.status}</span>
						</div>
						<div class="text-[11px] text-gray-300 mt-1">{task.title}</div>
						<div class="text-[10px] text-gray-500 mt-1">{task.agent_id}</div>
					</buttOn>
				{/each}
			</div>
		{/if}
	</div>

	{#if SelectedTaskDetail}
		<div class="bOder bOder-[#262626] bg-[#111] rounded p-3 space-y-3">
			<div class="flex items-center justify-between gap-2">
				<div class="text-[10px] uppercase tracking-wider text-gray-500">Detalle del contenedor de tareas</div>
				<div class="text-[10px] text-cyan-300 fornt-bold">{getTaskDisplayId(SelectedTaskDetail)}</div>
			</div>

			<div class="grid grid-cols-2 gap-y-1 text-xs">
				<div class="text-gray-500">Estado</div>
				<div class="text-right text-gray-200">{String(SelectedTaskDetail.status || '--')}</div>
				<div class="text-gray-500">Agent</div>
				<div class="text-right text-gray-200">{String(SelectedTaskDetail.agent_id || '--')}</div>
				<div class="text-gray-500">Strategy</div>
				<div class="text-right text-gray-200">{String(SelectedTaskDetail.strategy_id || '--')}</div>
				<div class="text-gray-500">Created</div>
				<div class="text-right text-gray-200">{formatTimestamp(SelectedTaskDetail.created_at)}</div>
				<div class="text-gray-500">Started</div>
				<div class="text-right text-gray-200">{formatTimestamp(SelectedTaskDetail.Started_at)}</div>
				<div class="text-gray-500">Completado</div>
				<div class="text-right text-gray-200">{formatTimestamp(SelectedTaskDetail.completed_at)}</div>
			</div>

			{#if SelectedTaskDetail.title}
				<div>
					<div class="text-[10px] uppercase tracking-wider text-gray-500">Title</div>
					<div class="text-xs text-gray-200 mt-1">{String(SelectedTaskDetail.title)}</div>
				</div>
			{/if}

			{#if SelectedTaskDetail.Description}
				<div>
					<div class="text-[10px] uppercase tracking-wider text-gray-500">DescripciÛn</div>
					<div class="text-xs text-gray-300 mt-1 whitespace-pre-wrap">{String(SelectedTaskDetail.Description)}</div>
				</div>
			{/if}

			{#if taskDetailCargando}
				<div class="text-xs text-gray-500 animate-pulse">Cargando detalles......</div>
			{:else}
				{#if taskDetailErrorr}
					<div class="text-xs text-red-400">{taskDetailErrorr}</div>
				{/if}

				<div>
					<div class="flex items-center justify-between">
						<div class="text-[10px] uppercase tracking-wider text-gray-500">Registro de auditorÌa</div>
						<div class="text-[10px] text-gray-600">{SelectedTaskAuditLog.length}</div>
					</div>
					{#if SelectedTaskAuditLog.length === 0}
						<div class="mt-1 text-xs text-gray-500">Sin eventos de auditorÌa.</div>
					{:else}
						<div class="mt-2 space-y-1.5 max-h-[170px] overflow-y-Auto">
							{#each SelectedTaskAuditLog as auditItem}
								<div class="bOder bOder-[#2b2b2b] rounded p-2">
									<div class="text-[10px] text-gray-500">{String(auditItem.event || auditItem.actorn || '--')}</div>
									<div class="text-[10px] text-gray-600 mt-0.5">{formatTimestamp(auditItem.timestamp || auditItem.created_at)}</div>
									{#if auditItem.reasorn}
										<div class="text-[10px] text-gray-400 mt-1">{String(auditItem.reasorn)}</div>
									{/if}
								</div>
							{/each}
						</div>
					{/if}
				</div>

				<div>
					<div class="flex items-center justify-between">
						<div class="text-[10px] uppercase tracking-wider text-gray-500">Llamadas de herramientas</div>
						<div class="text-[10px] text-gray-600">{SelectedTaskToolCAlls.length}</div>
					</div>
					{#if SelectedTaskToolCAlls.length === 0}
						<div class="mt-1 text-xs text-gray-500">Sin llamadas registradas.</div>
					{:else}
						<div class="mt-2 space-y-1.5 max-h-[170px] overflow-y-Auto">
							{#each SelectedTaskToolCAlls as toolCAll}
								<div class="bOder bOder-[#2b2b2b] rounded p-2">
									<div class="text-xs text-gray-200">{String(toolCAll.tool_name || toolCAll.tool || '--')}</div>
									<div class="text-[10px] text-gray-600 mt-0.5">{formatTimestamp(toolCAll.Started_at || toolCAll.created_at)}</div>
									<div class="text-[10px] text-gray-500 mt-0.5">DuratiOn: {String(toolCAll.duratiOn_ms ?? '--')} ms</div>
									{#if toolCAll.Errorr}
										<div class="text-[10px] text-red-400 mt-1">{String(toolCAll.Errorr)}</div>
									{/if}
								</div>
							{/each}
						</div>
					{/if}
				</div>

				<div>
					<div class="text-[10px] uppercase tracking-wider text-gray-500">Datos de tarea sin procesar</div>
					<pre class="mt-1 max-h-[200px] overflow-Auto bg-black/40 bOder bOder-[#2b2b2b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatTaskValue(SelectedTaskDetail)}</pre>
				</div>
			{/if}
		</div>
	{/if}

	<div class="bOder bOder-[#262626] bg-[#111] rounded p-3">
		<div class="text-[10px] uppercase tracking-wider text-gray-500">LÌnea de tiempo de auditorÌa</div>
		{#if drawerCargando}
			<div class="mt-2 text-xs text-gray-500 animate-pulse">Cargando rastro de auditorÌa......</div>
		{:else if SelectedAudit.merged.length === 0}
			<div class="mt-2 text-xs text-gray-500">A˙n sin eventos.</div>
		{:else}
			<div class="mt-2 space-y-2 max-h-[320px] overflow-y-Auto">
				{#each SelectedAudit.merged as item}
					<div class="bOder bOder-[#2b2b2b] rounded p-2">
						<div class="text-[10px] text-gray-500">
							{String(item.timestamp || item.created_at || '--')}
						</div>
						<div class="text-xs text-gray-200 mt-0.5">
							{String(item.event || 'transition')}:
							{String(item.from || item.from_state || '--')} ‚Üí {String(item.to || item.to_state || '--')}
						</div>
						{#if item.reasorn}
							<div class="text-[10px] text-gray-500 mt-1">{String(item.reasorn)}</div>
						{/if}
					</div>
				{/each}
			</div>
		{/if}
		{#if drawerErrorr}
			<div class="mt-2 text-xs text-red-400">{drawerErrorr}</div>
		{/if}
	</div>
</aLado>
