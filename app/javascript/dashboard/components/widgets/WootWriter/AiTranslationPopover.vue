<script setup>
import { computed, ref, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import aiTranslationAPI from 'dashboard/api/aiTranslation';
import { useConfig } from 'dashboard/composables/useConfig';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { LocalStorage } from 'shared/helpers/localStorage';

const props = defineProps({
  content: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();
const { aiTranslateEnabled, enabledLanguages } = useConfig();
const storedLanguagePreferences =
  LocalStorage.get(LOCAL_STORAGE_KEYS.AI_TRANSLATION_LANGUAGES) || {};

const isOpen = ref(false);
const isTranslating = ref(false);
const sourceLang = ref(storedLanguagePreferences.sourceLang || 'zh');
const targetLang = ref(storedLanguagePreferences.targetLang || 'en');
const translatedContent = ref('');
const errorMessage = ref('');
const translationRequestId = ref(0);

const languageOptions = computed(() => {
  const languages = new Map([
    ['zh', { value: 'zh', label: '中文 (zh)' }],
    ['en', { value: 'en', label: 'English (en)' }],
  ]);

  (enabledLanguages || []).forEach(language => {
    const code = language.iso_639_1_code.split(/[_-]/)[0].toLowerCase();
    if (languages.has(code)) return;

    const name = language.name.replace(/\s*\([^)]*\)\s*$/, '').trim();
    languages.set(code, { value: code, label: `${name} (${code})` });
  });

  return [...languages.values()];
});

const canTranslate = computed(
  () =>
    Boolean(props.content.trim()) &&
    sourceLang.value &&
    targetLang.value &&
    sourceLang.value !== targetLang.value &&
    !isTranslating.value
);

const isButtonDisabled = computed(() => props.disabled || !aiTranslateEnabled);

const buttonTooltip = computed(() => {
  if (aiTranslateEnabled) {
    return t('CONVERSATION.CONTEXT_MENU.TRANSLATE');
  }

  return `${t(
    'INTEGRATION_SETTINGS.WEBHOOK.CONFIGURE'
  )} ENV: AI_TRANSLATE_API_BASE_URL, AI_TRANSLATE_CLIENT_ID, AI_TRANSLATE_CLIENT_SECRET`;
});

const resetResult = () => {
  translatedContent.value = '';
  errorMessage.value = '';
};

const invalidateTranslation = () => {
  translationRequestId.value += 1;
  isTranslating.value = false;
  resetResult();
};

const closePopover = () => {
  isOpen.value = false;
  invalidateTranslation();
};

const togglePopover = () => {
  if (isButtonDisabled.value) return;
  if (isOpen.value) {
    closePopover();
    return;
  }

  isOpen.value = true;
};

const swapLanguages = () => {
  [sourceLang.value, targetLang.value] = [targetLang.value, sourceLang.value];
  resetResult();
};

const translate = async () => {
  if (!canTranslate.value) return;

  translationRequestId.value += 1;
  const requestId = translationRequestId.value;
  const content = props.content;
  isTranslating.value = true;
  errorMessage.value = '';
  translatedContent.value = '';

  try {
    const { data } = await aiTranslationAPI.translate({
      content,
      sourceLang: sourceLang.value,
      targetLang: targetLang.value,
    });
    if (
      requestId !== translationRequestId.value ||
      content !== props.content ||
      !isOpen.value
    ) {
      return;
    }
    translatedContent.value = data.result;
  } catch {
    if (requestId !== translationRequestId.value) return;
    errorMessage.value = t('CAPTAIN.COPILOT.EMPTY_MESSAGE');
  } finally {
    if (requestId === translationRequestId.value) {
      isTranslating.value = false;
    }
  }
};

const applyTranslation = () => {
  emit('apply', translatedContent.value);
  closePopover();
};

watch(
  () => props.content,
  () => invalidateTranslation()
);

watch([sourceLang, targetLang], ([newSourceLang, newTargetLang]) => {
  if (!newSourceLang || !newTargetLang) return;

  LocalStorage.set(LOCAL_STORAGE_KEYS.AI_TRANSLATION_LANGUAGES, {
    sourceLang: newSourceLang,
    targetLang: newTargetLang,
  });
});
</script>

<template>
  <OnClickOutside @trigger="closePopover">
    <div v-tooltip.top-end="buttonTooltip" class="relative flex">
      <Button
        icon="i-lucide-languages"
        slate
        :variant="isOpen ? 'solid' : 'faded'"
        sm
        :disabled="isButtonDisabled"
        :aria-expanded="isOpen"
        @click="togglePopover"
      />

      <div
        v-if="isOpen"
        class="absolute bottom-10 left-0 z-40 flex w-[30rem] max-w-[calc(100vw-3rem)] flex-col gap-4 rounded-lg border border-n-strong bg-n-solid-1 p-4 shadow-xl"
        role="dialog"
        :aria-label="t('CONVERSATION.CONTEXT_MENU.TRANSLATE')"
      >
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION.CONTEXT_MENU.TRANSLATE') }}
          </h3>
          <Button
            v-tooltip.top="t('GENERAL.CLOSE')"
            icon="i-lucide-x"
            slate
            ghost
            xs
            @click="closePopover"
          />
        </div>

        <div
          class="grid grid-cols-1 items-end gap-2 sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)]"
        >
          <div class="flex min-w-0 flex-col gap-1.5 text-xs text-n-slate-11">
            <span>{{ t('EMAIL_HEADER.FROM') }}</span>
            <ComboBox
              v-model="sourceLang"
              :options="languageOptions"
              :disabled="isTranslating"
              dropdown-placement="top"
              @update:model-value="resetResult"
            />
          </div>

          <Button
            v-tooltip.top="
              t(
                'HELP_CENTER.PORTAL.PORTAL_SETTINGS.LIST_ITEM.AVAILABLE_LOCALES.TABLE.SWAP'
              )
            "
            icon="i-lucide-arrow-right-left"
            slate
            outline
            sm
            class="justify-self-center rotate-90 sm:rotate-0"
            :disabled="isTranslating"
            @click="swapLanguages"
          />

          <div class="flex min-w-0 flex-col gap-1.5 text-xs text-n-slate-11">
            <span>{{ t('EMAIL_HEADER.TO') }}</span>
            <ComboBox
              v-model="targetLang"
              :options="languageOptions"
              :disabled="isTranslating"
              dropdown-placement="top"
              @update:model-value="resetResult"
            />
          </div>
        </div>

        <div
          v-if="translatedContent"
          class="max-h-40 overflow-y-auto whitespace-pre-wrap break-words rounded-md bg-n-alpha-2 p-3 text-sm leading-5 text-n-slate-12"
        >
          {{ translatedContent }}
        </div>

        <div
          v-if="errorMessage"
          class="flex items-center gap-2 text-sm text-n-ruby-11"
          role="alert"
        >
          <Icon icon="i-lucide-circle-alert" class="size-4 shrink-0" />
          <span>{{ errorMessage }}</span>
        </div>

        <div class="flex justify-end gap-2">
          <Button
            v-if="translatedContent"
            :label="t('CONVERSATION.CONTEXT_MENU.TRANSLATE')"
            slate
            outline
            sm
            :disabled="isTranslating"
            @click="translate"
          />
          <Button
            v-if="translatedContent"
            :label="t('CAPTAIN.COPILOT.USE')"
            blue
            sm
            @click="applyTranslation"
          />
          <Button
            v-else
            :label="t('CONVERSATION.CONTEXT_MENU.TRANSLATE')"
            blue
            sm
            :is-loading="isTranslating"
            :disabled="!canTranslate"
            @click="translate"
          />
        </div>
      </div>
    </div>
  </OnClickOutside>
</template>
