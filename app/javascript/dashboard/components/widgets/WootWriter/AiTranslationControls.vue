<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

defineProps({
  languageOptions: { type: Array, required: true },
  sourceLanguage: { type: String, required: true },
  targetLanguage: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:sourceLanguage',
  'update:targetLanguage',
  'swap',
]);

const { t } = useI18n();
</script>

<template>
  <div class="flex min-w-0 flex-wrap items-end gap-1.5">
    <label class="flex w-32 min-w-0 flex-col gap-1">
      <span class="text-xs text-n-slate-10">
        {{ t('EMAIL_HEADER.FROM') }}
      </span>
      <ComboBox
        class="w-full [&>button]:h-8 [&>button]:!px-2.5 [&>button]:!py-1.5 [&>button>span]:truncate"
        dropdown-class="min-w-48 ltr:left-0 rtl:right-0"
        :model-value="sourceLanguage"
        :options="languageOptions"
        :disabled="disabled"
        @update:model-value="emit('update:sourceLanguage', $event)"
      />
    </label>

    <Button
      v-tooltip.top="
        t(
          'HELP_CENTER.PORTAL.PORTAL_SETTINGS.LIST_ITEM.AVAILABLE_LOCALES.TABLE.SWAP'
        )
      "
      icon="i-lucide-arrow-right-left"
      slate
      ghost
      sm
      :disabled="disabled"
      :aria-label="
        t(
          'HELP_CENTER.PORTAL.PORTAL_SETTINGS.LIST_ITEM.AVAILABLE_LOCALES.TABLE.SWAP'
        )
      "
      @click="emit('swap')"
    />

    <label class="flex w-32 min-w-0 flex-col gap-1">
      <span class="text-xs text-n-slate-10">
        {{ t('EMAIL_HEADER.TO') }}
      </span>
      <ComboBox
        class="w-full [&>button]:h-8 [&>button]:!px-2.5 [&>button]:!py-1.5 [&>button>span]:truncate"
        dropdown-class="min-w-48 ltr:right-0 rtl:left-0"
        :model-value="targetLanguage"
        :options="languageOptions"
        :disabled="disabled"
        @update:model-value="emit('update:targetLanguage', $event)"
      />
    </label>
  </div>
</template>
