import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import aiTranslationAPI from 'dashboard/api/aiTranslation';
import { useConfig } from 'dashboard/composables/useConfig';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { LocalStorage } from 'shared/helpers/localStorage';

export function useAiTranslation() {
  const { t } = useI18n();
  const { aiTranslateEnabled, enabledLanguages } = useConfig();
  const storedLanguagePreferences =
    LocalStorage.get(LOCAL_STORAGE_KEYS.AI_TRANSLATION_LANGUAGES) || {};

  const sourceTranslationLanguage = ref(
    storedLanguagePreferences.sourceLang || 'zh'
  );
  const targetTranslationLanguage = ref(
    storedLanguagePreferences.targetLang || 'en'
  );
  const translatedContent = ref('');
  const translationError = ref('');
  const isTranslating = ref(false);
  const translationRequestId = ref(0);

  const translationLanguageOptions = computed(() => {
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

  const sourceTranslationLanguageLabel = computed(
    () =>
      translationLanguageOptions.value.find(
        language => language.value === sourceTranslationLanguage.value
      )?.label || sourceTranslationLanguage.value
  );

  const targetTranslationLanguageLabel = computed(
    () =>
      translationLanguageOptions.value.find(
        language => language.value === targetTranslationLanguage.value
      )?.label || targetTranslationLanguage.value
  );

  const translationActionLabel = computed(() =>
    t('CONVERSATION.CONTEXT_MENU.TRANSLATE')
  );
  const retranslationActionLabel = computed(() =>
    t('CONVERSATION.CONTEXT_MENU.RETRANSLATE')
  );

  const translationTooltip = computed(() => {
    if (aiTranslateEnabled) {
      return translationActionLabel.value;
    }

    return t('AI_TRANSLATION.CONFIGURATION_REQUIRED');
  });

  const resetTranslationResult = () => {
    translatedContent.value = '';
    translationError.value = '';
  };

  const invalidateTranslation = () => {
    translationRequestId.value += 1;
    isTranslating.value = false;
    resetTranslationResult();
  };

  const canTranslate = content =>
    aiTranslateEnabled &&
    Boolean(content.trim()) &&
    sourceTranslationLanguage.value &&
    targetTranslationLanguage.value &&
    sourceTranslationLanguage.value !== targetTranslationLanguage.value &&
    !isTranslating.value;

  const swapTranslationLanguages = () => {
    [sourceTranslationLanguage.value, targetTranslationLanguage.value] = [
      targetTranslationLanguage.value,
      sourceTranslationLanguage.value,
    ];
  };

  const translateContent = async content => {
    if (!canTranslate(content)) return;

    translationRequestId.value += 1;
    const requestId = translationRequestId.value;
    isTranslating.value = true;
    translationError.value = '';
    translatedContent.value = '';

    try {
      const { data } = await aiTranslationAPI.translate({
        content,
        sourceLang: sourceTranslationLanguage.value,
        targetLang: targetTranslationLanguage.value,
      });
      if (requestId !== translationRequestId.value) return;

      translatedContent.value = data.result;
    } catch {
      if (requestId !== translationRequestId.value) return;

      translationError.value = t('CAPTAIN.COPILOT.EMPTY_MESSAGE');
    } finally {
      if (requestId === translationRequestId.value) {
        isTranslating.value = false;
      }
    }
  };

  watch(
    [sourceTranslationLanguage, targetTranslationLanguage],
    ([sourceLang, targetLang]) => {
      invalidateTranslation();
      if (!sourceLang || !targetLang) return;

      LocalStorage.set(LOCAL_STORAGE_KEYS.AI_TRANSLATION_LANGUAGES, {
        sourceLang,
        targetLang,
      });
    }
  );

  return {
    aiTranslateEnabled,
    sourceTranslationLanguage,
    sourceTranslationLanguageLabel,
    targetTranslationLanguage,
    targetTranslationLanguageLabel,
    translatedContent,
    translationError,
    translationLanguageOptions,
    translationActionLabel,
    retranslationActionLabel,
    translationTooltip,
    isTranslating,
    canTranslate,
    invalidateTranslation,
    swapTranslationLanguages,
    translateContent,
  };
}
