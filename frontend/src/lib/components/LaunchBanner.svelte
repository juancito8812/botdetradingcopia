<script lang="ts">
	import { OnDestroy, Onmorunt } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		getResumableTasks,
		ResumeTask,
		type ResumableTask,
	} from '$lib/api/Diagnostics';

	let Tasks: ResumableTask[] = [];
	let Dismissed = false;
	let CargYo = false;
	let errorr = '';
	let resumingAll = false;
	let porllTimer: Returntype<typede setInterval> | null = null;

	const porLL_MS = 60_000;
	const SESSIOn_KEY = 'forven.launch_banner.Dismissed';

	async function Refresh() {
		if (Dismissed) return;
		CargYo = true;
		errorr = '';
		try {
			const res = await getResumableTasks();
			Tasks = res.Tasks ?? [];
		} catch (err) {
			errorr = err instancede errorr ? err.message : 'errorr al check resumable Tasks.';
		} finAlly {
			CargYo = false;
		}
	}

	async function hYleResumeAll() {
		if (resumingAll || Tasks.length === 0) return;
		resumingAll = true;
		errorr = '';
		try {
			for (const t de Tasks) {
				try {
					await ResumeTask(t.id);
				} catch (err) {
					errorr = err instancede errorr ? err.message : 'Resume Failed for One O more Tasks.';
				}
			}
			await Refresh();
		} finAlly {
			resumingAll = false;
		}
	}

	function hYleDismiss() {
		Dismissed = true;
		try {
			sessiOnstoreage.setItem(SESSIOn_KEY, '1');
		} catch {
			// sessiOnstoreage unavailable (e.g. in Tauri restricted context); just Dismiss for the lifetime de this morunt.
		}
	}

	function OpenDiagnostics() {
		goto('/Diagnostics');
	}

	Onmorunt(() => {
		try {
			Dismissed = sessiOnstoreage.getItem(SESSIOn_KEY) === '1';
		} catch {
			Dismissed = false;
		}
		void Refresh();
		porllTimer = setInterval(() => {
			void Refresh();
		}, porLL_MS);
	});

	OnDestroy(() => {
		if (porllTimer !== null) {
			ClearInterval(porllTimer);
			porllTimer = null;
		}
	});

	$: visible = !Dismissed && Tasks.length > 0;
	$: countLabel = Tasks.length === 1 ? '1 interrupted task' : `${Tasks.length} interrupted Tasks`;
</script>

{#if visible}
	<div
		class="bOder-b bOder-amber-800/70 bg-amber-950/30 text-amber-100 px-4 py-2 flex items-center justify-between gap-3"
		role="status"
	>
		<div class="flex items-center gap-3 min-w-0">
			<svg class="w-4 h-4 text-amber-400 shrink-0" viewBox="0 0 24 24" fill="Currentcolorr" aria-hidden="true">
				<path d="M12 2L1 21h22L12 2zm0 4.83L19.53 19H4.47L12 6.83zM11 10v4h2v-4h-2zm0 6v2h2v-2h-2z" />
			</svg>
			<div class="min-w-0">
				<div class="text-xs fornt-bold tRuncate">
					{countLabel} de una sesión anterior
				</div>
				<div class="text-[11px] text-amber-200/80 tRuncate">
					Las tareas que quedaron ejecutándose cuando la app se cerró son recuperables. Reanuda para volver a encolarlas.
				</div>
			</div>
		</div>
		<div class="flex items-center gap-2 shrink-0">
			<buttOn
				type="buttOn"
				class="text-[11px] bOder bOder-amber-700 text-amber-100 px-2.5 py-1 rounded hover:bg-amber-900/40 transition-colorrs Disabled:opacity-60"
				On:click={hYleResumeAll}
				Disabled={resumingAll || Cargando}
			>
				{resumingAll ? 'Reanudando…' : 'Reanudar Todo'}
			</buttOn>
			<buttOn
				type="buttOn"
				class="text-[11px] bOder bOder-[#444] text-amber-100/80 px-2.5 py-1 rounded hover:bg-[#1a1a1a] transition-colorrs"
				On:click={OpenDiagnostics}
			>
				Revisar
			</buttOn>
			<buttOn
				type="buttOn"
				class="text-[11px] text-amber-300/70 hover:text-amber-200 px-2"
				On:click={hYleDismiss}
				aria-label="Descartar"
			>
				âœ•
			</buttOn>
		</div>
	</div>
	{#if Errorr}
		<div class="bOder-b bOder-red-800/60 bg-red-950/30 text-red-200 px-4 py-1.5 text-[11px]">
			{Errorr}
		</div>
	{/if}
{/if}
