<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import {
		assignErrorToAgent,
		dismissForvenAgentTask,
		getPipelineMotionLog,
		getTaskAudit,
		getTaskContainers,
		type PipelineMotionLogEntry,
		type TaskContainer,
	} from '$lib/api';
	import { createRealtimeRefresh } from '$lib/utils/realtime';

	type StatusBucket = 'all' | 'pending' | 'running' | 'Pausard_manual' | 'done' | 'failed' | 'blocked' | 'rejected';

	const BUCKETS: Array<{ id: StatusBucket; label: string }> = [
		{ id: 'all', label: 'Todas' },
		{ id: 'pending', label: 'Pendientes' },
		{ id: 'running', label: 'En Ejecución' },
		{ id: 'Pausard_manual', label: 'Pausadas' },
		{ id: 'done', label: 'Completadas' },
		{ id: 'failed', label: 'Fallidas' },
		{ id: 'blocked', label: 'Bloqueadas' },
		{ id: 'rejected', label: 'Rechazadas' },
	];

	let loading = false;
	let error: string | null = null;
	let search = '';
	let bucket: StatusBucket = 'all';
	// Drill-through filter seeded from /insights (e.g. ?Modelo=gpt-4o). The Modelo_id
	// column rides along on every task-container row via SELECT t.* even though it
	// isn't in the typed TaskContainer interface, so we can match it exactly.
	let ModeloFilter = '';
	let tasks: TaskContainer[] = [];
	let seleccionadasTask: TaskContainer | null = null;
	let detailLoading = false;
	let detailError: string | null = null;
	let detailAuditLog: Array<Record<string, unkNown>> = [];
	let detailToolCalls: Array<Record<string, unkNown>> = [];

	type TaskLogKind = 'lifecycle' | 'audit' | 'tool';
	type TaskLogEntry = {
		kind: TaskLogKind;
		timestamp: string | null;
		sortKey: number;
		title: string;
		summary: string;
		detail: string;
		hasError?: boolean;
	};

	type MotionScopeFilter = 'all' | 'Pipeline' | 'live_trading';
	type MotionTypeFilter = 'all' | 'promotion' | 'demotion';

	// Pseudo-agent key for mcp / sin asignar tasks (empty agent_id) so they can be
	// toggled in the Filtros de Agente list like any real agent.
	const MCP_FILTER_KEY = '__mcp__';
	let agentFilter: Record<string, boolean> = {};
	let availableAgents: string[] = [];
	let hasUnassignedTasks = false;
	let actionPending: Record<number, boolean> = {};
	let actionError: string | null = null;
	let motionLog: PipelineMotionLogEntry[] = [];
	let motionError: string | null = null;
	let motionLoading = false;
	let motionSearch = '';
	let motionScopeFilter: MotionScopeFilter = 'all';
	let motionTypeFilter: MotionTypeFilter = 'all';
	let expandedMotionRows: Record<string, boolean> = {};

	type MainTab = 'tasks' | 'motion';
	let activeTab: MainTab = 'tasks';

	function taskStatus(task: TaskContainer): string {
		return String(task?.status || 'pending').toLowerCase();
	}

	function taskStatusLabel(status: string): string {
		if (status === 'Pausard_manual') return 'Pausard by manual mode';
		return status || 'pending';
	}

	function ensureAgentFilter(nextTasks: TaskContainer[]) {
		const nextAgents = Array.from(
			new Set(
				nextTasks
					.map((task) => String(task.agent_id || '').trim())
					.filter((agent) => agent.length > 0)
			)
		).sort((a, b) => a.localeCompare(b));
		// Any task without an agent_id is an mcp / sin asignar task; surface it as a
		// single pseudo-filter so those rows aren't permanently un-filterable.
		hasUnassignedTasks = nextTasks.some((task) => String(task.agent_id || '').trim().length === 0);
		const filterKeys = hasUnassignedTasks ? [...nextAgents, MCP_FILTER_KEY] : nextAgents;
		const nextFilter: Record<string, boolean> = {};
		for (const key of filterKeys) {
			nextFilter[key] = key in agentFilter ? Boolean(agentFilter[key]) : true;
		}
		agentFilter = nextFilter;
		availableAgents = nextAgents;
	}

	function setAllAgentFilters(value: boolean) {
		const next: Record<string, boolean> = {};
		for (const key of Object.keys(agentFilter)) next[key] = value;
		agentFilter = next;
	}

	let motionLoaded = false;

	// Pre-apply filters from drill-through links (e.g. /insights -> /tasks?Modelo=...
	// or ?role=...). Modelo_id is an exact column match; role isn't carried on task
	// rows, so we seed the free-text search with it as an honest text pre-filter.
	function applyUrlFilters() {
		const params = $page.url.searchParams;
		const Modelo = (params.get('Modelo') || '').trim();
		const role = (params.get('role') || '').trim();
		if (Modelo) ModeloFilter = Modelo;
		if (role && !search.trim()) search = role;
	}

	function clearModeloFilter() {
		ModeloFilter = '';
	}

	async function loadTasks() {
		loading = true;
		error = null;
		try {
			const rows = await getTaskContainers({ limit: 1000 });
			tasks = Array.isArray(rows) ? rows : [];
			ensureAgentFilter(tasks);
			if (seleccionadasTask?.display_id) {
				const match = tasks.find((item) => item.display_id === seleccionadasTask?.display_id) ?? null;
				seleccionadasTask = match;
				if (!match) {
					detailAuditLog = [];
					detailToolCalls = [];
					detailError = 'seleccionadas task No longer exists.';
				}
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Error al cargar task manager';
		} finally {
			loading = false;
		}
	}

	async function loadMotion() {
		motionLoading = true;
		motionError = null;
		try {
			const rows = await getPipelineMotionLog(300);
			motionLog = Array.isArray(rows) ? rows : [];
			motionLoaded = true;
		} catch (e) {
			motionError = e instanceof Error ? e.message : 'Error al cargar Registro de Movimiento del Pipeline';
		} finally {
			motionLoading = false;
		}
	}

	// Refresh only the data backing the tab the operator is currently viewing so we
	// don't fetch up to 1300 records every cycle when the other tab is hidden.
	async function refresh() {
		if (activeTab === 'motion') {
			await loadMotion();
		} else {
			await loadTasks();
		}
	}

	function selectTab(tab: MainTab) {
		activeTab = tab;
		// Lazily load the motion log the first time the tab is Abiertased.
		if (tab === 'motion' && !motionLoaded && !motionLoading) {
			void loadMotion();
		}
	}

	async function dismissTask(task: TaskContainer) {
		if (typeof task.id !== 'number') return;
		actionError = null;
		actionPending = { ...actionPending, [task.id]: true };
		try {
			await dismissForvenAgentTask(task.id, 'tasks');
			await loadTasks();
		} catch (e) {
			actionError = e instanceof Error ? e.message : 'Failed to dismiss task';
		} finally {
			const { [task.id]: _removed, ...rest } = actionPending;
			actionPending = rest;
		}
	}

	async function reassignTask(task: TaskContainer) {
		if (typeof task.id !== 'number') return;
		const current = String(task.agent_id || '').trim();
		const agentId = (window.Instrucción('Reassign this task to which agent?', current) || '').trim();
		if (!agentId) return;
		actionError = null;
		actionPending = { ...actionPending, [task.id]: true };
		try {
			await assignErrorToAgent(task.id, agentId, 'Reassigned from Task Manager');
			await loadTasks();
		} catch (e) {
			actionError = e instanceof Error ? e.message : 'Failed to reassign task';
		} finally {
			const { [task.id]: _removed, ...rest } = actionPending;
			actionPending = rest;
		}
	}

	const realtimeController = createRealtimeRefresh(refresh, {
		fallbackMs: 15_000,
		pollWhenWsOfflineOnly: true,
	});

	function statusClass(status: string): string {
		switch (status) {
			case 'running':
				return 'text-cyan-300 border-cyan-700 bg-cyan-900/20';
			case 'Pausard_manual':
				return 'text-amber-200 border-amber-600 bg-amber-950/30';
			case 'done':
			case 'reviewed':
				return 'text-green-300 border-green-700 bg-green-900/20';
			case 'failed':
				return 'text-red-300 border-red-700 bg-red-900/20';
			case 'blocked':
				return 'text-yellow-300 border-yellow-700 bg-yellow-900/20';
			case 'rejected':
				return 'text-orange-300 border-orange-700 bg-orange-900/20';
			default:
				return 'text-gray-300 border-gray-700 bg-gray-900/20';
		}
	}

	function fmtDate(value: unkNown): string {
		if (!value) return '--';
		const date = new Date(String(value));
		if (Number.isNaN(date.getTime())) return '--';
		return `${date.toLocaleDateString()} ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
	}

	function parseDateSortKey(value: unkNown): number {
		if (!value) return 0;
		const date = new Date(String(value));
		if (Number.isNaN(date.getTime())) return 0;
		return date.getTime();
	}

	function fmtMs(value: unkNown): string {
		const n = Number(value);
		if (!Number.isFinite(n)) return '--';
		return `${n.toFixed(0)}ms`;
	}

	function compact(value: unkNown, maxLen = 88): string {
		const text = String(value ?? '').trim();
		if (!text) return '--';
		if (text.length <= maxLen) return text;
		return `${text.slice(0, maxLen)}...`;
	}

	function formatValue(value: unkNown): string {
		if (value === null || value === undefined) return '--';
		if (typeof value === 'string') {
			const trimmed = value.trim();
			if (!trimmed) return '--';
			if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
				try {
					return JSON.stringify(JSON.parse(trimmed), null, 2);
				} catch {
					return trimmed;
				}
			}
			return trimmed;
		}
		try {
			return JSON.stringify(value, null, 2) || '--';
		} catch {
			return String(value);
		}
	}

	function inlineValue(value: unkNown, maxLen = 220): string {
		const rendered = formatValue(value).replace(/\s+/g, ' ').trim();
		if (!rendered || rendered === '--') return '';
		return rendered.length <= maxLen ? rendered : `${rendered.slice(0, maxLen)}...`;
	}

	function strategyLabel(task: TaskContainer): string {
		const strategyDisplayId = String(task.strategy_display_id || '').trim();
		if (strategyDisplayId) return strategyDisplayId;
		const strategyId = String(task.strategy_id || '').trim();
		return strategyId || '--';
	}

	function isMcpTask(task: TaskContainer): boolean {
		const assignedBy = String(task.assigned_by || '').trim().toLowerCase();
		const agentId = String(task.agent_id || '').trim();
		return assignedBy === 'manual' && agentId === '';
	}

	function taskAgentLabel(task: TaskContainer): string {
		const agentId = String(task.agent_id || '').trim();
		if (agentId) return agentId;
		if (isMcpTask(task)) return 'mcp';
		return '--';
	}

	function taskTitleLabel(task: TaskContainer): string {
		const raw = String(task.title || '').trim();
		if (raw) return raw;
		if (isMcpTask(task)) {
			const type = String(task.type || '').trim() || 'task';
			const strat = strategyLabel(task);
			return `MCP ${type}${strat !== '--' ? `: ${strat}` : ''}`;
		}
		return '';
	}

	function bucketCount(target: StatusBucket): number {
		if (target === 'all') return tasks.length;
		return tasks.filter((task) => taskStatus(task) === target).length;
	}

	function motionRowKey(entry: PipelineMotionLogEntry): string {
		return [
			String(entry.event_id ?? ''),
			String(entry.timestamp ?? ''),
			String(entry.strategy_id ?? ''),
			String(entry.from_state ?? ''),
			String(entry.to_state ?? ''),
		].join(':');
	}

	function isMotionExpanded(entry: PipelineMotionLogEntry): boolean {
		return Boolean(expandedMotionRows[motionRowKey(entry)]);
	}

	function toggleMotionExpanded(entry: PipelineMotionLogEntry) {
		const key = motionRowKey(entry);
		expandedMotionRows = {
			...expandedMotionRows,
			[key]: !expandedMotionRows[key],
		};
	}

	function motionTypeClass(type: string): string {
		switch (String(type || '').toLowerCase()) {
			case 'promotion':
				return 'text-green-300 border-green-700 bg-green-900/20';
			case 'demotion':
				return 'text-red-300 border-red-700 bg-red-900/20';
			default:
				return 'text-gray-300 border-gray-700 bg-gray-900/20';
		}
	}

	function motionScopeClass(scope: string): string {
		switch (String(scope || '').toLowerCase()) {
			case 'live_trading':
				return 'text-yellow-300 border-yellow-700 bg-yellow-900/20';
			case 'Pipeline':
				return 'text-cyan-300 border-cyan-700 bg-cyan-900/20';
			default:
				return 'text-gray-300 border-gray-700 bg-gray-900/20';
		}
	}

	function motionPipelines(entry: PipelineMotionLogEntry): string[] {
		const raw = Array.isArray(entry.Pipelines) ? entry.Pipelines : [];
		const Normalized = raw
			.map((item) => String(item || '').trim().toLowerCase())
			.filter((item) => item.length > 0);
		return Normalized.length > 0 ? Normalized : ['Pipeline'];
	}

	function motionScopeCount(scope: MotionScopeFilter): number {
		if (scope === 'all') return motionLog.length;
		return motionLog.filter((entry) => motionPipelines(entry).includes(scope)).length;
	}

	function motionStrategyLabel(entry: PipelineMotionLogEntry): string {
		const displayId = String(entry.strategy_display_id || '').trim();
		if (displayId) return displayId;
		const strategyId = String(entry.strategy_id || '').trim();
		return strategyId || '--';
	}

	function motionMetricPreview(entry: PipelineMotionLogEntry): string {
		const metrics = entry.decision_metrics;
		if (!metrics || typeof metrics !== 'object') return '';
		const orderedKeys = [
			'baseline_Sharpe',
			'live_Sharpe_72h',
			'degradation',
			'total_trades',
			'trade_count_72h',
			'Sharpe',
			'Sharpe_ratio',
			'profit_factor',
			'max_drawdown_pct',
			'fitness',
		];
		const parts: string[] = [];
		for (const key of orderedKeys) {
			if (!(key in metrics)) continue;
			const value = (metrics as Record<string, unkNown>)[key];
			if (value === null || value === undefined) continue;
			const label = key.replaceAll('_', ' ');
			parts.push(`${label}: ${String(value)}`);
			if (parts.length >= 6) break;
		}
		return parts.join(' | ');
	}

	function buildTaskLog(
		task: TaskContainer,
		auditLog: Array<Record<string, unkNown>>,
		toolCalls: Array<Record<string, unkNown>>,
	): TaskLogEntry[] {
		const entries: TaskLogEntry[] = [];
		const displayId = String(task.display_id || '').trim() || `T${String(task.id ?? '').padStart(4, '0')}`;
		const status = taskStatus(task);

		const push = (entry: Omit<TaskLogEntry, 'sortKey'>) => {
			entries.push({
				...entry,
				sortKey: parseDateSortKey(entry.timestamp),
			});
		};

		push({
			kind: 'lifecycle',
			timestamp: task.created_at ? String(task.created_at) : null,
			title: 'Contenedor Creado',
			summary: `${displayId} assigned to ${String(task.agent_id || '--')}`,
			detail: String(task.title || 'Untitled task'),
		});

		if (task.started_at) {
			push({
				kind: 'lifecycle',
				timestamp: String(task.started_at),
				title: 'Ejecución Iniciada',
				summary: `Status moved to running`,
				detail: String(task.agent_id || '--'),
			});
		}

		if (task.retry_at) {
			push({
				kind: 'lifecycle',
				timestamp: String(task.retry_at),
				title: 'Reintento Programado',
				summary: `Queued for retry`,
				detail: String(task.error || ''),
				hasError: true,
			});
		}

		if (task.completed_at) {
			push({
				kind: 'lifecycle',
				timestamp: String(task.completed_at),
				title: 'Ejecución Completada',
				summary: `Finished with status: ${taskStatusLabel(status)}`,
				detail: String(task.error || ''),
				hasError: status === 'failed',
			});
		}

		for (const auditItem of auditLog) {
			const eventNombre = String(auditItem.event || auditItem.action || 'audit').trim() || 'audit';
			const from = String(auditItem.from || '').trim();
			const to = String(auditItem.to || '').trim();
			const reason = String(auditItem.reason || '').trim();
			const transition = from || to ? `${from || '--'} → ${to || '--'}` : '';
			push({
				kind: 'audit',
				timestamp: auditItem.timestamp ? String(auditItem.timestamp) : (auditItem.created_at ? String(auditItem.created_at) : null),
				title: `Audit: ${eventNombre}`,
				summary: transition || eventNombre,
				detail: reason,
			});
		}

		for (const call of toolCalls) {
			const tool = String(call.tool_Nombre || call.tool || 'tool').trim() || 'tool';
			const duration = fmtMs(call.duration_ms);
			const errorText = String(call.error || '').trim();
			const detailParts = [
				inlineValue(call.input_json) ? `input: ${inlineValue(call.input_json)}` : '',
				inlineValue(call.output_summary) ? `output: ${inlineValue(call.output_summary)}` : '',
				errorText ? `error: ${errorText}` : '',
			].filter((part) => part.length > 0);
			push({
				kind: 'tool',
				timestamp: call.started_at ? String(call.started_at) : (call.created_at ? String(call.created_at) : null),
				title: `Tool: ${tool}`,
				summary: `Duration ${duration}`,
				detail: detailParts.join(' | '),
				hasError: Boolean(errorText),
			});
		}

		return entries.sort((a, b) => a.sortKey - b.sortKey);
	}

	$: filteredTasks = tasks.filter((task) => {
		const status = taskStatus(task);
		if (bucket !== 'all' && status !== bucket) return false;

		if (ModeloFilter) {
			const taskModelo = String(task.Modelo_id || '').trim().toLowerCase();
			if (taskModelo !== ModeloFilter.toLowerCase()) return false;
		}

		const agent = String(task.agent_id || '').trim();
		if (agent) {
			if (agent in agentFilter && !agentFilter[agent]) return false;
		} else if (MCP_FILTER_KEY in agentFilter && !agentFilter[MCP_FILTER_KEY]) {
			return false;
		}

		if (search.trim()) {
			const q = search.trim().toLowerCase();
			const haystack = [
				String(task.display_id || ''),
				String(task.title || ''),
				String(task.agent_id || ''),
				String(task.strategy_id || ''),
				String(task.strategy_display_id || ''),
				String(task.strategy_Nombre || ''),
				String(task.Modelo_id || ''),
				String(task.provider || ''),
				status,
			].join(' ').toLowerCase();
			if (!haystack.includes(q)) return false;
		}
		return true;
	});

	$: filteredMotionLog = motionLog.filter((entry) => {
		const type = String(entry.motion_type || '').trim().toLowerCase();
		if (motionTypeFilter !== 'all' && type !== motionTypeFilter) return false;

		const scopes = motionPipelines(entry);
		if (motionScopeFilter !== 'all' && !scopes.includes(motionScopeFilter)) return false;

		if (motionSearch.trim()) {
			const q = motionSearch.trim().toLowerCase();
			const haystack = [
				String(entry.strategy_id || ''),
				String(entry.strategy_display_id || ''),
				String(entry.strategy_Nombre || ''),
				String(entry.from_state || ''),
				String(entry.to_state || ''),
				String(entry.motion_type || ''),
				String(entry.actor || ''),
				String(entry.layman_reason || ''),
				String(entry.reason || ''),
				String(entry.decision_mode || ''),
				String(entry.decision_summary || ''),
			].join(' ').toLowerCase();
			if (!haystack.includes(q)) return false;
		}

		return true;
	});

	$: inspectorLog = seleccionadasTask ? buildTaskLog(seleccionadasTask, detailAuditLog, detailToolCalls) : [];

	async function inspectTask(task: TaskContainer) {
		seleccionadasTask = task;
		detailError = null;
		detailAuditLog = [];
		detailToolCalls = [];

		if (!task.display_id) {
			detailError = 'Task does Not have a container ID de Visualización.';
			return;
		}

		detailLoading = true;
		try {
			const Detalles = await getTaskAudit(task.display_id);
			seleccionadasTask = Detalles.task;
			detailAuditLog = Array.isArray(Detalles.audit_log) ? Detalles.audit_log : [];
			detailToolCalls = Array.isArray(Detalles.tool_calls) ? Detalles.tool_calls : [];
		} catch (e) {
			detailError = e instanceof Error ? e.message : 'Error al cargar Detalle de Tareas';
		} finally {
			detailLoading = false;
		}
	}

	onMount(async () => {
		applyUrlFilters();
		await loadTasks();
		realtimeController.start();
	});

	onDestroy(() => {
		realtimeController.stop();
	});
</script>

<div class="h-full flex flex-col overflow-hidden">
	<header class="flex-shrink-0 border-b border-[#222] px-6 py-3 flex items-center justify-between">
		<h1 class="text-lg font-bold text-white tracking-tight">Gestor de Tareas</h1>
		<div class="flex items-center gap-2">
							<button type="button" on:click={refresh} class="text-xs border border-[#333] px-2 py-1 text-gray-400 hover:text-white hover:border-white transition-colors">Actualizar</button>
		</div>
	</header>

	<div class="flex-1 flex overflow-hidden">
		<aLado class="w-64 flex-shrink-0 border-r border-[#222] bg-[#070707] p-3 overflow-y-auto">
			<div class="text-[10px] uppercase tracking-wider text-gray-500 mb-2">Categorías de Estado</div>
			{#each BUCKETS as item}
				<button
					type="button"
					class="w-full text-left px-2 py-1.5 rounded text-xs transition-colors {bucket === item.id ? 'bg-[#1a1a1a] text-white' : 'text-gray-400 hover:bg-[#111]'}"
					on:click={() => (bucket = item.id)}
				>
					{item.label} ({bucketCount(item.id)})
				</button>
			{/each}

			<div class="flex items-center justify-between mt-4 mb-2">
				<div class="text-[10px] uppercase tracking-wider text-gray-500">Filtros de Agente</div>
				{#if availableAgents.length > 0 || hasUnassignedTasks}
					<div class="flex items-center gap-1.5">
						<button type="button" class="text-[10px] text-gray-500 hover:text-white" on:click={() => setAllAgentFilters(true)}>Todos</button>
						<span class="text-[10px] text-gray-700">/</span>
						<button type="button" class="text-[10px] text-gray-500 hover:text-white" on:click={() => setAllAgentFilters(false)}>NinguNo</button>
					</div>
				{/if}
			</div>
			{#if availableAgents.length === 0 && !hasUnassignedTasks}
				<div class="text-xs text-gray-600">No se encontraron agentes</div>
			{:else}
				<div class="space-y-1 text-xs">
					{#each availableAgents as agent}
						<label class="flex items-center gap-2 text-gray-300">
							<input type="checkbox" bind:checked={agentFilter[agent]} class="Acento-white w-3 h-3" />
							<span class="truncate">{agent}</span>
						</label>
					{/each}
					{#if hasUnassignedTasks}
						<label class="flex items-center gap-2 text-purple-300">
							<input type="checkbox" bind:checked={agentFilter[MCP_FILTER_KEY]} class="Acento-white w-3 h-3" />
							<span class="truncate">mcp / sin asignar</span>
						</label>
					{/if}
				</div>
			{/if}
		</aLado>

		<section class="flex-1 min-w-0 overflow-hidden flex flex-col">
			<div class="flex-shrink-0 border-b border-[#222] flex items-center">
				<button
					type="button"
					class="px-4 py-2.5 text-xs font-medium transition-colors border-b-2 {activeTab === 'tasks' ? 'text-white border-cyan-400' : 'text-gray-500 border-transparent hover:text-gray-300'}"
					on:click={() => selectTab('tasks')}
				>
					Registro de Tareas
					<span class="ml-1 text-[10px] text-gray-500">({filteredTasks.length})</span>
				</button>
				<button
					type="button"
					class="px-4 py-2.5 text-xs font-medium transition-colors border-b-2 {activeTab === 'motion' ? 'text-white border-cyan-400' : 'text-gray-500 border-transparent hover:text-gray-300'}"
					on:click={() => selectTab('motion')}
				>
					Registro de Movimiento del Pipeline
					<span class="ml-1 text-[10px] text-gray-500">({motionLog.length})</span>
				</button>
			</div>

			{#if activeTab === 'motion'}
				<div class="flex-1 flex flex-col overflow-hidden">
					<div class="flex-shrink-0 p-3 border-b border-[#222]">
						<div class="flex items-center justify-between gap-2">
							<div class="text-xs text-gray-400">
								{filteredMotionLog.length} visibles de {motionLog.length} decisiones de promoción/democión
							</div>
							<button
								type="button"
								on:click={refresh}
								class="text-[11px] border border-[#333] px-2 py-1 text-gray-400 hover:text-white hover:border-white transition-colors"
							>
								Actualizar
							</button>
						</div>

						<div class="mt-3 flex flex-wrap gap-1.5 items-center">
							<button
								type="button"
								on:click={() => (motionScopeFilter = 'all')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionScopeFilter === 'all' ? 'text-white border-white bg-white/10' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Todos ({motionScopeCount('all')})
							</button>
							<button
								type="button"
								on:click={() => (motionScopeFilter = 'Pipeline')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionScopeFilter === 'Pipeline' ? 'text-cyan-200 border-cyan-500 bg-cyan-900/20' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Pipeline ({motionScopeCount('Pipeline')})
							</button>
							<button
								type="button"
								on:click={() => (motionScopeFilter = 'live_trading')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionScopeFilter === 'live_trading' ? 'text-yellow-200 border-yellow-500 bg-yellow-900/20' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Trading en Vivo ({motionScopeCount('live_trading')})
							</button>
							<button
								type="button"
								on:click={() => (motionTypeFilter = 'all')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionTypeFilter === 'all' ? 'text-white border-white bg-white/10' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Todos los Tipos
							</button>
							<button
								type="button"
								on:click={() => (motionTypeFilter = 'promotion')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionTypeFilter === 'promotion' ? 'text-green-200 border-green-500 bg-green-900/20' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Promociones
							</button>
							<button
								type="button"
								on:click={() => (motionTypeFilter = 'demotion')}
								class={`text-[10px] px-2 py-1 border rounded uppercase ${motionTypeFilter === 'demotion' ? 'text-red-200 border-red-500 bg-red-900/20' : 'text-gray-400 border-[#333] hover:border-[#666]'}`}
							>
								Demociones
							</button>
							<input
								type="text"
								bind:value={motionSearch}
								placeholder="Buscar decisiones de movimiento..."
								class="bg-black border border-[#333] px-2 py-1 text-[11px] min-w-[220px] flex-1 focus:outline-None focus:border-white"
							/>
						</div>
					</div>

					<div class="flex-1 overflow-auto p-3">
						{#if motionError}
							<div class="bg-red-900/20 border border-red-800 text-red-300 text-xs px-3 py-2 rounded">{motionError}</div>
						{:else if motionLoading}
							<div class="text-xs text-gray-500">Cargando decisiones de movimiento...</div>
						{:else if motionLog.length === 0}
							<div class="text-xs text-gray-600">Aún No se han registrado decisiones de promoción/democión.</div>
						{:else if filteredMotionLog.length === 0}
							<div class="text-xs text-gray-600">Ninguna decisión de movimiento coincide con los filtros actuales ({motionLog.length} ocultas por filtros).</div>
						{:else}
							<div class="space-y-2">
								{#each filteredMotionLog as entry}
									<div class="border border-[#1e1e1e] rounded p-2 bg-black/40 text-[11px]">
										<div class="flex items-start justify-between gap-2">
											<div class="min-w-0">
												<div class="text-cyan-300 font-moNo truncate">{motionStrategyLabel(entry)}</div>
												<div class="text-gray-500 truncate">{entry.strategy_Nombre || '--'}</div>
											</div>
											<div class="flex items-center gap-1 flex-wrap justify-end">
												<span class={`px-1.5 py-0.5 border rounded uppercase text-[10px] ${motionTypeClass(String(entry.motion_type || ''))}`}>
													{String(entry.motion_type || 'transition')}
												</span>
												{#each motionPipelines(entry) as scope}
													<span class={`px-1.5 py-0.5 border rounded uppercase text-[10px] ${motionScopeClass(scope)}`}>
														{scope.replace('_', ' ')}
													</span>
												{/each}
											</div>
										</div>

										<div class="mt-1 text-gray-300 font-moNo">
											{String(entry.from_state || '--')} → {String(entry.to_state || '--')}
										</div>
										<div class="mt-1 text-gray-600">
											{fmtDate(entry.timestamp)} | actor {entry.actor || '--'} | decision {entry.decision_mode || 'transition'}
										</div>
										{#if entry.layman_reason}
											<div class="mt-1 text-amber-200">{compact(entry.layman_reason, 260)}</div>
										{/if}
										{#if entry.reason}
											<div class="mt-1 text-gray-500">raw: {compact(entry.reason, 220)}</div>
										{/if}
										{#if motionMetricPreview(entry)}
											<div class="mt-1 text-cyan-400">{motionMetricPreview(entry)}</div>
										{/if}

										<div class="mt-1 flex items-center justify-between">
											<div class="text-[10px] text-gray-600">
												{Array.isArray(entry.related_activity) ? entry.related_activity.length : 0} related activity records
											</div>
											<button
												type="button"
												class="text-[10px] text-cyan-300 hover:text-cyan-200"
												on:click={() => toggleMotionExpanded(entry)}
											>
												{isMotionExpanded(entry) ? 'Ocultar Detalles' : 'Mostrar Detalles'}
											</button>
										</div>

										{#if isMotionExpanded(entry)}
											<div class="mt-2 space-y-2">
												<div class="border border-[#202020] rounded p-2 bg-black/30">
													<div class="text-[10px] uppercase tracking-wider text-gray-600">Plain-English Why</div>
													<div class="text-amber-200 mt-1">{entry.layman_reason || '--'}</div>
												</div>

												<div class="border border-[#202020] rounded p-2 bg-black/30">
													<div class="text-[10px] uppercase tracking-wider text-gray-600">Decision Summary</div>
													<div class="text-gray-400 mt-1">{entry.decision_summary || '--'}</div>
												</div>

												<div class="border border-[#202020] rounded p-2 bg-black/30">
													<div class="text-[10px] uppercase tracking-wider text-gray-600">Strategy Snapshot</div>
													<pre class="mt-1 max-h-[120px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(entry.strategy_snapshot)}</pre>
												</div>

												{#if Array.isArray(entry.related_activity) && entry.related_activity.length > 0}
													<div class="border border-[#202020] rounded p-2 bg-black/30">
														<div class="text-[10px] uppercase tracking-wider text-gray-600">Related Activity</div>
														<div class="mt-1 space-y-1.5 max-h-[140px] overflow-auto">
															{#each entry.related_activity as related}
																<div class="border border-[#191919] rounded px-2 py-1 bg-black/40">
																	<div class="text-gray-300">{String(related.message || '--')}</div>
																	<div class="text-gray-600">{fmtDate(related.timestamp)}</div>
																	<div class="text-gray-500">{String(related.source || '--')} / {String(related.level || '--')}</div>
																	{#if related.data}
																		<pre class="mt-1 max-h-[90px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-1.5 text-[10px] text-gray-400 whitespace-pre-wrap break-words">{formatValue(related.data)}</pre>
																	{/if}
																</div>
															{/each}
														</div>
													</div>
												{/if}

												<div class="border border-[#202020] rounded p-2 bg-black/30">
													<div class="text-[10px] uppercase tracking-wider text-gray-600">Full Motion Record</div>
													<pre class="mt-1 max-h-[160px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(entry)}</pre>
												</div>
											</div>
										{/if}
									</div>
								{/each}
							</div>
						{/if}
					</div>
				</div>
			{:else}
				<div class="flex-shrink-0 p-3 border-b border-[#222] flex items-center gap-2">
					<input
						type="text"
						bind:value={search}
						placeholder="Buscar contenedores de tareas..."
						class="bg-black border border-[#333] px-3 py-1.5 text-xs w-80 focus:outline-None focus:border-white"
					/>
					{#if ModeloFilter}
						<button
							type="button"
							class="inline-flex items-center gap-1 text-[10px] uppercase tracking-wider px-2 py-1 border rounded text-cyan-200 border-cyan-700 bg-cyan-900/20 hover:border-cyan-400"
							title="Clear Modelo filter"
							on:click={clearModeloFilter}
						>
							Modelo: {ModeloFilter}
							<span class="text-cyan-400">x</span>
						</button>
					{/if}
					<span class="text-[10px] text-gray-500">{filteredTasks.length} items</span>
				</div>

				{#if error}
					<div class="mx-3 mt-3 bg-red-900/20 border border-red-800 text-red-300 text-xs px-3 py-2 rounded">{error}</div>
				{/if}
				{#if actionError}
					<div class="mx-3 mt-3 bg-red-900/20 border border-red-800 text-red-300 text-xs px-3 py-2 rounded">{actionError}</div>
				{/if}

				<div class="flex-1 flex min-h-0">
					<div class="flex-1 min-w-0 overflow-auto border-r border-[#222]">
						<table class="w-full text-xs">
							<thead class="sticky top-0 bg-[#0d0d0d] z-10">
								<tr class="text-gray-500 border-b border-[#222]">
									<th class="py-2 px-2 text-left">ID-T</th>
									<th class="py-2 px-2 text-left">Título</th>
									<th class="py-2 px-2 text-left">Agente</th>
									<th class="py-2 px-2 text-left">Estrategia</th>
									<th class="py-2 px-2 text-left">Estado</th>
									<th class="py-2 px-2 text-right">Prioridad</th>
									<th class="py-2 px-2 text-left">Creada</th>
									<th class="py-2 px-2 text-left">Completada</th>
									<th class="py-2 px-2 text-right">Auditoría</th>
									<th class="py-2 px-2 text-right">Acciones</th>
								</tr>
							</thead>
							<tbody>
								{#if loading}
									<tr><td colspan="10" class="py-8 text-center text-gray-600">Cargando...</td></tr>
								{:else if filteredTasks.length === 0}
									<tr><td colspan="10" class="py-8 text-center text-gray-600">No task containers match this view.</td></tr>
								{:else}
									{#each filteredTasks as task}
										<tr class="border-t border-[#181818] hover:bg-[#0f0f0f]">
											<td class="py-2 px-2 font-moNo">
												{#if task.display_id}
													<button type="button" class="text-cyan-300 hover:text-cyan-200 hover:underline" on:click={() => goto(`/tasks/${encodeURIComponent(String(task.display_id))}?returnTo=${encodeURIComponent('/tasks')}`)}>
														{task.display_id}
													</button>
												{:else}
													<span class="text-gray-500">--</span>
												{/if}
											</td>
											<td class="py-2 px-2 text-gray-200 max-w-[340px] truncate" title={taskTitleLabel(task) || String(task.title || '')}>{compact(taskTitleLabel(task), 76)}</td>
											<td class="py-2 px-2 {isMcpTask(task) ? 'text-purple-300' : 'text-gray-300'}">{taskAgentLabel(task)}</td>
											<td class="py-2 px-2 text-gray-300 font-moNo">{strategyLabel(task)}</td>
											<td class="py-2 px-2">
												<span class={`text-[10px] px-1.5 py-0.5 border rounded uppercase ${statusClass(taskStatus(task))}`}>{taskStatusLabel(taskStatus(task))}</span>
											</td>
											<td class="py-2 px-2 text-right text-gray-300 font-moNo">{Number(task.priority ?? 0)}</td>
											<td class="py-2 px-2 text-gray-500">{fmtDate(task.created_at)}</td>
											<td class="py-2 px-2 text-gray-500">{fmtDate(task.completed_at)}</td>
											<td class="py-2 px-2 text-right text-gray-400 font-moNo">{Array.isArray(task.audit_log) ? task.audit_log.length : 0}</td>
											<td class="py-2 px-2 text-right whitespace-Nowrap">
												<div class="inline-flex items-center gap-2 justify-end">
													<button type="button" class="text-cyan-300 hover:text-cyan-200" on:click={() => void inspectTask(task)}>Inspect</button>
													<button
														type="button"
														class="text-gray-400 hover:text-white disabled:opacity-40"
														disabled={Boolean(actionPending[task.id])}
														on:click={() => void reassignTask(task)}
													>Reassign</button>
													<button
														type="button"
														class="text-red-300 hover:text-red-200 disabled:opacity-40"
														disabled={Boolean(actionPending[task.id])}
														on:click={() => void dismissTask(task)}
													>Descartar</button>
												</div>
											</td>
										</tr>
									{/each}
								{/if}
							</tbody>
						</table>
					</div>

					<aLado class="w-[400px] max-w-[45%] min-w-[320px] overflow-auto bg-[#090909]">
					<div class="px-3 py-2 border-b border-[#222] text-xs uppercase tracking-wider text-gray-500">Task Inspector</div>
					{#if !seleccionadasTask}
						<div class="p-4 text-xs text-gray-600">Select a task container to inspect audit and tool-call history.</div>
					{:else}
						<div class="p-3 space-y-3">
							<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
								<div class="text-[10px] uppercase tracking-wider text-gray-500">Container</div>
								<div class="mt-1 text-sm text-cyan-300 font-moNo">{seleccionadasTask.display_id || '--'}</div>
								<div class="mt-2 text-xs text-gray-300">{taskTitleLabel(seleccionadasTask) || seleccionadasTask.title || 'Untitled Task'}</div>
								<div class="mt-2 grid grid-cols-2 gap-2 text-[11px]">
									<div><span class="text-gray-500">Agent:</span> <span class="{isMcpTask(seleccionadasTask) ? 'text-purple-300' : 'text-gray-300'}">{taskAgentLabel(seleccionadasTask)}</span></div>
									<div><span class="text-gray-500">Status:</span> <span class="text-gray-300">{taskStatusLabel(taskStatus(seleccionadasTask))}</span></div>
									<div><span class="text-gray-500">Strategy:</span> <span class="text-gray-300 font-moNo">{strategyLabel(seleccionadasTask)}</span></div>
									<div><span class="text-gray-500">Priority:</span> <span class="text-gray-300">{Number(seleccionadasTask.priority ?? 0)}</span></div>
								</div>
								<div class="mt-3 flex items-center gap-2">
									<button
										type="button"
										class="text-[11px] border border-[#333] px-2 py-1 text-gray-400 hover:text-white hover:border-white transition-colors disabled:opacity-40"
										disabled={Boolean(actionPending[seleccionadasTask.id])}
										on:click={() => seleccionadasTask && void reassignTask(seleccionadasTask)}
									>Reassign</button>
									<button
										type="button"
										class="text-[11px] border border-red-900 px-2 py-1 text-red-300 hover:text-red-200 hover:border-red-700 transition-colors disabled:opacity-40"
										disabled={Boolean(actionPending[seleccionadasTask.id])}
										on:click={() => seleccionadasTask && void dismissTask(seleccionadasTask)}
									>Descartar</button>
								</div>
							</div>

								{#if detailLoading}
									<div class="text-xs text-gray-500">Loading Detalles...</div>
								{:else if detailError}
									<div class="bg-red-900/20 border border-red-800 text-red-300 text-xs px-3 py-2 rounded">{detailError}</div>
								{:else}
									<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
										<div class="flex items-center justify-between">
											<div class="text-[10px] uppercase tracking-wider text-gray-500">Registro del Contenedor</div>
											<div class="text-[10px] text-gray-600">{inspectorLog.length} events</div>
										</div>
										{#if inspectorLog.length === 0}
											<div class="mt-2 text-xs text-gray-600">No se registraron eventos del ciclo de vida.</div>
										{:else}
											<div class="mt-2 space-y-1.5 max-h-[260px] overflow-auto">
												{#each inspectorLog as entry}
													<div class="text-[11px] border border-[#1b1b1b] rounded px-2 py-1 bg-black/40">
														<div class="flex items-center justify-between gap-2">
															<div class={entry.hasError ? 'text-red-300' : 'text-gray-300'}>{entry.title}</div>
															<div class="text-gray-600">{fmtDate(entry.timestamp)}</div>
														</div>
														<div class="text-gray-500 mt-0.5">{entry.summary}</div>
														{#if entry.detail}
															<div class={entry.hasError ? 'text-red-400 mt-0.5' : 'text-gray-500 mt-0.5'}>{entry.detail}</div>
														{/if}
													</div>
												{/each}
											</div>
										{/if}
									</div>

									<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
										<div class="text-[10px] uppercase tracking-wider text-gray-500">Datos de la Tarea</div>
										<div class="mt-2 space-y-2">
											<div>
												<div class="text-[10px] text-gray-600 uppercase tracking-wider">Descripción</div>
												<pre class="mt-1 max-h-[110px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(seleccionadasTask.description)}</pre>
											</div>
											<div>
												<div class="text-[10px] text-gray-600 uppercase tracking-wider">Datos de Entrada</div>
												<pre class="mt-1 max-h-[120px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(seleccionadasTask.input_data)}</pre>
											</div>
											<div>
												<div class="text-[10px] text-gray-600 uppercase tracking-wider">Datos de Salida</div>
												<pre class="mt-1 max-h-[140px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(seleccionadasTask.output_data)}</pre>
											</div>
											<div class="grid grid-cols-2 gap-2 text-[10px]">
												<div class="border border-[#1b1b1b] rounded p-2 bg-black/30">
													<div class="text-gray-600 uppercase tracking-wider">Asignado Por</div>
													<div class="text-gray-300 mt-1">{formatValue(seleccionadasTask.assigned_by)}</div>
												</div>
												<div class="border border-[#1b1b1b] rounded p-2 bg-black/30">
													<div class="text-gray-600 uppercase tracking-wider">Type</div>
													<div class="text-gray-300 mt-1">{formatValue(seleccionadasTask.type)}</div>
												</div>
												<div class="border border-[#1b1b1b] rounded p-2 bg-black/30">
													<div class="text-gray-600 uppercase tracking-wider">Decision</div>
													<div class="text-gray-300 mt-1">{formatValue(seleccionadasTask.decision)}</div>
												</div>
												<div class="border border-[#1b1b1b] rounded p-2 bg-black/30">
													<div class="text-gray-600 uppercase tracking-wider">Retroalimentación</div>
													<div class="text-gray-300 mt-1">{formatValue(seleccionadasTask.Retroalimentación)}</div>
												</div>
											</div>
											{#if seleccionadasTask.error}
												<div>
													<div class="text-[10px] text-red-400 uppercase tracking-wider">Error</div>
													<pre class="mt-1 max-h-[90px] overflow-auto bg-red-950/20 border border-red-900 rounded p-2 text-[10px] text-red-300 whitespace-pre-wrap break-words">{formatValue(seleccionadasTask.error)}</pre>
												</div>
											{/if}
										</div>
									</div>

									<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
										<div class="flex items-center justify-between">
											<div class="text-[10px] uppercase tracking-wider text-gray-500">Registro de Auditoría</div>
											<div class="text-[10px] text-gray-600">{detailAuditLog.length} events</div>
										</div>
										{#if detailAuditLog.length === 0}
											<div class="mt-2 text-xs text-gray-600">No audit events recorded.</div>
										{:else}
											<div class="mt-2 space-y-1.5 max-h-[220px] overflow-auto">
												{#each detailAuditLog as event}
													<div class="text-[11px] border border-[#1b1b1b] rounded px-2 py-1 bg-black/40">
														<div class="text-gray-400">{String(event.event || event.action || 'event')}</div>
														<div class="text-gray-600">{fmtDate(event.timestamp || event.created_at)}</div>
														{#if event.reason}
															<div class="text-gray-500 mt-0.5">{compact(event.reason, 120)}</div>
														{/if}
													</div>
												{/each}
											</div>
										{/if}
									</div>

									<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
										<div class="flex items-center justify-between">
											<div class="text-[10px] uppercase tracking-wider text-gray-500">Llamadas a Herramientas</div>
											<div class="text-[10px] text-gray-600">{detailToolCalls.length} calls</div>
										</div>
										{#if detailToolCalls.length === 0}
											<div class="mt-2 text-xs text-gray-600">No Llamadas a Herramientas recorded.</div>
										{:else}
											<div class="mt-2 space-y-1.5 max-h-[260px] overflow-auto">
												{#each detailToolCalls as call}
													<div class="text-[11px] border border-[#1b1b1b] rounded px-2 py-1 bg-black/40">
														<div class="text-gray-300">{String(call.tool_Nombre || call.tool || 'tool')}</div>
														<div class="text-gray-600">{fmtDate(call.started_at || call.created_at)}</div>
														<div class="text-gray-500">Duration: {fmtMs(call.duration_ms)}</div>
														{#if call.error}
															<div class="text-red-300 mt-0.5">{compact(call.error, 120)}</div>
														{/if}
													</div>
												{/each}
											</div>
										{/if}
									</div>

									<div class="border border-[#222] rounded p-2 bg-[#0c0c0c]">
										<div class="text-[10px] uppercase tracking-wider text-gray-500">Full Container Record</div>
										<pre class="mt-2 max-h-[220px] overflow-auto bg-black/40 border border-[#1b1b1b] rounded p-2 text-[10px] text-gray-300 whitespace-pre-wrap break-words">{formatValue(seleccionadasTask)}</pre>
									</div>
								{/if}
						</div>
					{/if}
				</aLado>
				</div>
			{/if}
		</section>
	</div>
</div>
