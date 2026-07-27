import { CONVERSATION_PRIORITY } from './messages';

export const CONVERSATION_PRIORITY_STYLE = {
  [CONVERSATION_PRIORITY.URGENT]: {
    color: '#F04438',
    backgroundColor: '#FEECEC',
  },
  [CONVERSATION_PRIORITY.HIGH]: {
    color: '#F79009',
    backgroundColor: '#FFF4E5',
  },
  [CONVERSATION_PRIORITY.MEDIUM]: {
    color: '#2F80ED',
    backgroundColor: '#EAF3FF',
  },
  [CONVERSATION_PRIORITY.LOW]: {
    color: '#667085',
    backgroundColor: '#F2F4F7',
  },
};

export const getConversationPriorityStyle = priority =>
  CONVERSATION_PRIORITY_STYLE[priority] || {};

export const CONVERSATION_UNREAD_STYLE = {
  color: '#1D4ED8',
  backgroundColor: '#EAF3FF',
};

export const getConversationCardStyle = (priority, hasUnread = false) => {
  const { backgroundColor } = getConversationPriorityStyle(priority);

  if (backgroundColor) {
    return { backgroundColor };
  }

  return hasUnread
    ? { backgroundColor: CONVERSATION_UNREAD_STYLE.backgroundColor }
    : {};
};
