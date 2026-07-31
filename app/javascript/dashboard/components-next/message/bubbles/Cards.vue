<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';

const { contentAttributes } = useMessageContext();

const cards = computed(() => contentAttributes.value?.items ?? []);
</script>

<template>
  <BaseBubble
    class="max-w-[min(34rem,calc(100vw-5rem))] overflow-hidden"
    data-bubble-name="cards"
  >
    <div class="flex max-w-full overflow-x-auto snap-x snap-mandatory">
      <article
        v-for="(card, index) in cards"
        :key="`${card.title}-${index}`"
        class="flex w-72 shrink-0 snap-start flex-col border-n-weak first:border-l-0 ltr:border-l rtl:border-r rtl:first:border-r-0"
      >
        <img
          v-if="card.mediaUrl"
          :src="card.mediaUrl"
          :alt="card.title"
          class="h-36 w-full bg-n-alpha-2 object-cover"
          loading="lazy"
        />
        <div class="flex min-h-24 flex-1 flex-col gap-1 px-4 py-3">
          <h3 class="m-0 text-sm font-medium leading-5 text-n-slate-12">
            {{ card.title }}
          </h3>
          <p
            v-if="card.description"
            class="m-0 text-sm leading-5 text-n-slate-11"
          >
            {{ card.description }}
          </p>
        </div>
        <div
          v-if="card.actions?.length"
          class="flex flex-col border-t border-n-weak"
        >
          <template
            v-for="(action, actionIndex) in card.actions"
            :key="`${action.text}-${actionIndex}`"
          >
            <a
              v-if="action.type === 'link'"
              :href="action.uri"
              class="skip-context-menu flex min-h-10 items-center justify-center gap-1.5 border-n-weak px-3 text-sm font-medium text-n-brand no-underline hover:bg-n-alpha-2 [&:not(:first-child)]:border-t"
              target="_blank"
              rel="noopener noreferrer"
            >
              <span class="truncate">{{ action.text }}</span>
              <Icon icon="i-lucide-external-link" class="size-4 shrink-0" />
            </a>
            <div
              v-else
              class="flex min-h-10 items-center justify-center border-n-weak px-3 text-sm font-medium text-n-slate-11 [&:not(:first-child)]:border-t"
            >
              <span class="truncate">{{ action.text }}</span>
            </div>
          </template>
        </div>
      </article>
    </div>
  </BaseBubble>
</template>
