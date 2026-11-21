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
    static var description = IntentDescription("留空会话以新建聊天，或在所选会话中继续。返回收到消息的会话。")

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
    static var description = IntentDescription("按聊天列表顺序返回已保存的会话，可按名称筛选。")

    @Parameter(title: "关键词") var query: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[ETOSSessionEntity]> {
        let sessions = try await SystemChatShortcuts.sessions(matching: query ?? "")
        return .result(value: sessions.map { ETOSSessionEntity(id: $0.id, name: $0.name) })
    }
}

struct GetETOSChatReplyIntent: AppIntent {
    static var title: LocalizedStringResource = "读取最近回复"
    @Parameter(title: "会话", inputConnectionBehavior: .connectToPreviousIntentResult)
    var session: ETOSSessionEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let reply = try await SystemChatShortcuts.latestReply(sessionID: session.id)
        return .result(value: reply)
    }
}
