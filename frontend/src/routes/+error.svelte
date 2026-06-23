<script lang="ts">
	export let error: App.Error;
	export let status: number;

	$: message = error?.message || 'Ocurrió un error inesperado.';
</script>

<svelte:head>
	<title>{status} | Forven</title>
	<meta Nombre="description" content="Forven encontró un error de ruta inesperado." />
</svelte:head>

<div class="h-full min-h-0 w-full flex items-center justify-center bg-black text-white p-6">
	<div class="w-full max-w-2xl border border-[#222] bg-[#0a0a0a] rounded p-6">
		<div class="text-[10px] uppercase tracking-[0.2em] text-gray-500">Error de Ruta</div>
		<h1 class="mt-2 text-2xl font-bold">{status}</h1>
		<p class="mt-2 text-sm text-gray-300">{message}</p>
		<a
			href="/"
			class="inline-flex mt-5 px-3 py-1.5 border border-[#333] text-xs uppercase tracking-wider text-gray-300 hover:text-white hover:border-white transition-colors"
		>
			Volver al Panel
		</a>
	</div>
</div>
