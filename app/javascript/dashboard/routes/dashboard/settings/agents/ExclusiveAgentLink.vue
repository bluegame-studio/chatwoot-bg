<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
  inboxError: {
    type: Boolean,
    default: false,
  },
});

const exclusiveLink = defineModel('exclusiveLink', {
  type: String,
  default: '',
  set: value => (value || '').trim().replace(/^https?:\/\//i, ''),
});

const selectedInboxId = defineModel('selectedInboxId', {
  type: [String, Number],
  default: '',
});

const DEFAULT_EXCLUSIVE_LINK_DOMAIN = 'example.com';

const store = useStore();
const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');
const websiteInboxes = useMapGetter('inboxes/getWebsiteInboxes');
const eligibleWebsiteInboxes = ref([]);
const isLoadingEligibleInboxes = ref(true);
const fullExclusiveLink = computed(() =>
  exclusiveLink.value ? `https://${exclusiveLink.value}` : ''
);

const inboxOptions = computed(() =>
  eligibleWebsiteInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);

const selectedInboxDomain = computed(() => {
  const selectedInbox = eligibleWebsiteInboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  );

  return selectedInbox?.website_url
    ?.trim()
    .replace(/^https?:\/\//i, '')
    .split('/')[0];
});

const hasEligibleInboxes = computed(() => inboxOptions.value.length > 0);

watch(selectedInboxDomain, domain => {
  if (!domain) return;

  const currentExclusiveLink = exclusiveLink.value || '';
  const exclusivePathIndex = currentExclusiveLink.indexOf('/exclusive/');
  const exclusivePath =
    exclusivePathIndex >= 0
      ? currentExclusiveLink.slice(exclusivePathIndex)
      : '';

  exclusiveLink.value = `${domain}${exclusivePath}`;
});

const generateToken = () => {
  const characters =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const randomValues = new Uint32Array(8);
  window.crypto.getRandomValues(randomValues);

  return Array.from(
    randomValues,
    value => characters[value % characters.length]
  ).join('');
};

const regenerateExclusiveLink = () => {
  const domain = selectedInboxDomain.value || DEFAULT_EXCLUSIVE_LINK_DOMAIN;
  exclusiveLink.value = `${domain}/exclusive/${generateToken()}`;
};

const copyExclusiveLink = async () => {
  try {
    await copyTextToClipboard(fullExclusiveLink.value);
    useAlert(t('AGENT_MGMT.EXCLUSIVE_LINK.COPY_SUCCESS'));
  } catch {
    useAlert(t('AGENT_MGMT.EXCLUSIVE_LINK.COPY_ERROR'));
  }
};

const fetchEligibleWebsiteInboxes = async () => {
  try {
    if (!inboxes.value.length) {
      await store.dispatch('inboxes/get');
    }

    const membershipResponses = await Promise.all(
      websiteInboxes.value.map(inbox =>
        store.dispatch('inboxMembers/get', { inboxId: inbox.id })
      )
    );

    eligibleWebsiteInboxes.value = websiteInboxes.value.filter((_, index) =>
      membershipResponses[index]?.data?.payload?.some(
        member => member.id === props.agentId
      )
    );
  } catch {
    eligibleWebsiteInboxes.value = [];
  } finally {
    isLoadingEligibleInboxes.value = false;
  }
};

onMounted(fetchEligibleWebsiteInboxes);
</script>

<template>
  <div class="w-full pt-5 mt-2 border-t border-n-weak">
    <div class="flex items-center gap-2 mb-4">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.TITLE') }}
      </span>
      <span
        class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-brand/10 text-n-blue-11"
      >
        {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.BADGE') }}
      </span>
    </div>

    <label for="exclusive-agent-link">
      {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.LABEL') }}
    </label>
    <div class="flex flex-col gap-2 mt-1 sm:flex-row">
      <div
        class="flex items-center flex-1 h-10 min-w-0 gap-1 px-3 overflow-hidden transition-all duration-200 outline outline-1 outline-n-weak outline-offset-[-1px] rounded-lg bg-n-alpha-black2 hover:outline-n-slate-6 focus-within:outline-n-brand"
      >
        <span class="shrink-0 text-sm text-n-slate-9 select-none">
          {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.PROTOCOL') }}
        </span>
        <input
          id="exclusive-agent-link"
          v-model="exclusiveLink"
          class="flex-1 min-w-0 h-full reset-base !p-0 !m-0 !text-sm !leading-5 !border-0 !rounded-none !outline-none !bg-transparent !shadow-none focus:!border-0 focus:!outline-none focus:!ring-0"
          type="text"
          :placeholder="$t('AGENT_MGMT.EXCLUSIVE_LINK.PLACEHOLDER')"
        />
      </div>
      <div class="flex gap-2">
        <Button
          outline
          slate
          type="button"
          icon="i-lucide-copy"
          :disabled="!exclusiveLink"
          :label="$t('AGENT_MGMT.EXCLUSIVE_LINK.COPY')"
          @click="copyExclusiveLink"
        />
        <Button
          outline
          slate
          type="button"
          icon="i-lucide-refresh-cw"
          :disabled="isLoadingEligibleInboxes || !hasEligibleInboxes"
          :label="$t('AGENT_MGMT.EXCLUSIVE_LINK.REGENERATE')"
          @click="regenerateExclusiveLink"
        />
      </div>
    </div>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.HELP_TEXT') }}
    </p>

    <div class="mt-5">
      <label>
        {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.LABEL') }}
        <span class="text-n-ruby-9">
          {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.REQUIRED') }}
        </span>
      </label>
      <ComboBox
        v-model="selectedInboxId"
        :options="inboxOptions"
        :disabled="isLoadingEligibleInboxes || !hasEligibleInboxes"
        :has-error="inboxError"
        :message="
          inboxError ? $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.ERROR') : ''
        "
        :placeholder="$t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.PLACEHOLDER')"
        :search-placeholder="
          $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.SEARCH_PLACEHOLDER')
        "
        :empty-state="$t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.EMPTY_STATE')"
      />
      <p
        v-if="!isLoadingEligibleInboxes && !hasEligibleInboxes"
        class="mt-2 mb-0 text-xs leading-5 text-n-slate-10"
      >
        {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.EMPTY_STATE') }}
      </p>
      <p class="mt-2 mb-0 text-xs leading-5 text-n-slate-10">
        {{ $t('AGENT_MGMT.EXCLUSIVE_LINK.INBOXES.HELP_TEXT') }}
      </p>
    </div>
  </div>
</template>
