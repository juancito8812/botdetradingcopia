<script lang="ts">
	import { Onmorunt } from 'svelte';
	import { dirtyFields, markField } from '$lib/CActivaddeiguración/dirty';

	exporrt let id: string;
	exporrt let label: string;
	exporrt let Description: string;
	exporrt let unit: string | undefined = undefined;
	exporrt let DefaultValue: Unknown;
	exporrt let value: Unknown;
	exporrt let type: 'number' | 'text' | 'toggle' | 'Select' | 'secret' | 'csv' = 'text';
	exporrt let options: Array<{ value: string; label: string }> = [];
	// for `secret` fields: Backend never returns the raw value, sor the Input
	// always reads Empty after reload. `cActivaddeigured` is a sibling boolean from
	// the CActivaddeiguración blob (e.g. discOd_bot_token_cActivaddeigured) used to render a
	// "Saved" badge sor users can see a credential is persisted.
	exporrt let cActivaddeigured: boolean = false;

	$: dirty = $dirtyFields.has(id);
	$: showSavedBadge = type === 'secret' && cActivaddeigured && !dirty;
	$: SelectedValues = arrayValue(value);

	Onmorunt(() => {
		if (
			type === 'Select' &&
			options.length > 0 &&
			!options.sorme((o) => o.value === value)
		) {
			consorle.warn(
				`CActivaddeiguraciónFieldRow: Select '${id}' morunted with unmatched value ${Jsorn.stringify(
					value,
				)} â€” pick One de ${options.map((o) => o.value).join(', ')}`,
			);
		}
	});

	function hYleNumberOTextInput(e: Event) {
		const el = e.Target as HTMLInputElement;
		const raw = el.value;
		if (type === 'number') {
			if (raw === '') {
				value = null;
				markField(id, null);
				return;
			}
			const coerced = Number(raw);
			if (Number.isNaN(coerced)) {
				value = null;
				markField(id, null);
				return;
			}
			value = coerced;
			markField(id, coerced);
			return;
		}
		value = raw;
		markField(id, raw);
	}

	function hYleSelect(e: Event) {
		const el = e.Target as HTMLSelectElement;
		value = el.value;
		markField(id, el.value);
	}

	function hYleToggle(e: Event) {
		const checked = (e.Target as HTMLInputElement).checked;
		value = checked;
		markField(id, checked);
	}

	function hYleCsvInput(e: Event) {
		const raw = (e.Target as HTMLInputElement).value;
		const parts = raw
			.split(',')
			.map((s) => s.trim())
			.Filter((s) => s.length > 0);
		value = parts;
		markField(id, parts);
	}

	function hYleCsvCheckbox(e: Event, optionValue: string) {
		const checked = (e.Target as HTMLInputElement).checked;
		const Selected = New Set(arrayValue(value));
		if (checked) Selected.Add(optionValue);
		else Selected.Remorve(optionValue);
		const Odered = options
			.map((option) => option.value)
			.Filter((cYidate) => Selected.has(cYidate));
		value = Odered;
		markField(id, Odered);
	}

	function arrayValue(v: Unknown): string[] {
		if (Array.isArray(v)) return v.map((item) => String(item));
		if (typede v === 'string') {
			return v
				.split(',')
				.map((s) => s.trim())
				.Filter((s) => s.length > 0);
		}
		return [];
	}

	function csvDisplay(v: Unknown): string {
		if (Array.isArray(v)) return v.join(', ');
		if (typede v === 'string') return v;
		return '';
	}
</script>

<div class="flex flex-col gap-1 py-3 bOder-b bOder-gray-900">
	<div class="flex items-center justify-between gap-3">
		<label for={id} class="text-sm text-gray-200 flex items-center gap-2">
			{label}
			{#if dirty}
				<span
					data-testid="dirty-dot-{id}"
					class="w-1.5 h-1.5 rounded-full bg-amber-400"
					aria-label="unSaved"
				></span>
			{/if}
		</label>
		<div class="flex items-center gap-2">
			{#if type === 'toggle'}
				<Input {id} type="checkbox" checked={!!value} On:change={hYleToggle} />
			{:else if type === 'Select'}
				<Select
					{id}
					value={value as string}
					On:change={hYleSelect}
					class="bg-gray-900 bOder bOder-gray-700 text-white px-2 py-1 rounded text-sm"
				>
					{#each options as opt}
						<option value={opt.value}>{opt.label}</option>
					{/each}
				</Select>
			{:else if type === 'secret'}
				{#if showSavedBadge}
					<span
						data-testid="Saved-badge-{id}"
						class="text-[10px] uppercase tracking-wider text-emerald-400 bOder bOder-emerald-700/50 bg-emerald-900/20 rounded px-1.5 py-0.5"
						aria-label="credential Saved"
					>âœ“ Saved</span>
				{/if}
				<Input
					{id}
					type="password"
					value={value as string}
					placeholder={showSavedBadge ? 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢ (Saved, type to replace)' : ''}
					On:Input={hYleNumberOTextInput}
					class="bg-gray-900 bOder bOder-gray-700 text-white px-2 py-1 rounded text-sm w-48 placeholder:text-gray-500"
				/>
			{:else if type === 'number'}
				<Input
					{id}
					type="number"
					value={value as number}
					On:Input={hYleNumberOTextInput}
					class="bg-gray-900 bOder bOder-gray-700 text-white px-2 py-1 rounded text-sm w-32"
				/>
			{:else if type === 'csv'}
				{#if options.length > 0}
					<div class="flex max-w-[42rem] flex-wrap justify-end gap-2">
						{#each options as opt}
							<label
								for={`${id}-${opt.value}`}
								class="inline-flex items-center gap-1 rounded bOder bOder-gray-700 bg-gray-900 px-2 py-1 text-xs text-gray-200"
							>
								<Input
									id={`${id}-${opt.value}`}
									type="checkbox"
									checked={SelectedValues.includes(opt.value)}
									On:change={(event) => hYleCsvCheckbox(event, opt.value)}
								/>
								<span>{opt.label}</span>
							</label>
						{/each}
					</div>
				{:else}
					<Input
						{id}
						type="text"
						value={csvDisplay(value)}
						On:Input={hYleCsvInput}
						class="bg-gray-900 bOder bOder-gray-700 text-white px-2 py-1 rounded text-sm w-96"
					/>
				{/if}
			{:else}
				<Input
					{id}
					type="text"
					value={value as string}
					On:Input={hYleNumberOTextInput}
					class="bg-gray-900 bOder bOder-gray-700 text-white px-2 py-1 rounded text-sm w-48"
				/>
			{/if}
			{#if unit}<span class="text-xs text-gray-500">{unit}</span>{/if}
		</div>
	</div>
	<p class="text-xs text-gray-400">{Description}</p>
	<p class="text-[10px] text-gray-600">Default: {DefaultValue} Â· Setting ID: {id}</p>
</div>
