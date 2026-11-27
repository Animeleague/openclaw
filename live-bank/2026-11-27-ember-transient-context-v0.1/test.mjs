import assert from 'node:assert/strict';
import { test } from 'node:test';
import plugin, { checkConfig, buildReplayPolicy } from './index.js';
const cfg = { models: { providers: { local: { baseUrl: 'http://127.0.0.1:1234/v1', api: 'openai-completions', models: [{id:'gemma', reasoning:true}] } } }, agents: {defaults:{model:{primary:'local/gemma'}}} };
const ctx = { provider:'local', modelId:'gemma', modelApi:'openai-completions', model:{ reasoning:true, baseUrl: 'http://127.0.0.1:1234/v1' } };
test('valid config registers one provider and never mutates config', () => {
  const before=JSON.stringify(cfg); let registered=[];
  plugin.register({config:cfg, registerProvider:p=>registered.push(p)});
  assert.equal(JSON.stringify(cfg),before); assert.equal(registered.length,1);
  assert.equal(registered[0].id,'local'); assert.equal(registered[0].buildReplayPolicy(ctx).appendOnlyRuntimeContext,false);
});
test('bad config cannot register', () => {
  for(const change of [c=>c.models.providers.local.models.push({id:'other'}), c=>c.models.providers.local.baseUrl='https://example.com/v1', c=>c.agents.defaults.model.primary='openai/sol', c=>c.models.providers.local.models[0].reasoning=false]) {
    let c=structuredClone(cfg); change(c); let registered=false;
    assert.throws(()=>plugin.register({config:c, registerProvider:()=>{registered=true}})); assert.equal(registered,false);
  }
});
test('unsupported route fails closed', () => {
  for(const change of [c=>c.provider='openai', c=>c.modelId='other', c=>c.modelApi='openai-responses', c=>c.model.reasoning=false, c=>c.model.baseUrl='https://example.com/v1', c=>delete c.model]) {
    let c=structuredClone(ctx); change(c); assert.throws(()=>buildReplayPolicy(c));
  }
});
test('policy matches exact fallback except retention', () => {
  assert.deepEqual(buildReplayPolicy(ctx), {
    sanitizeToolCallIds:true, toolCallIdMode:'strict', dropReasoningFromHistory:false, applyAssistantFirstOrderingFix:true, validateGeminiTurns:true, validateAnthropicTurns:true, allowSyntheticToolResults:false, appendOnlyRuntimeContext:false
  });
});
