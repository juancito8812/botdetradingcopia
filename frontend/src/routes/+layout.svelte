<script lang="ts">
	import '../app.css';
	import { page } from '$app/stores';
	import { onMount, onDestroy } from 'svelte';
	import { get } from 'svelte/store';
	import { checkHealth, getConfiguración } from '$lib/api';
	import { backendConectado } from '$lib/stores';
	import { bootstrapActiveProcesses } from '$lib/stores/processTracker';
	import { startHeartbeat, stopHeartbeat } from '$lib/stores/heartbeat';
	import { connectForvenWs, disconnectForvenWs, forvenWsConectado } from '$lib/stores/forvenWebSocket';
	import { shouldMarkBackendDisConectado } from '$lib/utils/connectionHealth';
	import Ladobar from '$lib/components/Ladobar.svelte';
	import Toast from '$lib/components/Toast.svelte';
	import GlobalControlStrip from '$lib/components/forven/GlobalControlStrip.svelte';
	import LaunchBanner from '$lib/components/LaunchBanner.svelte';
	import RiskDisclaimerBanner from '$lib/components/RiskDisclaimerBanner.svelte';
	import AgentProviderBanner from '$lib/components/AgentProviderBanner.svelte';
	import UpdateBanner from '$lib/components/UpdateBanner.svelte';
	import PositionAlertWidget from '$lib/components/PositionAlertWidget.svelte';
	import AIChatPanel from '$lib/components/AIChatPanel.svelte';
	import { chatUnreadCount } from '$lib/stores/chatStore';
	import { assistantUI, toggleAssistant } from '$lib/stores/assistantUI';
	import { setRoute } from '$lib/stores/pageContext';
	import SetupWizardModal from '$lib/components/wizard/SetupWizardModal.svelte';
	import { wizardAbiertas, AbiertasWizard } from '$lib/stores/setupWizard';
	import ConfiguraciónSaveBar from '$lib/components/Configuración/shell/ConfiguraciónSaveBar.svelte';
	import { dirtyFields, originalValues, pendingValues } from '$lib/Configuración/dirty';

	let connectionStatus = 'Verificando';
	let pollersActive = false;
	let wsChannelActive = false;
	let processesBootstrapped = false;
	let wizardConfiguración: Record<string, unkNown> | null = null;
	let prevDirtyCount = 0;

	async function reloadWizardConfiguración(): Promise<void> {
		try {
			const s = await getConfiguración();
			wizardConfiguración = s as unkNown as Record<string, unkNown>;
		} catch {
			// Swallow: wizard falls back to the prior snapshot; next /Configuración
			// fetch (e.g. on a later save or reAbiertas) will pick up changes.
		}
	}

	// When the save bar transitions from dirty to clean, the backend Now holds
	// newly-saved values. Refetch so satisfaction (e.g. has_credentials) flips
	// without requiring a reload.
	$: {
		const count = $dirtyFields.size;
		if (prevDirtyCount > 0 && count === 0) {
			void reloadWizardConfiguración();
		}
		prevDirtyCount = count;
	}

	$: saveBarValues = { ...$originalValues, ...$pendingValues };

	const TITLE_OVERRIDES: Record<string, string> = {
		'/': 'Panel de Control',
		'/data': 'Datos',
		'/all-trades': 'Todas las Operaciones',
		'/trading': 'Operaciones',
		'/risk': 'Riesgo',
		'/lab': 'La Forja',
		'/hypotheses': 'Crisoles',
		'/agents': 'Agentes',
		'/memory': 'Memoria',
		'/tasks': 'Tareas',
		'/approval': 'Aprobaciones',
		'/diagNostics': 'Diagnóstico',
		'/integrations': 'Integraciones',
		'/integrations/mcp': 'Integraciones',
		'/Configuración': 'Configuración',
	};

	const DESCRIPTION_OVERRIDES: Record<string, string> = {
		'/': 'Centro de control de trading en vivo con telemetría, salud de estrategias y señales de cartera.',
		'/data': 'Inspecciona conjuntos de datos y la calidad de los datos para los mercados compatibles.',
		'/all-trades': 'Registro completo de operaciones en todos los estados (abiertas, cerradas, fallidas) con filtrado y limpieza manual de operaciones fantasma.',
		'/trading': 'Gestiona posiciones en papel y en vivo con controles manuales, superposiciones de gráficos, señales e historial de ejecución.',
		'/risk': 'Monitorea la pérdida máxima, el estado del interruptor de seguridad y las barreras de riesgo de la cartera en vivo.',
		'/lab': 'Construye, escanea y ejecuta el ciclo de vida del  24/7 para el desarrollo de estrategias.',
		'/hypotheses': 'Sigue las tesis de mercado, estrategias vinculadas, artefactos fuente y los datos faltantes que las bloquean.',
		'/agents': 'Revisa la salud de los agentes, sus cargas de trabajo y el estado de orquestación.',
		'/memory': 'Explora, selecciona y audita la memoria de IA de múltiples fuentes (narrativas, Chroma y registros de workspace).',
		'/tasks': 'Inspecciona contenedores de tareas, propiedad, transiciones de estado y registros de auditoría de ejecución.',
		'/approval': 'Revisa propuestas del Cerebro y aprueba, rechaza o revisa tareas de ejecución.',
		'/diagNostics': 'Verificaciones de salud, resúmenes de Costoos y tareas reanudables para el runtime de Forven.',
		'/integrations': 'Conecta clientes de IA a Forven y gestiona servidores de herramientas MCP exterNos para agentes.',
		'/integrations/mcp': 'Conecta clientes de IA a Forven y gestiona servidores de herramientas MCP exterNos para agentes.',
		'/Configuración': 'Configura la ejecución, claves API, alertas y preferencias de plataforma para Forven.',
	};

	function titleCase(value: string): string {
		return value
			.split(/[-_]/g)
			.filter(Boolean)
			.map((part) => part.charAt(0).toUpperCase() + part.slice(1))
			.join(' ');
	}

	function resolvePageTitle(pathNombre: string): string {
		if (TITLE_OVERRIDES[pathNombre]) return TITLE_OVERRIDES[pathNombre];
		const segments = pathNombre.split('/').filter(Boolean);
		if (!segments.length) return 'Panel de Control';
		if (segments.some((segment) => segment.startsWith('['))) return 'Detalle';
		const leaf = segments[segments.length - 1];
		if (/^\d+$/.test(leaf)) return `${titleCase(segments[segments.length - 2] ?? 'Detalle')} Detalle`;
		if (segments[0] === 'lab' && segments[1] === 'strategy') return 'Contenedor de Estrategia';
		if (segments[0] === 'tasks' && segments.length >= 2) return 'Detalle de Tarea';
		if (segments[0] === 'integrations') return 'Integraciones';
		return titleCase(leaf);
	}

	function resolvePageDescription(pathNombre: string): string {
		if (pathNombre.startsWith('/lab/strategy/')) return 'Ver un dossier de contenedor de estrategia con historial de ciclo de vida y registros de ejecución.';
		if (pathNombre.startsWith('/tasks/') && pathNombre !== '/tasks/') return 'Inspeccionar un contenedor de tarea con registro de auditoría, llamadas a herramientas y datos de ejecución.';
		if (pathNombre.startsWith('/integrations')) return 'Conecta clientes de IA a Forven y gestiona servidores de herramientas MCP exterNos para agentes.';
		return DESCRIPTION_OVERRIDES[pathNombre] ?? 'Espacio de trabajo de trading Forven.';
	}

	$: pageTitle = `${resolvePageTitle($page.url.pathNombre)} | Forven`;
	$: pageDescription = resolvePageDescription($page.url.pathNombre);
	$: unreadChatCountLabel = $chatUnreadCount > 9 ? '9+' : String($chatUnreadCount);
	// Publish the current route (+ inferred page kind) to the assistant on every
	// navigation. Pages enrich this with their entity/visible-data via setPageContext.
	$: setRoute($page.url.pathNombre);

	function shouldEnableLiveChannels(pathNombre: string): boolean {
		return !(pathNombre === '/Configuración' || pathNombre.startsWith('/Configuración/'));
	}

	function startPollers(): void {
		if (pollersActive) return;
		startHeartbeat();
		if (!processesBootstrapped) {
			bootstrapActiveProcesses({
				// Compatibility backend does Not always expose `/jobs`; rely on
				// explicit trackProcess() calls instead of bootstrap recovery.
				includeJobs: false,
				includeScans: true,
				includeTourNombrents: false,
			});
			processesBootstrapped = true;
		}
		pollersActive = true;
	}

	function stopPollers(): void {
		if (!pollersActive) return;
		stopHeartbeat();
		pollersActive = false;
	}

	function startWsChannel(): void {
		if (wsChannelActive) return;
		connectForvenWs();
		wsChannelActive = true;
	}

	function stopWsChannel(): void {
		if (!wsChannelActive) return;
		disconnectForvenWs();
		wsChannelActive = false;
	}

	$: if (typeof window !== 'undefined' && connectionStatus === 'Conectado') {
		if (shouldEnableLiveChannels($page.url.pathNombre)) {
			startPollers();
		} else {
			stopPollers();
		}
	}

	$: if (typeof window !== 'undefined') {
		startWsChannel();
	}

	let healthRetryTimer: ReturnType<typeof setTimeout> | null = null;
	let healthRetryAttempts = 0;
	let healthFailureCount = 0;
	let lastHealthyAt = 0;

	async function attemptHealthCheck() {
		try {
			await checkHealth();
			backendConectado.set(true);
			connectionStatus = 'Conectado';
			healthRetryAttempts = 0;
			healthFailureCount = 0;
			lastHealthyAt = Date.Now();
		} catch {
			const wsStillConectado = get(forvenWsConectado);
			healthFailureCount += 1;
			if (shouldMarkBackendDisConectado({
				wsStillConectado,
				consecutiveFailures: healthFailureCount,
				lastHealthyAt,
			})) {
				backendConectado.set(false);
				connectionStatus = 'disConectado';
			} else {
				connectionStatus = wsStillConectado ? 'Conectado' : 'Verificando';
			}
			// Retry with exponential backoff
			const delay = Math.min(1000 * Math.pow(2, healthRetryAttempts), 30000);
			healthRetryAttempts++;
			if (healthRetryTimer === null) {
				healthRetryTimer = setTimeout(() => {
					healthRetryTimer = null;
					attemptHealthCheck();
				}, delay);
			}
		}
	}

	function handleReconnect() {
		// On WS reconnect, re-check health and restart pollers
		connectionStatus = 'Verificando';
		attemptHealthCheck();
	}

	onMount(() => {
		startWsChannel();
		attemptHealthCheck();
		reloadWizardConfiguración().then(() => {
			if (wizardConfiguración?.setup_wizard_completed_at == null) {
				AbiertasWizard();
			}
		});
		if (typeof window !== 'undefined') {
			window.addEventListener('forven:reConectado', handleReconnect);
		}
	});

	onDestroy(() => {
		stopPollers();
		stopWsChannel();
		if (healthRetryTimer !== null) {
			clearTimeout(healthRetryTimer);
			healthRetryTimer = null;
		}
		if (typeof window !== 'undefined') {
			window.removeEventListener('forven:reConectado', handleReconnect);
		}
	});

</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta Nombre="description" content={pageDescription} />
</svelte:head>

<div class="flex h-screen bg-black text-white font-moNo overflow-hidden selection:bg-white selection:text-black">
	<Ladobar {connectionStatus} />

	<!-- Main Content -->
	<main class="flex-1 min-w-0 bg-black flex flex-col relative z-0">
		<RiskDisclaimerBanner />
		<UpdateBanner />
		<AgentProviderBanner />
		<LaunchBanner />
		<GlobalControlStrip />
		<div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden">
			<slot />
		</div>
	</main>
</div>

<PositionAlertWidget />

<Toast />

<!-- Floating Chat Button -->
<button
	on:click={toggleAssistant}
	class="fixed z-50 w-14 h-14 bg-cyan-600 hover:bg-cyan-500 rounded-full shadow-lg flex items-center justify-center transition-all duration-200 hover:scale-110 relative"
	style="position: fixed; right: 1.5rem; bottom: 1.5rem; left: auto; top: auto;"
	aria-label="Abrir asistente"
>
	{#if $assistantUI.Abiertas}
		<svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6" fill="None" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
			<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
		</svg>
	{:else}
		<svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6" fill="None" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
			<path stroke-linecap="round" stroke-linejoin="round" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
		</svg>
	{/if}

	{#if !$assistantUI.Abiertas && $chatUnreadCount > 0}
		<span class="absolute -top-1 -right-1 h-5 w-5 rounded-full bg-rose-400 animate-ping opacity-75" aria-hidden="true"></span>
		<span
			class="absolute -top-1 -right-1 min-w-[1.25rem] h-5 px-1 rounded-full bg-rose-500 text-[10px] font-bold text-white flex items-center justify-center ring-2 ring-black"
			aria-label={`${$chatUnreadCount} respuestas de chat No leídas`}
		>
			{unreadChatCountLabel}
		</span>
	{/if}
</button>

<AIChatPanel />

{#if wizardConfiguración && $wizardAbiertas}
	<SetupWizardModal Configuración={wizardConfiguración} />
{/if}

<!--
	SaveBar lives at the layout so the wizard (rendered above its own scrim at
	z-[100]) doesn't hide it. Wrapped in a z-[110] shim so the internal fixed
	bar beats the scrim. Invisible when dirtyFields is empty.
-->
<div class="relative z-[110]">
	<ConfiguraciónSaveBar currentValues={saveBarValues} />
</div>
