import AppIntents
import ETOSCore
import Foundation

struct AskETOSIntent: AppIntent {
    static var title: LocalizedStringResource = "询问 ETOS"
    static var description = IntentDescription("向聊天模型提问并返回文本，不创建会话。")

    @Parameter(title: "消息", inputConnectionBehavior: .connectToPreviousIntentResult)
    var prompt: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = try await SystemChatShortcuts.ask(prompt)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

struct SendETOSChatMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "发送聊天消息"
    static var description = IntentDescription("留空会话以新建聊天，或在所选会话中继续。返回收到消息的会话。", searchKeywords: ["ETOS"])

    @Parameter(title: "消息", inputConnectionBehavior: .connectToPreviousIntentResult)
    var prompt: String
    @Parameter(title: "会话") var session: ETOSSessionEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<ETOSSessionEntity> {
        let target = try await SystemChatShortcuts.send(prompt, sessionID: session?.id)
        return .result(value: ETOSSessionEntity(id: target.id, name: target.name))
    }
}

struct ListETOSSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "列出会话"
    static var description = IntentDescription("按聊天列表顺序返回已保存的会话，可按名称筛选。", searchKeywords: ["ETOS"])

    @Parameter(title: "关键词") var query: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[ETOSSessionEntity]> {
        let sessions = try await SystemChatShortcuts.sessions(matching: query ?? "")
        return .result(value: sessions.map { ETOSSessionEntity(id: $0.id, name: $0.name) })
    }
}

struct GetETOSChatReplyIntent: AppIntent {
    static var title: LocalizedStringResource = "读取最近回复"
    static var description = IntentDescription("返回所选会话最近一轮的文本回复。", searchKeywords: ["ETOS"])
    @Parameter(title: "会话", inputConnectionBehavior: .connectToPreviousIntentResult)
    var session: ETOSSessionEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let reply = try await SystemChatShortcuts.latestReply(sessionID: session.id)
        return .result(value: reply)
    }
}

struct OpenETOSSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 ETOS 会话"
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "会话", inputConnectionBehavior: .connectToPreviousIntentResult)
    var session: ETOSSessionEntity

    func perform() async throws -> some IntentResult {
        try await SystemChatShortcuts.open(sessionID: session.id)
        return .result()
    }
}

struct ETOSSessionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "会话")
    static var defaultQuery = ETOSSessionEntityQuery()
    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ETOSSessionEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ETOSSessionEntity] {
        try await SystemChatShortcuts.sessions(identifiers: identifiers).map { ETOSSessionEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ETOSSessionEntity] {
        try await entities(matching: "")
    }

    func entities(matching string: String) async throws -> [ETOSSessionEntity] {
        try await SystemChatShortcuts.sessions(matching: string, limit: 20).map { ETOSSessionEntity(id: $0.id, name: $0.name) }
    }
}

struct StartETOSAgentTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "新建 Agent 任务"
    static var description = IntentDescription("在新会话中交给 ETOS Agent 处理。", searchKeywords: ["ETOS"])
    @Parameter(title: "任务", inputConnectionBehavior: .connectToPreviousIntentResult)
    var prompt: String

    func perform() async throws -> some IntentResult & ReturnsValue<ETOSSessionEntity> {
        let target = try await SystemChatShortcuts.send(prompt, sessionID: nil, newSessionMode: .agent)
        return .result(value: ETOSSessionEntity(id: target.id, name: target.name))
    }
}

struct ETOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskETOSIntent(),
            phrases: ["询问 \(.applicationName)"],
            shortTitle: "询问 ETOS",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: StartETOSAgentTaskIntent(),
            phrases: ["用 \(.applicationName) 新建 Agent 任务"],
            shortTitle: "新建 Agent 任务",
            systemImageName: "sparkles"
        )
    }
}
