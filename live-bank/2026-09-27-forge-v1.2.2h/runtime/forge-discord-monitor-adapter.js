import { coerceSecretRef, resolveSecretRefValues } from "openclaw/plugin-sdk/secret-ref-runtime";
import { Type } from "typebox";
import { resolveConfig } from "./defaults.js";
import { MessageActivityCounter } from "./activity-counter.js";
import { CrossChannelSpamController } from "./cross-channel-spam.js";
import { CrossModelContinuityStore, continuitySideForModel } from "./cross-model-continuity.js";
import { PersistentPendingContinuityMap } from "./persistent-pending-continuity.js";
import { JsonlAuditLogger } from "./logger.js";
import { AutomaticAntiSpamController, DiscordRestModerationTransport, ModerationActionController } from "./moderation-actions.js";
import { contentDigest, directDiscordMentionPattern, extractLinkMedia, hasPhrase, inferMediaKind, normalizedDiscordMentionPattern, normalizeUrl } from "./normalization.js";
import { MonitorEngine } from "./monitor.js";
import { PersistentRecentChannelContext } from "./persistent-recent-channel-context.js"; // FORGE_PERSISTENT_RECENT_CHANNEL_CONTEXT_V1
import { sanitizeAssistantMassMentions } from "./mass-mentions.js";
import { GatewayModelRouter } from "./model-routing.js";
import { KbRuleFileStore } from "./rule-files.js";
import { formatCreditUsageReport, formatTokenUsageReport, readTurnUsageReport } from "./usage-report.js";
const FORGE_NATIVE_DELTA_BRIDGE_KEY = Symbol.for("forge.codex-native-delta.v1");
const FORGE_NATIVE_DELTA_TTL_MS = 2 * 60 * 60 * 1_000;
const forgeNativeDeltaBridge = () => {
    const globals = globalThis;
    const current = globals[FORGE_NATIVE_DELTA_BRIDGE_KEY];
    const bridge = {
        pendingRuns: current?.pendingRuns instanceof Map ? current.pendingRuns : new Map(),
        confirmations: current?.confirmations instanceof Map ? current.confirmations : new Map(),
        deliveredByThread: current?.deliveredByThread instanceof Map
            ? current.deliveredByThread
            : new Map(),
        ...(typeof current?.currentPrincipalThreadId === "string" &&
            current.currentPrincipalThreadId
            ? { currentPrincipalThreadId: current.currentPrincipalThreadId }
            : {})
    };
    globals[FORGE_NATIVE_DELTA_BRIDGE_KEY] = bridge;
    return bridge;
};
const cleanupForgeNativeDeltaBridge = (bridge, now = Date.now()) => {
    const oldest = now - FORGE_NATIVE_DELTA_TTL_MS;
    for (const [runId, payload] of bridge.pendingRuns) {
        if (payload.publishedAt < oldest)
            bridge.pendingRuns.delete(runId);
    }
    for (const [runId, confirmation] of bridge.confirmations) {
        if (confirmation.injectedAt < oldest)
            bridge.confirmations.delete(runId);
    }
    // Delivered IDs are a native-thread ledger, not a short-lived transport cache.
    // Keep them for the life of the warm thread so retained journal entries are
    // never re-injected into the same Luna native generation.
    while (bridge.deliveredByThread.size > 64) {
        const oldestThreadId = bridge.deliveredByThread.keys().next().value;
        if (!oldestThreadId)
            break;
        bridge.deliveredByThread.delete(oldestThreadId);
    }
    while (bridge.pendingRuns.size > 512) {
        const first = bridge.pendingRuns.keys().next().value;
        if (!first)
            break;
        bridge.pendingRuns.delete(first);
    }
    while (bridge.confirmations.size > 512) {
        const first = bridge.confirmations.keys().next().value;
        if (!first)
            break;
        bridge.confirmations.delete(first);
    }
};
const publishForgeNativeDelta = (runId, targetSide, delta) => {
    const bridge = forgeNativeDeltaBridge();
    cleanupForgeNativeDeltaBridge(bridge);
    bridge.pendingRuns.set(runId, {
        version: 1,
        scope: "discord",
        targetSide,
        runId,
        publishedAt: Date.now(),
        exchanges: delta.exchanges.map((exchange) => ({
            ...exchange,
            visibility: exchange.isGroup ? "public" : "private"
        })),
        acknowledgeIds: [...delta.acknowledgeIds]
    });
};
const sameIds = (left, right) => {
    if (left.length !== right.length)
        return false;
    const expected = new Set(left);
    return expected.size === right.length && right.every((id) => expected.has(id));
};
const confirmedNativeDeltaIds = (runId, targetSide, expectedIds) => {
    const bridge = forgeNativeDeltaBridge();
    cleanupForgeNativeDeltaBridge(bridge);
    const confirmation = bridge.confirmations.get(runId);
    if (!confirmation ||
        confirmation.version !== 1 ||
        confirmation.scope !== "discord" ||
        confirmation.targetSide !== targetSide ||
        confirmation.runId !== runId ||
        !sameIds(expectedIds, confirmation.acknowledgeIds)) {
        return;
    }
    return [...confirmation.acknowledgeIds];
};
const releaseForgeNativeDeltaRun = (runId) => {
    const bridge = forgeNativeDeltaBridge();
    bridge.pendingRuns.delete(runId);
    bridge.confirmations.delete(runId);
};
const readString = (value) => typeof value === "string" && value.trim().length > 0 ? value : undefined;
const readStringArray = (value) => Array.isArray(value) ? value.filter((item) => typeof item === "string") : [];
const readRecord = (value) => value && typeof value === "object" && !Array.isArray(value)
    ? value
    : undefined;
const readBoolean = (value) => typeof value === "boolean" ? value : undefined;
const resolveDiscordBotToken = async (rootConfig, accountId) => {
    const channels = readRecord(rootConfig.channels);
    const discord = readRecord(channels?.discord);
    const accounts = readRecord(discord?.accounts);
    const configuredAccountId = accountId ?? readString(discord?.defaultAccount) ?? "default";
    const configuredAccount = readRecord(accounts?.[configuredAccountId]);
    const defaultAccount = readRecord(accounts?.default);
    const firstAccount = accounts
        ? Object.values(accounts).map(readRecord).find(Boolean)
        : undefined;
    const tokenInput = configuredAccount?.token ??
        defaultAccount?.token ??
        discord?.token ??
        firstAccount?.token ??
        process.env.DISCORD_BOT_TOKEN;
    const ref = coerceSecretRef(tokenInput);
    if (ref) {
        const values = await resolveSecretRefValues([ref], {
            config: rootConfig,
            env: process.env
        });
        const value = values.get(`${ref.source}:${ref.provider}:${ref.id}`);
        if (typeof value === "string" && value.trim())
            return value.trim();
        throw new Error("The configured Discord bot token secret resolved empty.");
    }
    if (typeof tokenInput === "string" && tokenInput.trim()) {
        return tokenInput.trim();
    }
    throw new Error(`Discord bot token is unavailable for account "${configuredAccountId}".`);
};
const stripConversationPrefix = (value) => {
    const idAtEnd = value.match(/(\d{5,})$/u)?.[1];
    return idAtEnd ?? value.replace(/^(?:discord|channel|chat):/u, "");
};
const resolveChannelId = (context, metadata) => {
    const candidate = readString(context.conversationId) ??
        readString(metadata?.originatingTo) ??
        readString(metadata?.to);
    return candidate ? stripConversationPrefix(candidate) : undefined;
};
const replyTargetsForge = (replyToSender, config) => {
    if (!replyToSender)
        return false;
    if (config.forge.userId && replyToSender.includes(config.forge.userId))
        return true;
    return config.forge.aliases.some((alias) => hasPhrase(replyToSender, alias));
};
const containsForgeMention = (content, config) => {
    if (config.forge.userId &&
        directDiscordMentionPattern(config.forge.userId).test(content)) {
        return true;
    }
    return config.forge.aliases.some((alias) => normalizedDiscordMentionPattern(alias).test(content));
};
const attachmentMedia = (metadata) => {
    if (!metadata)
        return [];
    const paths = [
        ...readStringArray(metadata.mediaPaths),
        ...readStringArray(metadata.originalMediaPaths)
    ];
    const urls = [
        ...readStringArray(metadata.mediaUrls),
        ...readStringArray(metadata.originalMediaUrls)
    ];
    const types = [
        ...readStringArray(metadata.mediaTypes),
        ...readStringArray(metadata.originalMediaTypes)
    ];
    const singlePath = readString(metadata.mediaPath) ?? readString(metadata.originalMediaPath);
    const singleUrl = readString(metadata.mediaUrl) ?? readString(metadata.originalMediaUrl);
    const singleType = readString(metadata.mediaType) ?? readString(metadata.originalMediaType);
    if (singlePath)
        paths.unshift(singlePath);
    if (singleUrl)
        urls.unshift(singleUrl);
    if (singleType)
        types.unshift(singleType);
    const size = Math.max(paths.length, urls.length, types.length);
    const items = [];
    const seen = new Set();
    for (let index = 0; index < size; index += 1) {
        const url = urls[index];
        const path = paths[index];
        const contentType = types[index];
        const source = url ?? path;
        if (!source)
            continue;
        const identity = url ? normalizeUrl(url) : source;
        const key = contentDigest(identity);
        if (seen.has(key))
            continue;
        seen.add(key);
        items.push({
            kind: inferMediaKind(url ?? path ?? "", contentType),
            key,
            ...(contentType ? { contentType } : {}),
            source,
            sourceType: "attachment"
        });
    }
    return items;
};
const dedupeMedia = (items) => {
    const seen = new Set();
    return items.filter((item) => {
        if (seen.has(item.key))
            return false;
        seen.add(item.key);
        return true;
    });
};
export const toMonitorMessage = (event, context, config, now = Date.now) => {
    if (context.channelId !== "discord")
        return null;
    const metadata = event.metadata;
    const channelId = resolveChannelId(context, metadata);
    const userId = event.senderId ?? context.senderId ?? readString(metadata?.senderId);
    if (!channelId || !userId)
        return null;
    const replyToSender = event.replyToSender ??
        context.replyToSender ??
        readString(metadata?.replyToSender);
    const guildId = readString(metadata?.guildId);
    const userName = readString(metadata?.senderName) ?? readString(metadata?.senderUsername);
    const channelName = readString(metadata?.channelName);
    const member = readRecord(metadata?.member);
    const userRoleIds = [
        ...readStringArray(metadata?.userRoleIds),
        ...readStringArray(metadata?.memberRoleIds),
        ...readStringArray(metadata?.roleIds),
        ...readStringArray(member?.roles)
    ];
    const metadataMarksBot = readBoolean(metadata?.isBot) === true ||
        readBoolean(metadata?.senderIsBot) === true ||
        readBoolean(metadata?.bot) === true ||
        Boolean(readString(metadata?.webhookId));
    const content = event.content ?? "";
    const directForgeMention = containsForgeMention(content, config);
    return {
        timestamp: event.timestamp ?? now(),
        userId,
        ...(userName ? { userName } : {}),
        channelId,
        ...(channelName ? { channelName } : {}),
        content,
        ...(guildId ? { guildId } : {}),
        ...(event.messageId ? { messageId: event.messageId } : {}),
        ...(replyToSender ? { replyToUserName: replyToSender } : {}),
        directForgeMention,
        replyToForge: replyTargetsForge(replyToSender, config),
        ...(userRoleIds.length > 0 ? { userRoleIds: [...new Set(userRoleIds)] } : {}),
        isBot: metadataMarksBot ||
            config.botUserIds.includes(userId) ||
            config.forge.userId === userId,
        media: dedupeMedia([...attachmentMedia(metadata), ...extractLinkMedia(content)])
    };
};
const containsDirectForgeMention = (event, config) => {
    const content = `${event.content}\n${event.body ?? ""}`;
    return containsForgeMention(content, config);
};
const shouldSuppressMentionOnlyDispatch = (event, context, config) => {
    if (!config.routingGate.enabled || event.channel !== "discord")
        return false;
    if (event.isGroup === false)
        return false;
    const channelId = resolveChannelId(context);
    if (!channelId || !config.routingGate.mentionOnlyChannelIds.includes(channelId)) {
        return false;
    }
    if (containsDirectForgeMention(event, config))
        return false;
    const replyToSender = event.replyToSender ?? context.replyToSender;
    return !replyTargetsForge(replyToSender, config);
};
// FORGE_MONITOR_ADDRESSED_USER_GUARD_V1
const RAW_DISCORD_USER_MENTION_PATTERN = /<@!?(\d+)>/gu;
const NORMALIZED_DISCORD_USER_MENTION_PATTERN = /(?<![\p{L}\p{N}_@])@(?!everyone\b|here\b)[\p{L}\p{N}_]/iu;
const explicitlyAddressesForge = (event, config) => {
    const content = event.content ?? "";
    if (containsForgeMention(content, config))
        return true;
    return config.forge.aliases.some((alias) => hasPhrase(content, alias));
};
const targetsAnotherDiscordUser = (event, context, config) => {
    if (event.channel !== "discord" || event.isGroup === false)
        return false;
    if (explicitlyAddressesForge(event, config))
        return false;
    const replyToSender = event.replyToSender ?? context.replyToSender;
    if (replyToSender) {
        if (replyTargetsForge(replyToSender, config))
            return false;
        return true;
    }
    const content = event.content ?? "";
    for (const match of content.matchAll(RAW_DISCORD_USER_MENTION_PATTERN)) {
        const userId = match[1];
        if (userId && userId !== config.forge.userId)
            return true;
    }
    return NORMALIZED_DISCORD_USER_MENTION_PATTERN.test(content);
};
export const shouldSuppressDispatch = (event, context, config) => {
    if (!config.routingGate.enabled || event.channel !== "discord")
        return false;
    if (event.isGroup === false)
        return false;
    if (shouldSuppressMentionOnlyDispatch(event, context, config))
        return true;
    const content = (event.body ?? event.content).trim();
    if (config.routingGate.passSlashCommands && content.startsWith("/") && !content.startsWith("/ ")) {
        return false;
    }
    if (containsDirectForgeMention(event, config))
        return false;
    const replyToSender = event.replyToSender ?? context.replyToSender;
    if (replyTargetsForge(replyToSender, config))
        return false;
    if (targetsAnotherDiscordUser(event, context, config))
        return true;
    const channelId = resolveChannelId(context);
    if (channelId && config.routingGate.alwaysDispatchChannelIds.includes(channelId))
        return false;
    return true;
};
const toDispatchMonitorMessage = (event, context, config, now) => {
    const channelId = resolveChannelId(context);
    const userId = event.senderId ?? context.senderId;
    if (!channelId || !userId)
        return null;
    const replyToSender = event.replyToSender ?? context.replyToSender;
    return {
        timestamp: event.timestamp ?? now(),
        userId,
        ...(event.senderName
            ? { userName: event.senderName }
            : event.senderUsername
                ? { userName: event.senderUsername }
                : {}),
        channelId,
        content: event.content,
        ...(config.guildId ? { guildId: config.guildId } : {}),
        ...(event.messageId ? { messageId: event.messageId } : {}),
        ...(replyToSender ? { replyToUserName: replyToSender } : {}),
        directForgeMention: containsForgeMention(`${event.content}\n${event.body ?? ""}`, config),
        replyToForge: replyTargetsForge(replyToSender, config),
        isBot: config.botUserIds.includes(userId) || config.forge.userId === userId,
        media: extractLinkMedia(event.content)
    };
};
export class AssistanceDispatchGate {
    #config;
    #engine;
    #cooldowns = new Map();
    #now;
    constructor(config, now = Date.now) {
        this.#config = config;
        this.#engine = new MonitorEngine(config);
        this.#now = now;
    }
    evaluate(event, context) {
        if (!this.#config.enabled ||
            (!this.#config.assistanceDispatch.enabled &&
                !this.#config.moderationDispatch.enabled)) {
            return;
        }
        const message = toDispatchMonitorMessage(event, context, this.#config, this.#now);
        if (!message)
            return;
        const result = this.#engine.process(message);
        if (!result?.outcome)
            return;
        const linkPosted = result.outcome.triggers.some((trigger) => trigger.id === "link-posted");
        const addressedToAnotherUser = targetsAnotherDiscordUser(event, context, this.#config);
        const addressedModerationOverride = result.outcome.triggers.some((trigger) => trigger.track === "moderation" &&
            [
                "possible-hostility",
                "directed-abuse",
                "profanity-burst",
                "serious-term"
            ].includes(trigger.id));
        const assistance = this.#config.assistanceDispatch.enabled &&
            !addressedToAnotherUser &&
            (linkPosted ||
                result.outcome.assistanceScore >= this.#config.assistanceDispatch.threshold);
        const moderation = this.#config.moderationDispatch.enabled &&
            (!addressedToAnotherUser || addressedModerationOverride) &&
            result.outcome.moderationScore >= this.#config.moderationDispatch.threshold;
        if (!assistance && !moderation)
            return;
        const category = assistance && moderation
            ? "BOTH"
            : assistance
                ? "ASSISTANCE"
                : "MODERATION";
        const cooldownMs = category === "BOTH"
            ? Math.max(this.#config.assistanceDispatch.cooldownMs, this.#config.moderationDispatch.cooldownMs)
            : category === "ASSISTANCE"
                ? this.#config.assistanceDispatch.cooldownMs
                : this.#config.moderationDispatch.cooldownMs;
        const maxCooldownEntries = Math.max(this.#config.assistanceDispatch.maxCooldownEntries, this.#config.moderationDispatch.maxCooldownEntries);
        const cooldownKey = `${message.channelId}:${message.userId}`;
        const now = message.timestamp;
        this.#cleanup(now);
        const current = {
            lastSummonedAt: now,
            assistance,
            moderation,
            assistanceScore: result.outcome.assistanceScore,
            moderationScore: result.outcome.moderationScore,
            reviewLevel: reviewLevel(result.outcome)
        };
        const previous = this.#cooldowns.get(cooldownKey);
        if (previous && now - previous.lastSummonedAt < cooldownMs) {
            const assistanceEscalated = assistance &&
                (!previous.assistance ||
                    current.assistanceScore - previous.assistanceScore >=
                        this.#config.assistanceDispatch.escalationScoreDelta);
            const moderationEscalated = moderation &&
                (!previous.moderation ||
                    current.moderationScore - previous.moderationScore >=
                        this.#config.moderationDispatch.escalationScoreDelta);
            const strongerReviewSignal = current.reviewLevel > previous.reviewLevel;
            if (!assistanceEscalated && !moderationEscalated && !strongerReviewSignal) {
                this.#cooldowns.set(cooldownKey, {
                    ...previous,
                    assistance: previous.assistance || assistance,
                    moderation: previous.moderation || moderation,
                    assistanceScore: Math.max(previous.assistanceScore, current.assistanceScore),
                    moderationScore: Math.max(previous.moderationScore, current.moderationScore),
                    reviewLevel: Math.max(previous.reviewLevel, current.reviewLevel)
                });
                return;
            }
        }
        this.#cooldowns.delete(cooldownKey);
        this.#cooldowns.set(cooldownKey, current);
        while (this.#cooldowns.size > maxCooldownEntries) {
            const oldestKey = this.#cooldowns.keys().next().value;
            if (!oldestKey)
                break;
            this.#cooldowns.delete(oldestKey);
        }
        return { message, outcome: result.outcome, category };
    }
    snapshot() {
        return { cooldowns: this.#cooldowns.size };
    }
    #cleanup(now) {
        const retentionMs = Math.max(this.#config.assistanceDispatch.cooldownMs, this.#config.moderationDispatch.cooldownMs);
        if (retentionMs <= 0) {
            this.#cooldowns.clear();
            return;
        }
        const oldest = now - retentionMs;
        for (const [key, entry] of this.#cooldowns) {
            if (entry.lastSummonedAt <= oldest)
                this.#cooldowns.delete(key);
        }
    }
}
const STRONG_REVIEW_TRIGGERS = new Set([
    "directed-abuse",
    "serious-term",
    "profanity-burst",
    "rapid-posting-strong",
    "duplicate-message-strong",
    "duplicate-media",
    "media-flood",
    "cross-channel-duplicate"
]);
const SEVERE_REVIEW_TRIGGERS = new Set([
    "rapid-posting-severe",
    "duplicate-message-severe"
]);
const reviewLevel = (outcome) => {
    const triggerIds = outcome.triggers.map((trigger) => trigger.id);
    if (triggerIds.some((triggerId) => SEVERE_REVIEW_TRIGGERS.has(triggerId)))
        return 3;
    if (triggerIds.some((triggerId) => STRONG_REVIEW_TRIGGERS.has(triggerId)))
        return 2;
    return 1;
};
// FORGE_PERSISTENT_RECENT_CHANNEL_CONTEXT_V1
// Same-channel Discord history is persisted across plugin re-instantiation.
const invocationResult = (summon, config, forgeReplied = false) => ({
    message: summon.message,
    outcome: {
        classification: summon.category,
        assistanceScore: summon.outcome.assistanceScore,
        moderationScore: summon.outcome.moderationScore,
        assistanceThreshold: config.assistanceDispatch.threshold,
        moderationThreshold: config.moderationDispatch.threshold,
        triggers: summon.outcome.triggers,
        stats: summon.outcome.stats,
        actionSelected: "TRIGGER_FORGE",
        forgeCalled: true,
        forgeReplied,
        warningIssued: false,
        timeoutApplied: false,
        staffAlertSent: false,
        actionActor: "NONE"
    }
});
const moderationActionResult = (record) => ({
    message: record.message,
    outcome: {
        classification: "MODERATION",
        assistanceScore: 0,
        moderationScore: 0,
        assistanceThreshold: 0,
        moderationThreshold: 0,
        triggers: record.triggerIds.map((triggerId) => ({
            id: triggerId,
            track: "moderation",
            score: 0
        })),
        stats: {
            messages10s: 0,
            messages15s: 0,
            messages30s: 0,
            duplicateText15s: 0,
            duplicateText30s: 0,
            sameMedia15s: 0,
            mediaItems20s: 0,
            repeatedMention30s: 0,
            forgeMentions30s: 0,
            matchingChannels60s: 0,
            activeChannels30s: 0
        },
        actionSelected: record.action === "warn"
            ? "WARN_USER"
            : record.action === "alert_staff"
                ? "ALERT_STAFF"
                : "APPLY_TIMEOUT",
        forgeCalled: record.actor === "FORGE",
        forgeReplied: false,
        warningIssued: record.action === "warn",
        timeoutApplied: record.action === "timeout",
        staffAlertSent: record.action === "alert_staff",
        actionActor: record.actor,
        actionReason: record.reason,
        ...(record.timeoutMinutes !== undefined
            ? { timeoutMinutes: record.timeoutMinutes }
            : {}),
        ...(record.reviewId ? { reviewId: record.reviewId } : {})
    }
});
export const registerMonitor = (api) => {
    const configInput = (api.pluginConfig ?? {});
    const resolved = resolveConfig(configInput);
    const config = {
        ...resolved,
        logging: {
            ...resolved.logging,
            path: api.resolvePath(resolved.logging.path)
        },
        activityTracking: {
            ...resolved.activityTracking,
            path: api.resolvePath(resolved.activityTracking.path)
        },
        ruleFiles: {
            ...resolved.ruleFiles,
            directoryPath: api.resolvePath(resolved.ruleFiles.directoryPath)
        },
        moderationActions: {
            ...resolved.moderationActions,
            judgement: {
                ...resolved.moderationActions.judgement
            },
            temporaryTimeouts: {
                ...resolved.moderationActions.temporaryTimeouts,
                allowedMinutes: [
                    ...resolved.moderationActions.temporaryTimeouts.allowedMinutes
                ]
            },
            automaticAntiSpam: {
                ...resolved.moderationActions.automaticAntiSpam,
                objectiveTriggerIds: [
                    ...resolved.moderationActions.automaticAntiSpam.objectiveTriggerIds
                ],
                statePath: api.resolvePath(resolved.moderationActions.automaticAntiSpam.statePath)
            },
            crossChannelSpam: {
                ...resolved.moderationActions.crossChannelSpam,
                exemptRoleIds: [
                    ...resolved.moderationActions.crossChannelSpam.exemptRoleIds
                ],
                statePath: api.resolvePath(resolved.moderationActions.crossChannelSpam.statePath)
            }
        }
    };
    const gatewayModelRouter = new GatewayModelRouter(api.pluginConfig, config, api.logger);
    // FORGE_CROSS_MODEL_HANDOFF_V1
    const crossModelContinuity = new CrossModelContinuityStore(api.resolvePath("~/.openclaw/data/forge-discord-monitor/cross-model-handoff.json"), api.logger, {
        ttlMs: config.continuity.nativeJournalRetentionMs,
        maxNativeExchanges: config.continuity.nativeDeltaMaxExchanges,
        maxStoredExchanges: config.continuity.nativeJournalMaxStoredExchanges
    });
    // FORGE_MONITOR_SENTRY_BYPASS_V1
    let sentryBypassUntil = 0;
    const sentryBypassActive = () => {
        if (sentryBypassUntil <= Date.now()) {
            sentryBypassUntil = 0;
            return false;
        }
        return true;
    };
    const sentryBypassRemainingMs = () => sentryBypassActive() ? Math.max(0, sentryBypassUntil - Date.now()) : 0;
    const engine = new MonitorEngine(config);
    const assistanceGate = new AssistanceDispatchGate(config);
    const ruleFiles = new KbRuleFileStore(config.ruleFiles, config, {
        warn: (message) => api.logger.warn(message)
    });
    const recentChannelContext = new PersistentRecentChannelContext(config.contextMessageCount, api.resolvePath("~/.openclaw/data/forge-discord-monitor/recent-channel-context"), api.logger);
    const audit = new JsonlAuditLogger(config.logging, {
        warn: (message) => api.logger.warn(message)
    });
    const activity = new MessageActivityCounter(config.activityTracking, {
        warn: (message) => api.logger.warn(message)
    });
    const transportFactory = async () => {
        if (!api.config) {
            throw new Error("OpenClaw configuration is unavailable.");
        }
        const token = await resolveDiscordBotToken(api.config, config.moderationActions.discordAccountId);
        return new DiscordRestModerationTransport(token);
    };
    const logModerationAction = (record) => {
        audit.log(moderationActionResult(record), "moderation-action");
    };
    const moderationActions = new ModerationActionController(config.moderationActions, transportFactory, {
        onAction: logModerationAction,
        warn: (message) => api.logger.warn(message)
    });
    const automaticAntiSpam = new AutomaticAntiSpamController(config.moderationActions, transportFactory, {
        onAction: logModerationAction,
        warn: (message) => api.logger.warn(message)
    });
    const crossChannelSpam = new CrossChannelSpamController(config.moderationActions.crossChannelSpam, transportFactory, {
        onIncident: (incident) => audit.logCrossChannelSpam(incident),
        warn: (message) => api.logger.warn(message)
    });
    const pendingReplies = new Map();
    // FORGE_PERSISTENT_PENDING_CONTINUITY_V1
    const pendingContinuityInputs = new PersistentPendingContinuityMap(api.resolvePath("~/.openclaw/data/forge-discord-monitor/pending-continuity.json"), api.logger);
    const continuityRuns = new Map();
    const continuityRunSides = new Map();
    const liveRoomContextDiagnostics = new Map();
    // FORGE_LIVE_ROOM_CONTEXT_BRIDGE_V122A
    // Export the exact already-generated bounded room chronology by runId.
    // Transport-only bridge: no extra model-visible text, no policy, no persistence.
    globalThis[Symbol.for("forge.live-room-context.v1")] = {
        pendingRuns: liveRoomContextDiagnostics
    };
    let lastLiveRoomContextDiagnosticResult;
    const pendingPromptContexts = new Map();
    const attachedPromptContexts = new Map();
    const verifiedPromptContextRunIds = new Set();
    const loggedUsageRunIds = new Map();
    const maxPromptContexts = Math.max(1, config.assistanceDispatch.maxCooldownEntries, config.moderationDispatch.maxCooldownEntries);
    let pendingPromptContextCount = [...pendingPromptContexts.values()].reduce((total, records) => total + records.length, 0);
    const cleanupContinuityInputs = (now) => {
        for (const [sessionKey, records] of pendingContinuityInputs) {
            const retained = records.filter((record) => record.expiresAt > now);
            if (retained.length > 0)
                pendingContinuityInputs.set(sessionKey, retained);
            else
                pendingContinuityInputs.delete(sessionKey);
        }
    };
    const stageContinuityInput = (event, context, message) => {
        if (event.channel !== "discord")
            return;
        const sessionKey = event.sessionKey ?? context.sessionKey;
        const channelId = message?.channelId ?? resolveChannelId(context);
        const content = (event.content || event.body || "").trim();
        if (!sessionKey || !channelId || !content)
            return;
        const now = Date.now();
        cleanupContinuityInputs(now);
        const records = pendingContinuityInputs.get(sessionKey) ?? [];
        const nativeLunaEligible = event.isGroup !== false &&
            !config.routingGate.alwaysDispatchChannelIds.includes(channelId) &&
            !config.excludedChannelIds.includes(channelId);
        records.push({
            sessionKey,
            channelId,
            ...(message?.userId || event.senderId || context.senderId
                ? { userId: message?.userId ?? event.senderId ?? context.senderId }
                : {}),
            ...(message?.userName || event.senderName || event.senderUsername
                ? { userName: message?.userName ?? event.senderName ?? event.senderUsername }
                : {}),
            ...(message?.messageId || event.messageId
                ? { messageId: message?.messageId ?? event.messageId }
                : {}),
            content,
            isGroup: event.isGroup !== false,
            nativeLunaEligible,
            timestamp: event.timestamp ?? now,
            expiresAt: now + 2 * 60 * 60_000
        });
        pendingContinuityInputs.set(sessionKey, records.slice(-8));
        // FORGE_CONTINUITY_STAGE_DIAG_V1
        api.logger.info(JSON.stringify({
            kind: "forge-continuity-stage-diag-v1",
            sessionKey,
            channelId,
            isGroup: event.isGroup !== false,
            contentChars: content.length,
            hasCanary: content.includes("FORGE_CANARY_"),
            pendingForSession: Math.min(records.length, 8)
        }));
        while (pendingContinuityInputs.size > 512) {
            const oldest = pendingContinuityInputs.keys().next().value;
            if (!oldest)
                break;
            pendingContinuityInputs.delete(oldest);
        }
    };
    const consumeContinuityInput = (event, context) => {
        const runId = context.runId;
        if (runId) {
            const existing = continuityRuns.get(runId);
            if (existing)
                return existing.input;
        }
        const now = Date.now();
        cleanupContinuityInputs(now);
        const exactSessionKey = context.sessionKey?.trim();
        const channelHints = [context.channel, context.channelId]
            .filter((value) => typeof value === "string" && value.length > 0)
            .map(stripConversationPrefix);
        const all = [...pendingContinuityInputs.entries()].flatMap(([sessionKey, records]) => records.map((record, index) => ({ sessionKey, record, index })));
        const exact = exactSessionKey
            ? all.filter((candidate) => candidate.sessionKey === exactSessionKey)
            : [];
        const pool = exact.length > 0 ? exact : all;
        const channelMatches = pool.filter(({ record }) => channelHints.some((hint) => hint.includes(record.channelId)));
        const candidates = channelMatches.length > 0 ? channelMatches : pool;
        let selected;
        let bestPromptPosition = -1;
        // FORGE_CROSS_MODEL_CONTINUITY_NORMALIZED_MATCH_V1
        // OpenClaw may normalize whitespace between Discord dispatch and prompt
        // construction. Prefer the exact text match, but fall back to matching
        // whitespace-normalized text so the completed exchange is not lost.
        const normalizedPrompt = event.prompt.replace(/\s+/g, " ").trim();
        for (const candidate of candidates) {
            const exactPosition = event.prompt.lastIndexOf(candidate.record.content);
            const position = exactPosition >= 0
                ? exactPosition
                : normalizedPrompt.lastIndexOf(candidate.record.content.replace(/\s+/g, " ").trim());
            if (position > bestPromptPosition) {
                bestPromptPosition = position;
                selected = candidate;
            }
        }
        // FORGE_CONTINUITY_CONSUME_DIAG_V1
        api.logger.info(JSON.stringify({
            kind: "forge-continuity-consume-diag-v1",
            runId: context.runId ?? null,
            exactSessionKey: exactSessionKey ?? null,
            channelHints,
            allCount: all.length,
            exactCount: exact.length,
            poolCount: pool.length,
            channelMatchCount: channelMatches.length,
            candidateCount: candidates.length,
            candidateCanaryCount: candidates.filter((candidate) => candidate.record.content.includes("FORGE_CANARY_")).length,
            normalizedPromptChars: normalizedPrompt.length,
            selected: Boolean(selected),
            bestPromptPosition
        }));
        if (!selected)
            return;
        const ownerRecords = pendingContinuityInputs.get(selected.sessionKey);
        if (!ownerRecords)
            return;
        const [record] = ownerRecords.splice(selected.index, 1);
        if (!record)
            return;
        if (ownerRecords.length === 0) {
            pendingContinuityInputs.delete(selected.sessionKey);
        }
        else {
            // Persist the claim when other pending records remain.
            pendingContinuityInputs.set(selected.sessionKey, ownerRecords);
        }
        return record;
    };
    const logPromptContext = (record, eventType, options = {}) => {
        audit.logContextDelivery({
            eventType,
            message: record.message,
            contextId: record.contextId,
            sessionKey: record.sessionKey,
            ...(options.runId ? { runId: options.runId } : {}),
            previousMessageCount: record.previousMessageCount,
            previousMessageIds: record.previousMessageIds,
            previousMessageHashes: record.previousMessageHashes,
            contextLength: record.text.length,
            contextHash: record.contextHash,
            ...(options.reason ? { reason: options.reason } : {})
        });
    };
    const expirePromptContext = (record, reason) => {
        logPromptContext(record, "context-expired", { reason });
    };
    const cleanupPromptContexts = (now) => {
        for (const [sessionKey, records] of pendingPromptContexts) {
            const retained = records.filter((record) => {
                if (record.expiresAt > now)
                    return true;
                pendingPromptContextCount -= 1;
                expirePromptContext(record, "expired-before-prompt-build");
                return false;
            });
            if (retained.length > 0)
                pendingPromptContexts.set(sessionKey, retained);
            else
                pendingPromptContexts.delete(sessionKey);
        }
        for (const [runId, record] of attachedPromptContexts) {
            if (record.expiresAt <= now) {
                attachedPromptContexts.delete(runId);
                verifiedPromptContextRunIds.delete(runId);
            }
        }
        for (const [runId, loggedAt] of loggedUsageRunIds) {
            if (loggedAt + 10 * 60 * 1000 <= now)
                loggedUsageRunIds.delete(runId);
        }
    };
    const trimPromptContexts = () => {
        while (pendingPromptContextCount > maxPromptContexts) {
            const firstSession = pendingPromptContexts.entries().next().value;
            if (!firstSession) {
                pendingPromptContextCount = [...pendingPromptContexts.values()].reduce((total, records) => total + records.length, 0);
                return;
            }
            const [sessionKey, records] = firstSession;
            const removed = records.shift();
            if (removed) {
                pendingPromptContextCount -= 1;
                expirePromptContext(removed, "pending-context-capacity-reached");
            }
            if (records.length === 0)
                pendingPromptContexts.delete(sessionKey);
        }
    };
    const stagePromptContext = (params) => {
        const stagedAt = Date.now();
        cleanupPromptContexts(stagedAt);
        const record = {
            contextId: `forge-context-${contentDigest(`${params.sessionKey}:${params.summon.message.messageId ?? ""}:${params.summon.message.timestamp}:${params.summon.message.userId}:${params.summon.message.content}`)}`,
            sessionKey: params.sessionKey,
            gated: params.gated,
            text: params.text,
            triggerContent: params.summon.message.content,
            message: params.summon.message,
            previousMessageCount: params.previousMessages.length,
            previousMessageIds: params.previousMessages
                .map((message) => message.messageId)
                .filter((messageId) => Boolean(messageId)),
            previousMessageHashes: params.previousMessages.map((message) => contentDigest(message.content)),
            contextHash: contentDigest(params.text),
            stagedAt,
            expiresAt: stagedAt + Math.max(1_000, params.ttlMs)
        };
        const records = pendingPromptContexts.get(params.sessionKey) ?? [];
        records.push(record);
        pendingPromptContexts.delete(params.sessionKey);
        pendingPromptContexts.set(params.sessionKey, records);
        pendingPromptContextCount += 1;
        trimPromptContexts();
        logPromptContext(record, "context-staged");
        return record;
    };
    const consumePromptContext = (event, context) => {
        const now = Date.now();
        cleanupPromptContexts(now);
        if (context.runId) {
            const attached = attachedPromptContexts.get(context.runId);
            if (attached)
                return attached;
        }
        if (context.messageProvider &&
            context.messageProvider !== "discord") {
            return;
        }
        const sessionKey = context.sessionKey?.trim();
        const channelHints = [context.channel, context.channelId]
            .filter((value) => typeof value === "string" && value.length > 0)
            .map(stripConversationPrefix);
        const matchesChannel = (record) => channelHints.some((hint) => hint.includes(record.message.channelId));
        const exactRecords = sessionKey
            ? pendingPromptContexts.get(sessionKey)
            : undefined;
        let candidates;
        if (exactRecords && exactRecords.length > 0 && sessionKey) {
            const exactCandidates = exactRecords.map((record, index) => ({
                sessionKey,
                record,
                index
            }));
            const channelMatches = exactCandidates.filter(({ record }) => matchesChannel(record));
            candidates = channelMatches.length > 0
                ? channelMatches
                : exactCandidates;
        }
        else {
            const allCandidates = [...pendingPromptContexts.entries()].flatMap(([ownerSessionKey, records]) => records.map((record, index) => ({
                sessionKey: ownerSessionKey,
                record,
                index
            })));
            const channelMatches = allCandidates.filter(({ record }) => matchesChannel(record));
            candidates = channelMatches.length > 0
                ? channelMatches
                : allCandidates;
        }
        let selected;
        let bestPromptPosition = -1;
        for (const candidate of candidates) {
            const position = candidate.record.triggerContent
                ? event.prompt.lastIndexOf(candidate.record.triggerContent)
                : -1;
            if (position > bestPromptPosition) {
                bestPromptPosition = position;
                selected = candidate;
            }
        }
        if (!selected) {
            const mediaChannelMatches = candidates.filter(({ record }) => record.triggerContent.length === 0 && matchesChannel(record));
            if (mediaChannelMatches.length !== 1)
                return;
            const onlyMatch = mediaChannelMatches[0];
            if (!onlyMatch)
                return;
            selected = onlyMatch;
        }
        const ownerRecords = pendingPromptContexts.get(selected.sessionKey);
        if (!ownerRecords)
            return;
        const [record] = ownerRecords.splice(selected.index, 1);
        if (!record)
            return;
        pendingPromptContextCount -= 1;
        if (ownerRecords.length === 0) {
            pendingPromptContexts.delete(selected.sessionKey);
        }
        if (context.runId)
            attachedPromptContexts.set(context.runId, record);
        logPromptContext(record, "context-attached", {
            ...(context.runId ? { runId: context.runId } : {})
        });
        return record;
    };
    const recentInboundMetadata = new Map();
    const inboundMetadataKey = (message) => `${message.channelId}:${message.userId}:${contentDigest(message.content)}`;
    const rememberInboundMetadata = (message) => {
        const now = message.timestamp;
        for (const [key, metadata] of recentInboundMetadata) {
            if (metadata.timestamp + 60_000 <= now)
                recentInboundMetadata.delete(key);
        }
        recentInboundMetadata.set(inboundMetadataKey(message), {
            ...(message.messageId ? { messageId: message.messageId } : {}),
            ...(message.guildId ? { guildId: message.guildId } : {}),
            timestamp: message.timestamp
        });
        while (recentInboundMetadata.size > 10_000) {
            const oldest = recentInboundMetadata.keys().next().value;
            if (!oldest)
                break;
            recentInboundMetadata.delete(oldest);
        }
    };
    const enrichFromInboundMetadata = (message) => {
        const metadata = recentInboundMetadata.get(inboundMetadataKey(message));
        if (!metadata ||
            Math.abs(message.timestamp - metadata.timestamp) > 60_000) {
            return;
        }
        if (metadata.messageId)
            message.messageId = metadata.messageId;
        if (metadata.guildId)
            message.guildId = metadata.guildId;
    };
    const pendingReplyKey = (sessionKey, channelId) => `${sessionKey}:${channelId}`;
    const findPendingReply = (sessionKey, conversationId) => {
        if (!sessionKey)
            return;
        const now = Date.now();
        for (const [key, pending] of pendingReplies) {
            if (pending.expiresAt <= now)
                pendingReplies.delete(key);
        }
        const channelId = conversationId
            ? stripConversationPrefix(conversationId)
            : undefined;
        const exactKey = channelId
            ? pendingReplyKey(sessionKey, channelId)
            : undefined;
        if (exactKey) {
            const exact = pendingReplies.get(exactKey);
            if (exact)
                return exact;
        }
        const matches = [...pendingReplies.entries()].filter(([key]) => key.startsWith(`${sessionKey}:`));
        return matches.length === 1 ? matches[0]?.[1] : undefined;
    };
    const onLlmInput = api.on;
    const onReplyPayloadSending = api.on;
    const onLlmOutput = api.on;
    const onBeforeToolCall = api.on;
    // FORGE_DISCORD_LOOKUP_HARD_DISABLE_V1
    onBeforeToolCall("before_tool_call", (event) => {
        if (event.toolName !== "message")
            return;
        const action = typeof event.params.action === "string"
            ? event.params.action.trim().toLowerCase()
            : "";
        if (!["read", "search", "fetch"].includes(action))
            return;
        return {
            block: true,
            blockReason: "Discord history lookup is temporarily disabled while Forge continuity is under test."
        };
    }, { priority: 2_000, matcher: ["message"] });
    api.on("message_received", async (event, context) => {
        await ruleFiles.refreshIfDue();
        const message = toMonitorMessage(event, context, config);
        if (!message)
            return;
        rememberInboundMetadata(message);
        recentChannelContext.remember(message);
        const result = engine.process(message);
        if (result) {
            audit.log(result);
            activity.record(result);
            let crossChannelIncident = false;
            try {
                crossChannelIncident = Boolean(await crossChannelSpam.evaluate(result));
            }
            catch (error) {
                api.logger.warn(`Forge monitor cross-channel spam action failed safely: ${String(error)}`);
            }
            try {
                if (!crossChannelIncident) {
                    await automaticAntiSpam.evaluate(result);
                }
            }
            catch (error) {
                api.logger.warn(`Forge monitor automatic anti-spam action failed safely: ${String(error)}`);
            }
        }
    });
    if (api.registerTool &&
        (config.moderationActions.judgement.enabled ||
            config.moderationActions.temporaryTimeouts.enabled)) {
        const parameters = Type.Object({
            reviewId: Type.String(),
            action: Type.Union([
                Type.Literal("warn"),
                Type.Literal("timeout")
            ]),
            reason: Type.String({
                minLength: 1,
                maxLength: 500
            }),
            warning: Type.Optional(Type.String({
                maxLength: config.moderationActions.judgement.maxWarningChars
            })),
            durationMinutes: Type.Optional(Type.Integer({ minimum: 1 }))
        }, { additionalProperties: false });
        api.registerTool({
            name: "forge_moderation_action",
            label: "Discord Moderation Action",
            description: "Discord moderation action.",
            parameters,
            executionMode: "sequential",
            async execute(_toolCallId, params) {
                const record = await moderationActions.execute(params);
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify({
                                ok: true,
                                action: record.action,
                                userId: record.message.userId,
                                channelId: record.message.channelId,
                                timeoutMinutes: record.timeoutMinutes ?? null
                            })
                        }
                    ],
                    details: {
                        action: record.action,
                        userId: record.message.userId,
                        channelId: record.message.channelId,
                        timeoutMinutes: record.timeoutMinutes ?? null
                    }
                };
            }
        }, { name: "forge_moderation_action" });
    }
    api.registerCommand?.({
        name: "activity",
        description: "Show locally counted Discord messages per username.",
        acceptsArgs: true,
        requireAuth: false,
        handler: async (context) => {
            if (!config.activityTracking.enabled) {
                return {
                    text: "Forge activity tracking is disabled.",
                    isError: true
                };
            }
            const args = (context.args ?? "")
                .trim()
                .split(/\s+/u)
                .filter(Boolean);
            if (args.length > 2 ||
                args.some((value) => !/^\d+$/u.test(value))) {
                return {
                    text: "Usage: /activity [days] [limit]",
                    isError: true
                };
            }
            const days = args[0]
                ? Number.parseInt(args[0], 10)
                : config.activityTracking.defaultWindowDays;
            const limit = args[1]
                ? Number.parseInt(args[1], 10)
                : config.activityTracking.maxReportUsers;
            if (days < 1 ||
                days >= config.activityTracking.retentionDays ||
                limit < 1 ||
                limit > config.activityTracking.maxReportUsers) {
                return {
                    text: `Days must be 1-${config.activityTracking.retentionDays - 1}; limit must be 1-${config.activityTracking.maxReportUsers}.`,
                    isError: true
                };
            }
            const report = await activity.report(days, limit);
            const rows = report.rows.map((row, index) => `${index + 1}. ${row.userName ?? "Username pending"} — ${row.messageCount.toLocaleString("en-GB")}`);
            const missingUserNames = report.rows.filter((row) => !row.userName).length;
            return {
                text: [
                    `Forge activity — last ${report.windowDays} days`,
                    `${report.totalMessages.toLocaleString("en-GB")} assessed messages from ${report.totalUsers.toLocaleString("en-GB")} users.`,
                    ...(rows.length > 0 ? rows : ["No messages counted yet."]),
                    ...(missingUserNames > 0
                        ? [
                            `${missingUserNames} legacy username${missingUserNames === 1 ? " is" : "s are"} pending until ${missingUserNames === 1 ? "that user next posts" : "those users next post"}.`
                        ]
                        : []),
                    "Hourly rolling-window precision; counting starts when this version is installed."
                ].join("\n")
            };
        }
    });
    api.registerCommand?.({
        name: "roomdiag",
        description: "Show the latest Forge live-room context delivery diagnostic.",
        acceptsArgs: false,
        requireAuth: true,
        exposeSenderIsOwner: true,
        handler: (context) => {
            if (context.senderIsOwner !== true) {
                return {
                    text: "/roomdiag is owner-only.",
                    isError: true
                };
            }
            const latest = lastLiveRoomContextDiagnosticResult;
            if (!latest) {
                return {
                    text: "No live-room context diagnostic has completed since the gateway started."
                };
            }
            return {
                text: [
                    `Room context delivery: ${latest.verified ? "VERIFIED" : "MISSING"}`,
                    `Run: ${latest.runId}`,
                    `Channel: ${latest.channelId}`,
                    `Messages: ${latest.messageCount}`,
                    `Hash: ${latest.roomContextHash}`,
                    `Room chars: ${latest.roomContextChars}`,
                    `Prompt chars: ${latest.promptChars}`,
                    `Offsets: ${latest.startOffset}..${latest.endOffset}`,
                    `Checked: ${new Date(latest.checkedAt).toISOString()}`
                ].join("\n")
            };
        }
    });
    api.registerCommand?.({
        name: "sentry",
        description: "Turn the Discord Sentry attention gate on or temporarily off.",
        acceptsArgs: true,
        requireAuth: true,
        exposeSenderIsOwner: true,
        handler: (context) => {
            if (context.senderIsOwner !== true) {
                return {
                    text: "/sentry is owner-only.",
                    isError: true
                };
            }
            const argument = (context.args ?? "").trim().toLowerCase();
            if (!argument) {
                const remainingMs = sentryBypassRemainingMs();
                if (remainingMs <= 0)
                    return { text: "Sentry is on." };
                const remainingMinutes = Math.max(1, Math.ceil(remainingMs / 60_000));
                return {
                    text: `Sentry is off with about ${remainingMinutes} minute${remainingMinutes === 1 ? "" : "s"} remaining. Use /sentry on to restore it early.`
                };
            }
            if (argument === "on") {
                sentryBypassUntil = 0;
                gatewayModelRouter.clear();
                api.logger.info("Forge Sentry attention gate restored by owner.");
                return { text: "Sentry on." };
            }
            const offMatch = argument.match(/^off(?:\s+(\d+))?$/u);
            if (!offMatch) {
                return {
                    text: "Usage: /sentry on | /sentry off [hours] (default 24; range 1-24)",
                    isError: true
                };
            }
            const hours = offMatch[1]
                ? Number.parseInt(offMatch[1], 10)
                : 24;
            if (hours < 1 || hours > 24) {
                return {
                    text: "Hours must be between 1 and 24.",
                    isError: true
                };
            }
            sentryBypassUntil = Date.now() + hours * 60 * 60 * 1000;
            gatewayModelRouter.clear();
            const expiresAt = new Date(sentryBypassUntil).toISOString();
            api.logger.info(`Forge Sentry attention gate disabled by owner for ${hours} hour${hours === 1 ? "" : "s"}; expires ${expiresAt}.`);
            return {
                text: `Sentry off for ${hours} hour${hours === 1 ? "" : "s"}. Every Discord group message now reaches Forge judgement through the normal Sol/Luna routing. It auto-restores; use /sentry on to restore it early.`
            };
        }
    });
    const usageCommands = [
        {
            name: "tokens",
            description: "Show hourly Forge token usage by turn type.",
            format: formatTokenUsageReport
        },
        {
            name: "credits",
            description: "Show hourly Forge Codex-credit usage by turn type.",
            format: formatCreditUsageReport
        }
    ];
    for (const command of usageCommands) {
        api.registerCommand?.({
            name: command.name,
            description: command.description,
            acceptsArgs: true,
            requireAuth: false,
            handler: async (context) => {
                if (!config.logging.enabled) {
                    return {
                        text: "Forge usage reporting requires audit logging to be enabled.",
                        isError: true
                    };
                }
                const argument = (context.args ?? "").trim();
                if (!/^\d+$/u.test(argument)) {
                    return {
                        text: `Usage: /${command.name} <hours> (1-24)`,
                        isError: true
                    };
                }
                const hours = Number.parseInt(argument, 10);
                if (hours < 1 || hours > 24) {
                    return {
                        text: "Hours must be between 1 and 24.",
                        isError: true
                    };
                }
                const report = await readTurnUsageReport(config.logging, hours);
                return { text: command.format(report) };
            }
        });
    }
    api.on("before_dispatch", async (event, context) => {
        await ruleFiles.refreshIfDue();
        const activityUserId = event.senderId ?? context.senderId;
        const activityUserName = event.senderName ?? event.senderUsername;
        if (activityUserId && activityUserName) {
            activity.rememberUserName(event.timestamp ?? Date.now(), activityUserId, activityUserName);
        }
        if (shouldSuppressMentionOnlyDispatch(event, context, config)) {
            return { handled: true };
        }
        const sentryBypass = event.channel === "discord" &&
            event.isGroup !== false &&
            sentryBypassActive();
        if (sentryBypass) {
            const message = toDispatchMonitorMessage(event, context, config, Date.now);
            if (!message || message.isBot)
                return { handled: true };
            if (crossChannelSpam.recentIncident(message))
                return { handled: true };
            const sessionKey = event.sessionKey ?? context.sessionKey;
            const discordConfig = readRecord(readRecord(api.config?.channels)?.discord);
            const staffUserIds = new Set(readStringArray(discordConfig?.allowFrom));
            const dispatchContent = (event.body ?? event.content).trim();
            const isSlashCommand = config.routingGate.passSlashCommands &&
                dispatchContent.startsWith("/") &&
                !dispatchContent.startsWith("/ ");
            const alwaysSolChannel = config.routingGate.alwaysDispatchChannelIds.includes(message.channelId);
            const addressedToForge = Boolean(message.directForgeMention || message.replyToForge);
            const authorIsStaff = staffUserIds.has(message.userId);
            const routeToGatewayModel = !alwaysSolChannel &&
                !isSlashCommand &&
                !(addressedToForge && authorIsStaff);
            if (routeToGatewayModel) {
                if (!sessionKey) {
                    api.logger.warn("Forge Sentry bypass could not stage the Luna route because OpenClaw supplied no session key; suppressing rather than falling through to Sol.");
                    return { handled: true };
                }
                gatewayModelRouter.stage({
                    sessionKey,
                    channelId: message.channelId,
                    triggerContent: message.content
                });
            }
            stageContinuityInput(event, context, message);
            return;
        }
        const suppress = shouldSuppressDispatch(event, context, config);
        const summon = assistanceGate.evaluate(event, context);
        if (!summon) {
            if (suppress)
                return { handled: true };
            stageContinuityInput(event, context);
            return;
        }
        enrichFromInboundMetadata(summon.message);
        if (crossChannelSpam.recentIncident(summon.message)) {
            // The exact message was already captured by the deterministic spam
            // controller. Do not spend an AI turn responding to a deleted post.
            return { handled: true };
        }
        stageContinuityInput(event, context, summon.message);
        const sessionKey = event.sessionKey ?? context.sessionKey;
        // FORGE_ALLOWFROM_ADDRESS_ROUTING_V1
        const discordConfig = readRecord(readRecord(api.config?.channels)?.discord);
        const staffUserIds = new Set(readStringArray(discordConfig?.allowFrom));
        const dispatchContent = (event.body ?? event.content).trim();
        const isSlashCommand = config.routingGate.passSlashCommands &&
            dispatchContent.startsWith("/") &&
            !dispatchContent.startsWith("/ ");
        const alwaysSolChannel = config.routingGate.alwaysDispatchChannelIds.includes(summon.message.channelId);
        const addressedToForge = Boolean(summon.message.directForgeMention || summon.message.replyToForge);
        const authorIsStaff = staffUserIds.has(summon.message.userId);
        const routeToGatewayModel = event.isGroup !== false &&
            !alwaysSolChannel &&
            !isSlashCommand &&
            (suppress || (addressedToForge && !authorIsStaff));
        if (routeToGatewayModel && sessionKey) {
            gatewayModelRouter.stage({
                sessionKey,
                channelId: summon.message.channelId,
                triggerContent: summon.message.content
            });
        }
        const moderationReviewId = event.isGroup === false
            ? undefined
            : moderationActions.registerReview(summon);
        const replyTrackingTtlMs = summon.category === "BOTH"
            ? Math.max(config.assistanceDispatch.replyTrackingTtlMs, config.moderationDispatch.replyTrackingTtlMs)
            : summon.category === "ASSISTANCE"
                ? config.assistanceDispatch.replyTrackingTtlMs
                : config.moderationDispatch.replyTrackingTtlMs;
        let stagedPromptContext;
        if (moderationReviewId) {
            const text = `[review-id:${moderationReviewId}]`;
            if (sessionKey) {
                stagedPromptContext = stagePromptContext({
                    sessionKey,
                    gated: suppress,
                    text,
                    summon,
                    previousMessages: [],
                    ttlMs: replyTrackingTtlMs
                });
            }
            else {
                api.logger.warn("Forge moderation review was created without a session key; review binding was not attached.");
            }
        }
        audit.log(invocationResult(summon, config), "forge-invocation");
        if (sessionKey) {
            const now = summon.message.timestamp;
            for (const [key, pending] of pendingReplies) {
                if (pending.expiresAt <= now)
                    pendingReplies.delete(key);
            }
            pendingReplies.set(pendingReplyKey(sessionKey, summon.message.channelId), {
                summon,
                gated: suppress,
                ...(stagedPromptContext ? { promptContext: stagedPromptContext } : {}),
                expiresAt: now + replyTrackingTtlMs
            });
            const maxPendingReplies = Math.max(config.assistanceDispatch.maxCooldownEntries, config.moderationDispatch.maxCooldownEntries);
            while (pendingReplies.size > maxPendingReplies) {
                const oldestKey = pendingReplies.keys().next().value;
                if (!oldestKey)
                    break;
                pendingReplies.delete(oldestKey);
            }
        }
        return;
    }, { priority: 1_000, timeoutMs: 1_000 });
    api.on("before_model_resolve", (event, context) => {
        const resolved = gatewayModelRouter.resolve(event, context);
        if (context.runId) {
            continuityRunSides.set(context.runId, resolved?.modelOverride
                ? continuitySideForModel(resolved.modelOverride)
                : "principal");
            while (continuityRunSides.size > 512) {
                const oldest = continuityRunSides.keys().next().value;
                if (!oldest)
                    break;
                continuityRunSides.delete(oldest);
            }
        }
        return resolved;
    }, { priority: 1_000, timeoutMs: 1_000 });
    // FORGE_MONITOR_DISPOSABLE_NATIVE_TURN_V1_2
    // FORGE_CROSS_MODEL_HANDOFF_V1
    api.on("before_prompt_build", (event, context) => {
        const staged = consumePromptContext(event, context);
        const runId = context.runId;
        const existingRun = runId ? continuityRuns.get(runId) : undefined;
        const continuityInput = existingRun?.input ?? consumeContinuityInput(event, context);
        // FORGE_PERSISTENT_RECENT_CHANNEL_CONTEXT_V1
        const liveRecentMessages = continuityInput
            ? recentChannelContext.previous({
                timestamp: continuityInput.timestamp,
                userId: continuityInput.userId ?? "",
                channelId: continuityInput.channelId,
                content: continuityInput.content,
                isBot: false
            }).slice(-10) // FORGE_AMBIENT_CONTEXT_10_FALLBACK_V1
            : [];
        const liveRecentText = liveRecentMessages.length > 0 && continuityInput
            ? liveRecentMessages
                .map((message) => {
                const author = message.userName
                    ? `${message.userName} (${message.userId})`
                    : message.userId;
                const content = message.content.trim() || "[no text]";
                const visibility = continuityInput.isGroup ? "public" : "DM";
                const messageId = message.messageId
                    ? ` | message ${message.messageId}`
                    : "";
                return [
                    `[Discord | ${visibility} | channel ${message.channelId} | ${new Date(message.timestamp).toISOString()} | user ${author}${messageId}]`,
                    content
                ].join("\n");
            })
                .join("\n\n")
            : undefined;
        if (liveRecentText && runId && continuityInput) {
            const roomContextHash = contentDigest(liveRecentText);
            liveRoomContextDiagnostics.set(runId, {
                text: liveRecentText,
                hash: roomContextHash,
                channelId: continuityInput.channelId,
                messageCount: liveRecentMessages.length,
                createdAt: Date.now()
            });
            while (liveRoomContextDiagnostics.size > 512) {
                const oldestRunId = liveRoomContextDiagnostics.keys().next().value;
                if (!oldestRunId)
                    break;
                liveRoomContextDiagnostics.delete(oldestRunId);
            }
            api.logger.info(JSON.stringify({
                kind: "forge-live-room-context-diag-v1",
                runId,
                channelId: continuityInput.channelId,
                messageCount: liveRecentMessages.length,
                roomContextHash,
                roomContextChars: liveRecentText.length
            }));
        }
        const side = existingRun?.side ??
            (runId ? continuityRunSides.get(runId) ?? "principal" : "principal");
        const handoffText = existingRun?.handoffText;
        const acknowledgeIds = existingRun?.acknowledgeIds ?? [];
        let nativeAcknowledgeIds = existingRun?.nativeAcknowledgeIds ?? [];
        if (!existingRun && continuityInput) {
            if (runId) {
                // FORGE_CROSS_MODEL_NATIVE_DELTA_V1
                // Both warm model threads receive the other side's newest completed
                // Discord exchanges as native chronology. Public group exchanges and
                // private DMs are labelled separately by the bridge.
                const nativeDelta = crossModelContinuity.nativeDeltaFor(side);
                nativeAcknowledgeIds = nativeDelta?.acknowledgeIds ?? [];
                if (nativeDelta)
                    publishForgeNativeDelta(runId, side, nativeDelta);
                continuityRuns.set(runId, {
                    input: continuityInput,
                    side,
                    acknowledgeIds,
                    nativeAcknowledgeIds
                });
            }
        }
        if (side === "luna" && (staged || liveRecentText) && runId) {
            const policyKey = Symbol.for("forge.native-thread-rollback.v1");
            const globals = globalThis;
            let policy = readRecord(globals[policyKey]);
            if (!policy) {
                policy = {};
                globals[policyKey] = policy;
            }
            const disposableRuns = policy.disposableRuns instanceof Map
                ? policy.disposableRuns
                : new Map();
            policy.disposableRuns = disposableRuns;
            disposableRuns.set(runId, { at: Date.now(), reason: "forge-monitor" });
            while (disposableRuns.size > 512) {
                const oldest = disposableRuns.keys().next().value;
                if (oldest === undefined)
                    break;
                disposableRuns.delete(oldest);
            }
        }
        // FORGE_TRANSIENT_CONTEXT_POSITION_EPHEMERAL_V3
        // Keep Luna's changing room transcript at the tail of the current turn so
        // the stable prompt prefix remains cache-friendly and the newest room
        // context stays adjacent to the request. Never duplicate the room block.
        // Principal/Sol retains the existing prepend ordering unchanged.
        const lunaLiveRecentText = side === "luna" ? liveRecentText : undefined;
        const prependContext = [
            staged?.text,
            side === "luna" ? undefined : liveRecentText,
            handoffText
        ]
            .filter((value) => Boolean(value))
            .join("\n\n");
        const appendContext = lunaLiveRecentText;
        return prependContext || appendContext
            ? {
                ...(prependContext ? { prependContext } : {}),
                ...(appendContext ? { appendContext } : {})
            }
            : undefined;
    }, { priority: 1_000 });
    onLlmInput("llm_input", (event, context) => {
        const runId = event.runId || context.runId;
        if (!runId)
            return;
        const liveRoomDiagnostic = liveRoomContextDiagnostics.get(runId);
        if (liveRoomDiagnostic) {
            const startOffset = event.prompt.indexOf(liveRoomDiagnostic.text);
            const verified = startOffset >= 0;
            const endOffset = verified
                ? startOffset + liveRoomDiagnostic.text.length
                : -1;
            lastLiveRoomContextDiagnosticResult = {
                runId,
                channelId: liveRoomDiagnostic.channelId,
                messageCount: liveRoomDiagnostic.messageCount,
                roomContextHash: liveRoomDiagnostic.hash,
                roomContextChars: liveRoomDiagnostic.text.length,
                promptChars: event.prompt.length,
                verified,
                startOffset,
                endOffset,
                checkedAt: Date.now()
            };
            api.logger.info(JSON.stringify({
                kind: "forge-live-room-context-llm-input-diag-v1",
                ...lastLiveRoomContextDiagnosticResult
            }));
        }
        if (verifiedPromptContextRunIds.has(runId))
            return;
        const record = attachedPromptContexts.get(runId);
        if (!record)
            return;
        const finalInput = [
            event.systemPrompt ?? "",
            event.prompt,
            JSON.stringify(event.historyMessages)
        ].join("\n");
        const verified = finalInput.includes(record.text);
        logPromptContext(record, verified ? "context-verified" : "context-missing", {
            runId,
            ...(!verified ? { reason: "not-present-in-llm-input" } : {})
        });
        verifiedPromptContextRunIds.add(runId);
        if (!verified) {
            api.logger.warn(`Forge monitor staged context ${record.contextId} for run ${runId}, but the final model input did not contain it.`);
        }
    });
    onLlmOutput("llm_output", (event, context) => {
        const runId = event.runId || context.runId;
        if (!runId)
            return;
        const continuityRun = continuityRuns.get(runId);
        if (continuityRun) {
            continuityRun.side = continuitySideForModel(event.model);
        }
        else {
            continuityRunSides.set(runId, continuitySideForModel(event.model));
        }
        cleanupPromptContexts(Date.now());
        const attached = attachedPromptContexts.get(runId);
        const pending = findPendingReply(context.sessionKey, context.conversationId);
        const promptContext = attached ?? pending?.promptContext;
        audit.logModelUsage({
            timestamp: Date.now(),
            runId,
            ...(context.sessionKey ? { sessionKey: context.sessionKey } : {}),
            ...(context.conversationId || context.channelId
                ? {
                    channelId: stripConversationPrefix(context.conversationId ?? context.channelId ?? "")
                }
                : {}),
            ...(promptContext ? { contextId: promptContext.contextId } : {}),
            ...(pending || promptContext
                ? { gatedHint: pending?.gated ?? promptContext?.gated ?? false }
                : {}),
            provider: event.provider,
            model: event.model,
            ...(event.resolvedRef ? { resolvedRef: event.resolvedRef } : {}),
            ...(event.reasoningEffort
                ? { reasoningEffort: event.reasoningEffort }
                : {}),
            ...(event.fastMode !== undefined ? { fastMode: event.fastMode } : {}),
            ...(event.contextTokenBudget !== undefined
                ? { contextTokenBudget: event.contextTokenBudget }
                : {}),
            ...(event.usage ? { usage: event.usage } : {})
        });
    });
    onReplyPayloadSending("reply_payload_sending", (event, context) => {
        // FORGE_MONITOR_MASS_MENTION_REPLY_PAYLOAD_V1
        if (event.channel === "discord" &&
            typeof event.payload?.text === "string") {
            event.payload.text = sanitizeAssistantMassMentions(event.payload.text);
        }
        if (event.channel === "discord" &&
            event.payload?.isFallbackNotice === true) {
            return {
                cancel: true,
                reason: "forge-monitor-hide-model-switch-notice"
            };
        }
        if (event.kind !== "final")
            return;
        const runId = event.runId ?? context.runId;
        if (runId && loggedUsageRunIds.has(runId))
            return;
        if (runId)
            loggedUsageRunIds.set(runId, Date.now());
        cleanupPromptContexts(Date.now());
        const sessionKey = event.sessionKey ?? context.sessionKey;
        const pending = findPendingReply(sessionKey, context.conversationId);
        const attached = runId
            ? attachedPromptContexts.get(runId)
            : undefined;
        const promptContext = attached ?? pending?.promptContext;
        const message = pending?.summon.message ?? promptContext?.message;
        const usage = event.usageState;
        const continuityRun = runId ? continuityRuns.get(runId) : undefined;
        const finalReply = event.payload?.text?.trim();
        if (continuityRun && finalReply) {
            // Native cross-model delivery is intentionally retained in the recovery
            // journal. Codex deduplicates by native thread ID, so warm threads skip
            // already-seen exchanges while a rebuilt thread can replay the latest
            // bounded shared chronology.
            if (runId && continuityRun.nativeAcknowledgeIds.length > 0) {
                confirmedNativeDeltaIds(runId, continuityRun.side, continuityRun.nativeAcknowledgeIds);
            }
            if (continuityRun.side === "principal") {
                const principalThreadId = forgeNativeDeltaBridge().currentPrincipalThreadId;
                if (principalThreadId) {
                    crossModelContinuity.syncPrincipalGeneration(principalThreadId, config.continuity.solFreshHistoryTokens);
                }
            }
            crossModelContinuity.record({
                timestamp: Date.now(),
                side: continuityRun.side,
                sessionKey: continuityRun.input.sessionKey,
                channelId: continuityRun.input.channelId,
                isGroup: continuityRun.input.isGroup,
                nativeLunaEligible: continuityRun.input.nativeLunaEligible,
                ...(continuityRun.input.userId
                    ? { userId: continuityRun.input.userId }
                    : {}),
                ...(continuityRun.input.userName
                    ? { userName: continuityRun.input.userName }
                    : {}),
                ...(continuityRun.input.messageId
                    ? { messageId: continuityRun.input.messageId }
                    : {}),
                userText: continuityRun.input.content,
                assistantText: finalReply
            });
        }
        if (runId) {
            releaseForgeNativeDeltaRun(runId);
            continuityRuns.delete(runId);
            continuityRunSides.delete(runId);
            liveRoomContextDiagnostics.delete(runId);
        }
        const contextDeliveryStatus = promptContext
            ? runId && verifiedPromptContextRunIds.has(runId)
                ? "verified"
                : attached
                    ? "attached"
                    : "staged"
            : "none";
        audit.logTurnUsage({
            timestamp: Date.now(),
            ...(runId ? { runId } : {}),
            ...(sessionKey ? { sessionKey } : {}),
            ...(message?.channelId ? { channelId: message.channelId } : {}),
            ...(message?.messageId ? { messageId: message.messageId } : {}),
            ...(message?.guildId ? { guildId: message.guildId } : {}),
            ...(message?.userId ? { userId: message.userId } : {}),
            gated: pending?.gated ?? promptContext?.gated ?? false,
            ...(promptContext ? { contextId: promptContext.contextId } : {}),
            contextDeliveryStatus,
            ...(usage?.provider ? { provider: usage.provider } : {}),
            ...(usage?.model ? { model: usage.model } : {}),
            ...(usage?.resolvedRef ? { resolvedRef: usage.resolvedRef } : {}),
            ...(usage?.reasoningEffort
                ? { reasoningEffort: usage.reasoningEffort }
                : {}),
            ...(usage?.fastMode !== undefined
                ? { fastMode: usage.fastMode }
                : {}),
            ...(usage?.fallbackUsed !== undefined
                ? { fallbackUsed: usage.fallbackUsed }
                : {}),
            ...(usage?.durationMs !== undefined
                ? { durationMs: usage.durationMs }
                : {}),
            ...(usage?.turnUsd !== undefined ? { turnUsd: usage.turnUsd } : {}),
            ...(usage?.contextUsedTokens !== undefined
                ? { contextUsedTokens: usage.contextUsedTokens }
                : {}),
            ...(usage?.contextTokenBudget !== undefined
                ? { contextTokenBudget: usage.contextTokenBudget }
                : {}),
            ...(usage?.usage ? { usage: usage.usage } : {}),
            ...(usage?.lastUsage ? { lastUsage: usage.lastUsage } : {})
        });
    });
    api.on("message_sending", (event, context) => {
        if (!context.sessionKey || event.content.trim().length === 0)
            return;
        const pending = findPendingReply(context.sessionKey, context.conversationId);
        if (!pending)
            return;
        const key = pendingReplyKey(context.sessionKey, pending.summon.message.channelId);
        pendingReplies.delete(key);
        audit.log(invocationResult(pending.summon, config, true), "forge-reply");
    });
    api.on("gateway_stop", async () => {
        pendingReplies.clear();
        // Persistent pending continuity intentionally survives plugin/gateway reload.
        continuityRuns.clear();
        continuityRunSides.clear();
        liveRoomContextDiagnostics.clear();
        gatewayModelRouter.clear();
        recentInboundMetadata.clear();
        // Persistent recent channel context survives reload.
        for (const records of pendingPromptContexts.values()) {
            for (const record of records) {
                expirePromptContext(record, "gateway-stopped-before-prompt-build");
            }
        }
        pendingPromptContexts.clear();
        attachedPromptContexts.clear();
        verifiedPromptContextRunIds.clear();
        loggedUsageRunIds.clear();
        pendingPromptContextCount = [...pendingPromptContexts.values()].reduce((total, records) => total + records.length, 0);
        await Promise.all([
            audit.flush(),
            activity.close(),
            automaticAntiSpam.close(),
            crossChannelSpam.close()
        ]);
    }, { timeoutMs: 5_000 });
    api.logger.info(`Forge Discord Monitor loaded; routing gate ${config.routingGate.enabled ? "enabled" : "disabled"}; assistance summons ${config.assistanceDispatch.enabled ? "enabled" : "disabled"}; moderation summons ${config.moderationDispatch.enabled ? "enabled" : "disabled"}; Forge moderation actions ${config.moderationActions.judgement.enabled ? "enabled" : "disabled"}; Forge timeouts ${config.moderationActions.temporaryTimeouts.enabled
        ? "enabled"
        : "disabled"}; automatic anti-spam ${config.moderationActions.automaticAntiSpam.enabled
        ? "enabled"
        : "disabled"}; cross-channel delete/quarantine ${config.moderationActions.crossChannelSpam.enabled
        ? "enabled"
        : "disabled"}; activity tracking ${config.activityTracking.enabled ? "enabled" : "disabled"}; ambient gateway model ${gatewayModelRouter.enabled
        ? gatewayModelRouter.modelReference
        : "agent default"}; same-run summon context ${config.contextMessageCount} previous messages.`);
};
//# sourceMappingURL=adapter.js.map