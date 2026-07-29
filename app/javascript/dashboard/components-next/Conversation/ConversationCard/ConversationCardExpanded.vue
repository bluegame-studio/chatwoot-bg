<script setup>
import { computed, useTemplateRef } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import CardAvatar from './CardAvatar.vue';
import CardContent from './CardContent.vue';
import CardLabels from './CardLabelsV5.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';
import InboxName from 'dashboard/components-next/Conversation/InboxName.vue';
import Avatar from 'next/avatar/Avatar.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';
import CardStatusIcon from './CardStatusIcon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  hasNewAssignmentAlert: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  isInboxView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'selectConversation',
  'deSelectConversation',
  'click',
  'contextmenu',
]);

const { t } = useI18n();
const activeChatClass =
  "active animate-card-select bg-n-alpha-1 dark:bg-n-alpha-3 !border-n-surface-1 before:!content-[none] after:content-[''] after:absolute ltr:after:left-2 rtl:after:right-2 after:top-2.5 after:bottom-2.5 after:w-1 after:rounded-full after:bg-n-brand after:pointer-events-none z-[2]";
const lastMessageInChat = computed(() => getLastMessage(props.chat));
const showLabelsSection = computed(() => props.chat.labels?.length > 0);
const contactDisplayId = computed(
  () =>
    props.currentContact?.identifier ||
    props.currentContact?.id ||
    props.currentContact?.name
);

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const unreadCount = computed(() => props.chat.unread_count);

const slaCardLabel = useTemplateRef('slaCardLabel');

const hasSlaPolicyId = computed(
  () =>
    !props.currentContact?.blocked &&
    (props.chat?.applied_sla?.id || slaCardLabel.value?.hasSlaThreshold)
);

const selectedModel = computed({
  get: () => props.selected,
  set: value => {
    if (value) {
      emit('selectConversation', value);
    } else {
      emit('deSelectConversation', value);
    }
  },
});

const copyContactDisplayId = async () => {
  try {
    await copyTextToClipboard(String(contactDisplayId.value));
    useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
  } catch (error) {
    // error
  }
};
</script>

<template>
  <div
    class="conversation relative cursor-pointer group grid gap-4 items-center px-3 h-12 border-b border-n-slate-3 hover:border-n-surface-1 hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      [activeChatClass]: isActiveChat,
      'selected bg-n-slate-2 dark:bg-n-slate-3 !border-n-surface-1': selected,
      'hover:bg-n-alpha-1': !isActiveChat && !selected,
      'grid-cols-[minmax(0,2fr)_minmax(0,1fr)]': showLabelsSection,
      'grid-cols-[minmax(0,2fr)_max-content]': !showLabelsSection,
    }"
    :style="
      hasNewAssignmentAlert
        ? { backgroundColor: '#FFF4E5', borderColor: '#F79009' }
        : {}
    "
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <span
      v-if="hasNewAssignmentAlert"
      class="absolute top-2 bottom-2 w-1 rounded-full ltr:left-1 rtl:right-1"
      style="background-color: #f79009"
    />
    <!-- LEFT SECTION -->
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <div class="flex items-center justify-center flex-shrink-0" @click.stop>
        <Checkbox v-model="selectedModel" />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardPriorityIcon :priority="chat.priority" show-empty />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <Avatar
          v-if="showAssignee && assignee.name"
          v-tooltip.top="{
            content: assignee.name,
            delay: { show: 500, hide: 0 },
          }"
          :name="assignee.name"
          :src="assignee.thumbnail"
          :size="14"
          :status="assignee.availability_status"
          hide-offline-status
        />
        <Icon
          v-else
          icon="i-woot-empty-assignee"
          class="size-4 text-n-slate-7"
        />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardStatusIcon :status="chat.status" show-empty />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div v-if="!isInboxView && showInboxName" class="w-20 flex-shrink-0">
        <InboxName v-if="showInboxName" :inbox="inbox" class="min-w-0" />
      </div>

      <div
        v-if="!isInboxView && showInboxName"
        class="w-px h-3 bg-n-slate-6 flex-shrink-0"
      />

      <div
        v-tooltip.top="{
          content: chat.id,
          delay: { show: 500, hide: 0 },
        }"
        class="h-6 flex items-center gap-1 max-w-20 w-full min-w-0 flex-shrink-0"
      >
        <Icon
          icon="i-woot-hash"
          class="size-3.5 text-n-slate-10 flex-shrink-0"
        />
        <span class="text-body-main text-n-slate-11 truncate">
          {{ chat.id }}
        </span>
      </div>

      <CardAvatar
        :contact="currentContact"
        :selected="false"
        :enable-selection="false"
        :hide-thumbnail="false"
      />

      <div class="flex items-center gap-1 w-32 flex-shrink-0 min-w-0">
        <h4
          class="text-heading-3 my-0 truncate text-n-slate-12 font-medium min-w-0"
          :class="{
            'font-semibold': hasNewAssignmentAlert,
          }"
          :style="hasNewAssignmentAlert ? { color: '#B54708' } : {}"
        >
          {{ contactDisplayId }}
        </h4>
        <button
          type="button"
          class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded size-5 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
          @click.stop.prevent="copyContactDisplayId"
        >
          <Icon icon="i-lucide-copy" class="size-3.5" />
        </button>
      </div>

      <CardContent
        :last-message="lastMessageInChat"
        :voice-call-status="voiceCallData.status"
        :voice-call-direction="voiceCallData.direction"
        :unread-count="unreadCount"
        :show-expanded-preview="false"
        :highlight-new-assignment="hasNewAssignmentAlert"
      />
    </div>

    <!-- RIGHT SECTION -->
    <div class="flex items-center justify-end gap-1.5 flex-shrink-0">
      <div v-if="showLabelsSection" class="min-w-0 w-full">
        <CardLabels
          :labels="chat.labels"
          disable-toggle
          class="my-0 [&>div]:justify-end justify-end"
        />
      </div>

      <div v-if="hasSlaPolicyId" class="flex-shrink-0">
        <SLACardLabel ref="slaCardLabel" :chat="chat" />
      </div>

      <div class="flex-shrink-0 w-[4.375rem] text-end">
        <TimeAgo
          :conversation-id="chat.id"
          :last-activity-timestamp="chat.timestamp"
          :created-at-timestamp="chat.created_at"
          class="font-440 !text-xs text-n-slate-11"
        />
      </div>
      <span
        v-if="hasNewAssignmentAlert"
        class="inline-flex items-center justify-center px-1.5 py-0.5 rounded text-[10px] font-semibold leading-3 border"
        style="
          color: #b54708;
          background-color: #fff4e5;
          border-color: #f79009;
        "
      >
        新分配
      </span>
    </div>
  </div>
</template>
