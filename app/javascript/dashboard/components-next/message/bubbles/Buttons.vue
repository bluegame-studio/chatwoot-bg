<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';

const { content, contentAttributes } = useMessageContext();

const buttons = computed(() => contentAttributes.value?.items ?? []);
</script>

<template>
  <BaseBubble
    class="w-72 max-w-[calc(100vw-5rem)] overflow-hidden"
    data-bubble-name="buttons"
  >
    <p class="m-0 whitespace-pre-wrap break-words px-4 py-3 text-sm leading-5">
      {{ content }}
    </p>
    <div v-if="buttons.length" class="flex flex-col border-t border-n-weak">
      <a
        v-for="(button, index) in buttons"
        :key="`${button.text}-${index}`"
        :href="button.uri"
        class="skip-context-menu flex min-h-10 items-center justify-center gap-1.5 border-n-weak px-3 text-sm font-medium text-n-brand no-underline hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-n-brand [&:not(:first-child)]:border-t"
        target="_blank"
        rel="noopener noreferrer"
      >
        <span class="truncate">{{ button.text }}</span>
        <Icon icon="i-lucide-external-link" class="size-4 shrink-0" />
      </a>
    </div>
  </BaseBubble>
</template>
