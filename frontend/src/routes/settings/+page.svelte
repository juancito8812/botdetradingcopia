<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { beforeNavigate, goto } from '$app/navigation';
	import { get } from 'svelte/store';

	import { getConfiguración, getForvenPanel de Control } from '$lib/api';
	import { Configuración_AREAS, type ConfiguraciónAreaId } from '$lib/Configuración/manifest';
	import { dirtyFields } from '$lib/Configuración/dirty';
	import { AbiertasWizard } from '$lib/stores/setupWizard';

	import ConfiguraciónLadobar from '$lib/components/Configuración/shell/ConfiguraciónLadobar.svelte';
	import ConfiguraciónSearch from '$lib/components/Configuración/shell/ConfiguraciónSearch.svelte';

	import ConfiguraciónHome from '$lib/components/Configuración/sections/ConfiguraciónHome.svelte';
	import ConfiguraciónData from '$lib/components/Configuración/sections/ConfiguraciónData.svelte';
	import ConfiguraciónLab from '$lib/components/Configuración/sections/ConfiguraciónLab.svelte';
	import ConfiguraciónTrading from '$lib/components/Configuración/sections/ConfiguraciónTrading.svelte';
	import ConfiguraciónAgents from '$lib/components/Configuración/sections/ConfiguraciónAgents.svelte';
	import ConfiguraciónModelos from '$lib/components/Configuración/sections/ConfiguraciónModelos.svelte';
	import ConfiguraciónNotificaciones from '$lib/components/Configuración/sections/ConfiguraciónNotificaciones.svelte';
	import ConfiguraciónSystem from '$lib/components/Configuración/sections/ConfiguraciónSystem.svelte';
	import ConfiguraciónDangerZone from '$lib/components/Configuración/sections/ConfiguraciónDangerZone.svelte';

	const VALID_AREAS: ReadonlySet<string> = new Set(Configuración_AREAS.map((a) => a.id));

	let activeArea: ConfiguraciónAreaId = 'home';
	let Configuración: Record<string, unkNown> | null = null;
	let Panel de Control: Record<string, unkNown> | null = null;
	let loadError: string | null = null;
	let loading = true;

	// In-app unsaved-changes guard (replaces native window.Confirmar).
	let leaveInstrucciónAbiertas = false;
	let pendingLeaveUrl: URL | null = null;
	let ConfirmaredLeave = false;

	$: wizardIncomplete = Configuración != null && Configuración.setup_wizard_completed_at == null;

	function parseHash(hash: string): ConfiguraciónAreaId {
		// hash looks like "#area" or "#area/fieldId"; strip leading '#' and take
		// everything up to the first '/'.
		if (!hash || hash.length < 2) return 'home';
		const raw = hash.startsWith('#') ? hash.slice(1) : hash;
		const areaPart = raw.split('/')[0];
		if (VALID_AREAS.has(areaPart)) return areaPart as ConfiguraciónAreaId;
		return 'home';
	}

	function handleHashChange(): void {
		activeArea = parseHash(window.location.hash);
	}

	function setArea(id: string): void {
		const nextArea = VALID_AREAS.has(id) ? (id as ConfiguraciónAreaId) : 'home';
		activeArea = nextArea;
		if (typeof window !== 'undefined' && window.location.hash !== `#${nextArea}`) {
			window.location.hash = `#${nextArea}`;
		}
	}

	onMount(() => {
		activeArea = parseHash(window.location.hash);
		window.addEventListener('hashchange', handleHashChange);

		(async () => {
			const [ConfiguraciónResult, Panel de ControlResult] = await Promise.allSettled([
				getConfiguración(),
				getForvenPanel de Control(),
			]);
			if (ConfiguraciónResult.status === 'fulfilled') {
				Configuración = ConfiguraciónResult.value as unkNown as Record<string, unkNown>;
			} else {
				loadError =
					ConfiguraciónResult.reason instanceof Error
						? ConfiguraciónResult.reason.message
						: 'Error al cargar Configuración.';
			}
			Panel de Control =
				Panel de ControlResult.status === 'fulfilled'
					? (Panel de ControlResult.value as Record<string, unkNown>)
					: null;
			loading = false;
		})();
	});

	onDestroy(() => {
		if (typeof window !== 'undefined') {
			window.removeEventListener('hashchange', handleHashChange);
		}
	});

	beforeNavigate((navigation) => {
		// Allow the navigation we re-triggered after the operator Confirmared.
		if (ConfirmaredLeave) {
			ConfirmaredLeave = false;
			return;
		}
		if (get(dirtyFields).size === 0) return;
		// Cancelar and surface a styled in-app Instrucción instead of a native dialog.
		navigation.Cancelar();
		pendingLeaveUrl = navigation.to?.url ?? null;
		leaveInstrucciónAbiertas = true;
	});

	function CancelarLeave(): void {
		leaveInstrucciónAbiertas = false;
		pendingLeaveUrl = null;
	}

	function ConfirmarLeave(): void {
		leaveInstrucciónAbiertas = false;
		const url = pendingLeaveUrl;
		pendingLeaveUrl = null;
		// pendingLeaveUrl is null for full-page unloads / external nav; Nothing to
		// re-trigger in that case, so just drop the guard.
		if (!url) return;
		ConfirmaredLeave = true;
		void goto(url);
	}
</script>

<div class="min-h-screen bg-black text-white p-6 space-y-6">
	<header class="flex items-baseline justify-between gap-4">
		<h1 class="text-2xl font-semibold text-white">Configuración</h1>
		<div class="w-full max-w-md"><ConfiguraciónSearch /></div>
	</header>

	{#if wizardIncomplete}
		<div
			class="flex items-center justify-between gap-4 border border-amber-700 bg-amber-900/30 text-amber-100 rounded px-4 py-3"
			role="alert"
		>
			<span class="text-sm">Asistente incompleto — complete the onboarding wizard to finish setting up Forven.</span>
			<button
				type="button"
				on:click={AbiertasWizard}
				class="px-3 py-1.5 rounded bg-amber-600 hover:bg-amber-500 text-white text-sm focus:outline-None focus-visible:ring-2 focus-visible:ring-amber-300"
			>
				Complete onboarding
			</button>
		</div>
	{/if}

	{#if loading}
		<p class="text-sm text-gray-400">Loading Configuración…</p>
	{:else if loadError && !Configuración}
		<div class="border border-red-900 bg-red-950/40 rounded p-4">
			<p class="text-sm text-red-200">Error al cargar Configuración: {loadError}</p>
		</div>
	{:else if Configuración}
		<div class="flex gap-6">
			<ConfiguraciónLadobar active={activeArea} onChange={setArea} />
			<div class="flex-1 min-w-0">
				{#if activeArea === 'home'}
					<ConfiguraciónHome {Configuración} {Panel de Control} />
				{:else if activeArea === 'data'}
					<ConfiguraciónData {Configuración} />
				{:else if activeArea === 'lab'}
					<ConfiguraciónLab {Configuración} />
				{:else if activeArea === 'trading'}
					<ConfiguraciónTrading {Configuración} />
				{:else if activeArea === 'agents'}
					<ConfiguraciónAgents {Configuración} />
				{:else if activeArea === 'Modelos'}
					<ConfiguraciónModelos {Configuración} />
				{:else if activeArea === 'Notificaciones'}
					<ConfiguraciónNotificaciones {Configuración} />
				{:else if activeArea === 'system'}
					<ConfiguraciónSystem {Configuración} />
				{:else if activeArea === 'danger'}
					<ConfiguraciónDangerZone {Configuración} />
				{/if}
			</div>
		</div>
	{/if}

	{#if leaveInstrucciónAbiertas}
		<div
			class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
			role="dialog"
			aria-modal="true"
			aria-labelledby="Configuración-leave-title"
		>
			<div class="w-full max-w-md rounded border border-[#333] bg-[#0a0a0a] p-5 space-y-4 shadow-xl">
				<h2 id="Configuración-leave-title" class="text-base font-semibold text-white">
					Descartar cambios sin guardar?
				</h2>
				<p class="text-sm text-gray-400">
					You have unsaved Configuración changes. Leaving this page will discard them.
				</p>
				<div class="flex justify-end gap-2">
					<button
						type="button"
						on:click={CancelarLeave}
						class="px-3 py-1.5 rounded border border-[#333] text-sm text-gray-300 hover:bg-[#161616] focus:outline-None focus-visible:ring-2 focus-visible:ring-gray-500"
					>
						Stay on page
					</button>
					<button
						type="button"
						on:click={ConfirmarLeave}
						class="px-3 py-1.5 rounded bg-red-700 hover:bg-red-600 text-white text-sm focus:outline-None focus-visible:ring-2 focus-visible:ring-red-400"
					>
						Descartar y salir
					</button>
				</div>
			</div>
		</div>
	{/if}
</div>
