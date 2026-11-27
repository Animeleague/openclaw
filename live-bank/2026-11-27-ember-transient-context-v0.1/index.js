const ID = 'ember-transient-context';
const ENDPOINT = 'http://127.0.0.1:1234/v1';
const API = 'openai-completions';
const MODEL = 'gemma';
const endpoint = (s) => typeof s === 'string' ? s.replace(/\/+$/, '') : '';

// Deliberately limited to Ember's exact existing reasoning-enabled model.
// Provider-owned replay hooks replace (not merge with) transport fallback.
// Preserve all defined fallback fields for this exact route; change only retention.
export function buildReplayPolicy(ctx) {
  if (ctx.provider !== 'local' || ctx.modelId !== MODEL ||
      ctx.modelApi !== API || ctx.model?.reasoning !== true ||
      endpoint(ctx.model?.baseUrl) !== ENDPOINT) {
    throw new Error(`${ID}: unsupported replay route; disable this experimental plugin`);
  }
  return {
    sanitizeToolCallIds: true,
    toolCallIdMode: 'strict',
    dropReasoningFromHistory: false,
    applyAssistantFirstOrderingFix: true,
    validateGeminiTurns: true,
    validateAnthropicTurns: true,
    allowSyntheticToolResults: false,
    appendOnlyRuntimeContext: false,
  };
}

export function checkConfig(cfg) {
  const p = cfg?.models?.providers?.local;
  if (endpoint(p?.baseUrl) !== ENDPOINT || p?.api !== API ||
      !Array.isArray(p?.models) || p.models.length !== 1 ||
      p.models[0]?.id !== MODEL || p.models[0]?.reasoning !== true ||
      (p.models[0]?.api && p.models[0].api !== API)) {
    throw new Error(`${ID}: expected exactly one local/gemma model, reasoning=true, OpenAI Completions at the configured loopback endpoint; no provider registered`);
  }
  const m = cfg?.agents?.defaults?.model;
  if ((typeof m === 'string' ? m : m?.primary) !== 'local/gemma') {
    throw new Error(`${ID}: expected Ember's primary local/gemma model; no provider registered`);
  }
}

export default {
  id: ID,
  name: 'Ember Transient Context',
  description: 'Experimental provider-scoped replay policy',
  register(api) {
    checkConfig(api.config);
    api.registerProvider({ id: 'local', label: 'Ember local LM Studio', auth: [], buildReplayPolicy });
  },
};
