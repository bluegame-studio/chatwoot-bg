#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');

const DEFAULT_CONFIG_FILE = path.join(process.cwd(), 'scripts', 'simple-agent-bot.env');
const DEFAULT_STATE_FILE = path.join('/tmp', 'chatwoot-simple-agent-bot-state.json');

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};

  return fs
    .readFileSync(filePath, 'utf8')
    .split('\n')
    .map(line => line.trim())
    .filter(line => line && !line.startsWith('#'))
    .reduce((config, line) => {
      const separatorIndex = line.indexOf('=');
      if (separatorIndex === -1) return config;

      const key = line.slice(0, separatorIndex).trim();
      const value = line.slice(separatorIndex + 1).trim().replace(/^["']|["']$/g, '');
      return { ...config, [key]: value };
    }, {});
}

function config() {
  const fileConfig = parseEnvFile(process.env.BOT_CONFIG_FILE || DEFAULT_CONFIG_FILE);
  return {
    chatwootUrl: process.env.CHATWOOT_URL || fileConfig.CHATWOOT_URL || 'http://localhost:3000',
    accountId: process.env.CHATWOOT_ACCOUNT_ID || fileConfig.CHATWOOT_ACCOUNT_ID || '1',
    botToken: process.env.CHATWOOT_BOT_TOKEN || fileConfig.CHATWOOT_BOT_TOKEN || '',
    botSecret: process.env.CHATWOOT_BOT_SECRET || fileConfig.CHATWOOT_BOT_SECRET || '',
    port: Number(process.env.BOT_PORT || fileConfig.BOT_PORT || 4000),
    host: process.env.BOT_HOST || fileConfig.BOT_HOST || '127.0.0.1',
    handoffAfter: Number(process.env.HANDOFF_AFTER || fileConfig.HANDOFF_AFTER || 3),
    stateFile: process.env.BOT_STATE_FILE || fileConfig.BOT_STATE_FILE || DEFAULT_STATE_FILE,
    interactiveMessage:
      process.env.BOT_INTERACTIVE_MESSAGE ||
      fileConfig.BOT_INTERACTIVE_MESSAGE ||
      '你好，我是智能助手。请选择你需要的服务：',
    interactiveOptions: parseInteractiveOptions(
      process.env.BOT_INTERACTIVE_OPTIONS || fileConfig.BOT_INTERACTIVE_OPTIONS
    ),
  };
}

function parseInteractiveOptions(rawOptions) {
  if (!rawOptions) {
    return [
      { title: '咨询订单', value: 'order' },
      { title: '转人工客服', value: 'agent' },
    ];
  }

  return rawOptions.split(',').map(option => {
    const [title, value] = option.split(':').map(part => part.trim());
    return { title, value: value || title };
  });
}

function loadState(stateFile) {
  try {
    if (!fs.existsSync(stateFile)) return { conversations: {}, deliveries: {} };
    return JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  } catch (error) {
    console.warn(`[bot] Could not read state file: ${error.message}`);
    return { conversations: {}, deliveries: {} };
  }
}

function saveState(stateFile, state) {
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
}

function verifySignature(rawBody, headers, botSecret) {
  if (!botSecret) return true;

  const signature = headers['x-chatwoot-signature'];
  const timestamp = headers['x-chatwoot-timestamp'];
  if (!signature || !timestamp) return false;

  const expected = `sha256=${crypto
    .createHmac('sha256', botSecret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex')}`;

  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}

async function chatwootRequest(configValue, route, body) {
  if (!configValue.botToken) {
    throw new Error('CHATWOOT_BOT_TOKEN is missing. Add it to scripts/simple-agent-bot.env.');
  }

  const response = await fetch(`${configValue.chatwootUrl}${route}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      api_access_token: configValue.botToken,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Chatwoot API failed: ${response.status} ${text}`);
  }
}

async function sendReply(configValue, conversationId, content) {
  await chatwootRequest(
    configValue,
    `/api/v1/accounts/${configValue.accountId}/conversations/${conversationId}/messages`,
    {
      content,
      message_type: 'outgoing',
      private: false,
    }
  );
}

async function sendInteractiveReply(configValue, conversationId) {
  await chatwootRequest(
    configValue,
    `/api/v1/accounts/${configValue.accountId}/conversations/${conversationId}/messages`,
    {
      content: configValue.interactiveMessage,
      message_type: 'outgoing',
      private: false,
      content_type: 'input_select',
      content_attributes: {
        items: configValue.interactiveOptions,
      },
    }
  );
}

async function handoffToAgent(configValue, conversationId) {
  await chatwootRequest(
    configValue,
    `/api/v1/accounts/${configValue.accountId}/conversations/${conversationId}/toggle_status`,
    { status: 'open' }
  );
}

function shouldProcess(payload) {
  return payload.event === 'message_created' && payload.message_type === 'incoming' && payload.private === false;
}

async function handlePayload(payload, deliveryId) {
  const configValue = config();
  const state = loadState(configValue.stateFile);

  if (deliveryId && state.deliveries[deliveryId]) return { skipped: 'duplicate delivery' };
  if (deliveryId) state.deliveries[deliveryId] = Date.now();

  if (payload.event === 'conversation_resolved') {
    state.conversations[payload.id] = {
      incomingCount: 0,
      handedOff: false,
      interactiveSent: false,
      waitingForNewRound: true,
    };
    saveState(configValue.stateFile, state);
    return { ok: true, reset: payload.id };
  }

  if (!shouldProcess(payload)) {
    saveState(configValue.stateFile, state);
    return { skipped: 'not an incoming public message' };
  }

  const conversationId = payload.conversation?.id;
  if (!conversationId) throw new Error('Missing conversation id in webhook payload.');

  const current = state.conversations[conversationId] || {
    incomingCount: 0,
    handedOff: false,
    interactiveSent: false,
    waitingForNewRound: false,
  };

  if (current.waitingForNewRound || (current.handedOff && payload.conversation?.status === 'pending')) {
    current.incomingCount = 0;
    current.handedOff = false;
    current.interactiveSent = false;
    current.waitingForNewRound = false;
  }

  current.incomingCount += 1;
  state.conversations[conversationId] = current;
  saveState(configValue.stateFile, state);

  if (current.handedOff) return { skipped: 'already handed off' };

  if (!current.interactiveSent) {
    current.interactiveSent = true;
    saveState(configValue.stateFile, state);
    await sendInteractiveReply(configValue, conversationId);
    return { ok: true, replied: true, interactive: true, incomingCount: current.incomingCount };
  }

  if (current.incomingCount <= configValue.handoffAfter) {
    await sendReply(configValue, conversationId, `我收到啦，这是第 ${current.incomingCount} 条消息。我先帮你处理。`);
    return { ok: true, replied: true, incomingCount: current.incomingCount };
  }

  current.handedOff = true;
  saveState(configValue.stateFile, state);
  await sendReply(configValue, conversationId, '我把这段会话转给人工客服继续处理。');
  await handoffToAgent(configValue, conversationId);
  return { ok: true, handedOff: true, incomingCount: current.incomingCount };
}

const server = http.createServer((request, response) => {
  if (request.method !== 'POST' || request.url !== '/webhook') {
    response.writeHead(404);
    response.end('Not found');
    return;
  }

  let rawBody = '';
  request.on('data', chunk => {
    rawBody += chunk;
  });

  request.on('end', async () => {
    try {
      const configValue = config();
      if (!verifySignature(rawBody, request.headers, configValue.botSecret)) {
        response.writeHead(401);
        response.end('Invalid signature');
        return;
      }

      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ ok: true, accepted: true }));

      handlePayload(JSON.parse(rawBody), request.headers['x-chatwoot-delivery'])
        .then(result => console.log('[bot]', result))
        .catch(error => console.error('[bot]', error));
    } catch (error) {
      console.error('[bot]', error);
      response.writeHead(500, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: error.message }));
    }
  });
});

server.listen(config().port, config().host, () => {
  const configValue = config();
  console.log(`[bot] Listening on http://${configValue.host}:${configValue.port}/webhook`);
  console.log(`[bot] Chatwoot URL: ${configValue.chatwootUrl}, account: ${configValue.accountId}`);
  console.log(`[bot] Handoff after ${configValue.handoffAfter} incoming messages`);
  if (!configValue.botToken) {
    console.log('[bot] Add CHATWOOT_BOT_TOKEN to scripts/simple-agent-bot.env before testing replies.');
  }
});
