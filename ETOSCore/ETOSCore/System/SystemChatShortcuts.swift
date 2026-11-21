import Foundation

/// 系统可以在首屏出现前解析会话参数。查询和执行都要遵守与前台相同的解锁状态。
public enum SystemChatShortcuts {
    @MainActor
    private static func prepareAccess() async throws {
        try await Task.detached(priority: .userInitiated) {
            guard !DatabaseEncryptionManager.shared.requiresManualUnlock else {
                throw ETOSSystemEntryError.databaseLocked
            }
            Persistence.bootstrapGRDBStoreOnLaunch()
            guard !Persistence.hasPendingLaunchRecoveryRequest() else {
                throw ETOSSystemEntryError.persistenceUnavailable
            }
        }.value
        await AppConfigStore.shared.waitForPersistentStoreLoaded()
        #if os(watchOS)
        await CompressedAppLanguageController.prepareConfiguredLanguage()
        #endif
        try AppLockManager.shared.requireUnlockedForShortcut()
    }

    public static func sessions(
        matching search: String = "", identifiers: [UUID]? = nil, limit: Int? = nil
    ) async throws -> [ETOSSessionSummary] {
        try await prepareAccess()
        let matches = await Task.detached(priority: .userInitiated) { () -> [ETOSSessionSummary] in
            let sessions = Persistence.loadChatSessions()
            if let identifiers {
                let byID = Dictionary(sessions.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                return identifiers.compactMap { id in
                    guard let name = byID[id] else { return nil }
                    return ETOSSessionSummary(id: id, name: name)
                }
            }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return sessions.lazy.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                .prefix(max(0, limit ?? sessions.count))
                .map { ETOSSessionSummary(id: $0.id, name: $0.name) }
        }.value
        try await AppLockManager.shared.requireUnlockedForShortcut()
        return matches
    }

    @concurrent
    public static func ask(_ question: String) async throws -> String {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw ETOSSystemEntryError.emptyPrompt }
        try await prepareAccess()
        let config = await MainActor.run {
            (prompt: AppConfigStore.shared.systemPrompt, temperature: AppConfigStore.shared.aiTemperature)
        }
        let reply = try await ChatService.shared.generateDetachedChatCompletion(
            systemPrompt: config.prompt, userPrompt: prompt, temperature: config.temperature, requestSource: .chat
        ) { text in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ETOSSystemEntryError.noTextReply
            }
        }
        try await AppLockManager.shared.requireUnlockedForShortcut()
        return reply
    }

    @concurrent
    public static func send(
        _ prompt: String, sessionID: UUID?, newSessionMode: LocalAgentMode = .chat
    ) async throws -> ETOSSessionSummary {
        try await prepareAccess()
        let service = ChatService.shared
        await service.waitForInitialPersistenceStateIfNeeded()
        let coordinator = await SystemEntryCoordinator.shared
        let result: ETOSSystemEntryTaskResult
        if let sessionID {
            _ = try visibleSession(id: sessionID)
            result = try await coordinator.continueTask(sessionID: sessionID, prompt: prompt, requestID: UUID())
        } else {
            result = try await coordinator.startTask(
                prompt: prompt, mode: newSessionMode, requestID: UUID(), activate: false
            )
        }
        try await AppLockManager.shared.requireUnlockedForShortcut()
        let session = try visibleSession(id: result.sessionID)
        return ETOSSessionSummary(id: session.id, name: session.name)
    }

    @concurrent
    public static func latestReply(sessionID: UUID) async throws -> String {
        try await prepareAccess()
        _ = try visibleSession(id: sessionID)
        let service = ChatService.shared
        await service.waitForInitialPersistenceStateIfNeeded()
        let reply = try replyText(
            in: service.messagesSnapshot(for: sessionID), excluding: service.activeResponseMessageID(for: sessionID)
        )
        try await AppLockManager.shared.requireUnlockedForShortcut()
        return reply
    }

    static func replyText(in messages: [ChatMessage], excluding loadingID: UUID?) throws -> String {
        // 自动化常把本动作接在发送之后。本轮失败或仍在等待时，不能把上一轮的答案交给下一步。
        let visible = ChatResponseAttemptSupport.visibleMessages(from: messages)
        guard let last = visible.last, last.role == .assistant,
              last.id != loadingID, !last.isReceivingStream,
              (last.toolCalls ?? []).isEmpty,
              !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ETOSSystemEntryError.noTextReply
        }
        return last.content
    }

    @concurrent
    public static func open(sessionID: UUID) async throws {
        try await prepareAccess()
        _ = try visibleSession(id: sessionID)
        await ChatService.shared.waitForInitialPersistenceStateIfNeeded()
        await AppLocalNotificationCenter.shared.requestOpenChatSession(id: sessionID)
    }

    private static func visibleSession(id: UUID) throws -> ChatSession {
        guard let session = Persistence.loadChatSession(id: id), !session.isTemporary, !session.isEmbeddedSubagent else {
            throw ETOSSystemEntryError.sessionNotFound
        }
        return session
    }
}
