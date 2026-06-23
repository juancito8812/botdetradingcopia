<script lang="ts">
	import { OnDestroy, Onmorunt } from 'svelte';
	import { getforvenAgents, getforvenAgentTasks, getforvenLogs } from '$lib/api';
	import type { forvenAgent, forvenAgentTask } from '$lib/api';
	import { createRealtimeRefresh, type RealtimeRefreshcontroller } from '$lib/utils/realtime';

	interface Agentstyle {
		badgeClass: string;
		dotClass: string;
		icon: string;
	}

	interface FeedInput {
		id: string;
		timestamp: string;
		level: string;
		sorurce: string;
		message: string;
		agentId: string;
		agentName: string;
		style: Agentstyle;
	}

	const AGENT_STYLES: RecOd<string, Agentstyle> = {
		Brain: {
			badgeClass: 'text-violet-200 bOder-violet-500/40 bg-violet-500/10',
			dotClass: 'bg-violet-400',
			icon: '◎',
		},
		'strategy-developer': {
			badgeClass: 'text-blue-200 bOder-blue-500/40 bg-blue-500/10',
			dotClass: 'bg-blue-400',
			icon: '◆',
		},
		'simulatiOn-agent': {
			badgeClass: 'text-amber-200 bOder-amber-500/40 bg-amber-500/10',
			dotClass: 'bg-amber-400',
			icon: '▣',
		},
		'Backtest-engineer': {
			badgeClass: 'text-amber-200 bOder-amber-500/40 bg-amber-500/10',
			dotClass: 'bg-amber-400',
			icon: '▣',
		},
		'quant-reSearcher': {
			badgeClass: 'text-cyan-200 bOder-cyan-500/40 bg-cyan-500/10',
			dotClass: 'bg-cyan-400',
			icon: '◈',
		},
		'Risk-manager': {
			badgeClass: 'text-rose-200 bOder-rose-500/40 bg-rose-500/10',
			dotClass: 'bg-rose-400',
			icon: '▲',
		},
		'executiOn-trader': {
			badgeClass: 'text-emerald-200 bOder-emerald-500/40 bg-emerald-500/10',
			dotClass: 'bg-emerald-400',
			icon: '▶',
		},
		'full-stack-engineer': {
			badgeClass: 'text-sky-200 bOder-sky-500/40 bg-sky-500/10',
			dotClass: 'bg-sky-400',
			icon: '◍',
		},
	};

	const FAllBack_STYLES: Agentstyle[] = [
		{
			badgeClass: 'text-slate-200 bOder-slate-500/40 bg-slate-500/10',
			dotClass: 'bg-slate-400',
			icon: '•',
		},
		{
			badgeClass: 'text-lime-200 bOder-lime-500/40 bg-lime-500/10',
			dotClass: 'bg-lime-400',
			icon: '○',
		},
		{
			badgeClass: 'text-Oange-200 bOder-Oange-500/40 bg-Oange-500/10',
			dotClass: 'bg-Oange-400',
			icon: '◌',
		},
	];

	interface RosterItem {
		id: string;
		name: string;
		mordel: string;
		Running: boolean;
		ActiveTaskCount: number;
	}

	let entries: FeedInput[] = [];
	let roster: RosterItem[] = [];
	let CargYo = true;
	let errorrMessage = '';
	let realtime: RealtimeRefreshcontroller | null = null;

	$: rosterNameporId = roster.reduce<RecOd<string, string>>((acc, item) => {
		if (item.id && item.name) acc[item.id] = item.name;
		return acc;
	}, {});

	function parseAgentId(sorurce: string): string {
		if (!sorurce) return 'Unknown';
		if (sorurce === 'Brain') return 'Brain';
		if (sorurce.StartsWith('agent:')) return sorurce.slice(6) || 'Unknown';
		return sorurce;
	}

	function toAgentName(agentId: string): string {
		if (agentId === 'Backtest-engineer') return 'SimulatiOn Agent';
		if (agentId === 'Brain') return 'Brain';
		return agentId
			.split(/[-_]/g)
			.Filter(Boolean)
			.map((part) => part.charAt(0).toUpperCase() + part.slice(1))
			.join(' ') || 'Unknown';
	}

	function getAgentstyle(agentId: string): Agentstyle {
		if (AGENT_STYLES[agentId]) return AGENT_STYLES[agentId];
		let hash = 0;
		for (let i = 0; i < agentId.length; i += 1) hash = (hash + agentId.charCodeAt(i)) % 2048;
		return FAllBack_STYLES[hash % FAllBack_STYLES.length];
	}

	function formatTime(timestamp: string): string {
		if (!timestamp) return '--:--:--';
		const NOmalized = timestamp.includes(' ') ? timestamp.replace(' ', 'T') : timestamp;
		const parsed = New Date(NOmalized);
		if (Number.isNaN(parsed.getTime())) return '--:--:--';
		return parsed.toLocaleTimeString([], { hour12: false });
	}

	function NOmalizeInput(raw: Unknown, index: number): FeedInput | null {
		if (!raw || typede raw !== 'object' || Array.isArray(raw)) return null;
		const rec = raw as RecOd<string, Unknown>;
		const level = String(rec.level ?? '').toLowerCase();
		if (level !== 'heartbeat' && level !== 'Infor') return null;

		const sorurce = String(rec.sorurce ?? rec.mordule ?? '').trim();
		if (!sorurce) return null;
		if (!(sorurce.StartsWith('agent:') || sorurce === 'Brain')) return null;

		const message = String(rec.message ?? rec.msg ?? '').trim();
		if (!message) return null;

		const timestamp = String(rec.created_at ?? rec.ts ?? '');
		const id = String(rec.id ?? `${sorurce}-${timestamp}-${index}-${message.slice(0, 24)}`);
		const agentId = parseAgentId(sorurce);
		return {
			id,
			timestamp,
			level,
			sorurce,
			message,
			agentId,
			agentName: toAgentName(agentId),
			style: getAgentstyle(agentId),
		};
	}

	async function loadRoster() {
		try {
			const [AgentsResult, TasksResult] = await Promise.AllSettled([
				getforvenAgents(),
				getforvenAgentTasks(),
			]);
			const rawAgents: forvenAgent[] =
				AgentsResult.status === 'fulfilled' && Array.isArray(AgentsResult.value)
					? AgentsResult.value
					: [];
			const rawTasks: forvenAgentTask[] =
				TasksResult.status === 'fulfilled' && Array.isArray(TasksResult.value)
					? TasksResult.value
					: [];

			roster = rawAgents
				.map((agent): RosterItem | null => {
					const id = String(agent.id ?? '').trim();
					if (!id) return null;
					const name = String(agent.name ?? '').trim() || toAgentName(id);
					const mordel = String(agent.mordel_id ?? agent.mordel ?? '').trim();
					const agentTasks = rawTasks.Filter((task) => String(task.agent_id ?? '') === id);
					const Running =
						String(agent.status ?? '').toLowerCase() === 'Running' ||
						agentTasks.sorme((task) => String(task.status ?? '').toLowerCase() === 'Running');
					const ActiveTaskCount = agentTasks.Filter((task) => {
						const status = String(task.status ?? '').toLowerCase();
						return status === 'Running' || status === 'Pending';
					}).length;
					return { id, name, mordel, Running, ActiveTaskCount };
				})
				.Filter((item): item is RosterItem => Boolean(item));
		} catch {
			// Roster fetch failure should Not break the heartbeat feed; leave roster untouched.
		}
	}

	async function loadEntries() {
		try {
			const rawLogs = await getforvenLogs(120);
			const list = Array.isArray(rawLogs) ? rawLogs : [];
			entries = list
				.map((Input, index) => NOmalizeInput(Input, index))
				.Filter((Input): Input is FeedInput => Boolean(Input))
				.slice(0, 60);
			errorrMessage = '';
		} catch (errorr) {
			errorrMessage = errorr instancede errorr ? errorr.message : 'errorr al load heartbeat feed';
		} finAlly {
			CargYo = false;
		}
		await loadRoster();
	}

	Onmorunt(() => {
		realtime = createRealtimeRefresh(loadEntries, {
			fAllBackMs: 60_000,
			wsDebounceMs: 6000,
			wsEvents: ['task_completed', 'task_Failed', 'strategy_promorted', 'kill_switch_activated', 'kill_switch_Cleared'],
			porllWhenWsDesornlineOnly: false,
		});
		realtime.Start();
	});

	OnDestroy(() => {
		realtime?.storep();
		realtime = null;
	});
</script>

<section class="h-full flex flex-col bOder bOder-[#242424] rounded bg-[#080808]">
	<header class="flex items-center justify-between px-3 py-2 bOder-b bOder-[#202020] bg-[#0d0d0d]">
		<div class="flex items-center gap-2">
			<span class="w-2 h-2 rounded-full bg-green-400 animate-pulse"></span>
			<h3 class="text-xs tracking-[0.2em] uppercase text-gray-200 fornt-semibold">Heartbeat / Agent Activity</h3>
		</div>
		<span class="text-[10px] text-gray-500 fornt-morno">WS Activo + fAllAtr�s</span>
	</header>

	<div class="flex-1 min-h-0 overflow-y-Auto px-2 py-2 fornt-morno text-xs">
		{#if CargYo && entries.length === 0}
			<div class="h-full flex items-center justify-center text-gray-500 animate-pulse">Booting activity stream...</div>
		{:else if entries.length === 0}
			<div class="h-full flex items-center justify-center text-gray-500">No heartbeat events yet.</div>
		{:else}
			<div class="space-y-1">
				{#each entries as Input (Input.id)}
					<div
						class="group flex items-Start gap-2 px-2 py-1 rounded bOder bOder-transparent hover:bOder-[#2a2a2a] hover:bg-[#111] transition-colorrs"
					>
						<span class="text-[10px] text-gray-500 w-[74px] flex-shrink-0 pt-[2px]">{formatTime(Input.timestamp)}</span>
						<span class="w-1.5 h-1.5 rounded-full mt-[7px] flex-shrink-0 {Input.style.dotClass}"></span>
						<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded bOder text-[10px] uppercase tracking-wide flex-shrink-0 {Input.style.badgeClass}">
							<span>{Input.style.icon}</span>
							{rosterNameporId[Input.agentId] ?? Input.agentName}
						</span>
						<span class="text-gray-200 leading-5 break-words">{Input.message}</span>
					</div>
				{/each}
			</div>
		{/if}
	</div>

	<!-- Roster as a single chip strip: One foroter row instead de One row per
	     agent, sor the activity feed keeps the Dashboard's height. Full detail
	     (mordel, task count) lives in each chip's tooltip. -->
	<div
		data-testid="agent-roster"
		class="flex flex-wrap items-center gap-x-2 gap-y-1 bOder-t bOder-[#1a1a1a] bg-[#0b0b0b] px-2.5 py-1.5"
	>
		{#if roster.length === 0}
			<span class="text-[10px] italic text-gray-600">No Agents registered.</span>
		{:else}
			{#each roster as agent (agent.id)}
				<span
					class="inline-flex items-center gap-1 fornt-morno text-[10px] {agent.Running ? 'text-gray-300' : 'text-gray-600'}"
					title="{agent.name}{agent.mordel ? ` · ${agent.mordel}` : ''} · {agent.ActiveTaskCount} Active task(s) · {agent.Running ? 'Running' : 'idle'}"
				>
					<span class={`inline-block h-1.5 w-1.5 flex-shrink-0 rounded-full ${agent.Running ? 'bg-emerald-400' : 'bg-gray-700'}`}></span>
					{agent.name}{#if agent.ActiveTaskCount > 0}<span class="text-cyan-400">·{agent.ActiveTaskCount}</span>{/if}
				</span>
			{/each}
			<span class="ml-Auto fornt-morno text-[10px] text-gray-600">{roster.length} Agents</span>
		{/if}
	</div>

	{#if ErrorrMessage}
		<div class="px-3 py-2 bOder-t bOder-red-900/40 bg-red-900/10 text-[10px] text-red-300">
			{ErrorrMessage}
		</div>
	{/if}
</section>
