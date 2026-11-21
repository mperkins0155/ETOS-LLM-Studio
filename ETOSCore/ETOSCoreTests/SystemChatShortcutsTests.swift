import Combine
import Foundation
import Testing
@testable import ETOSCore

@Suite("聊天快捷指令")
struct SystemChatShortcutsTests {
    @Test("读取用户选中的回复版本")
    func selectedReply() throws {
        let chosen = UUID()
        let question = ChatMessage(role: .user, content: "问题", selectedResponseAttemptID: chosen)
        let answer = ChatMessage(role: .assistant, content: "选中的答案", responseGroupID: question.id,
                                 responseAttemptID: chosen, responseAttemptIndex: 0)
        let hidden = ChatMessage(role: .assistant, content: "另一版本", responseGroupID: question.id,
                                 responseAttemptID: UUID(), responseAttemptIndex: 1)
        #expect(try SystemChatShortcuts.replyText(in: [question, answer, hidden], excluding: nil) == answer.content)
    }

    @Test("当前轮次没有文本结果时不会误用旧答案、工具输出或流式草稿")
    func unavailableReply() {
        let history = [ChatMessage(role: .assistant, content: "先前答案"), ChatMessage(role: .user, content: "追问")]
        let tool = InternalToolCall(id: "1", toolName: "tool", arguments: "{}")
        let drafts = [
            ChatMessage(role: .error, content: "失败"),
            ChatMessage(role: .assistant, content: "", reasoningContent: "思考"),
            ChatMessage(role: .assistant, content: "正在查找", toolCalls: [tool]),
            ChatMessage(role: .tool, content: "工具结果")
        ]
        for messages in [history] + drafts.map({ history + [$0] }) {
            #expect(throws: ETOSSystemEntryError.noTextReply) {
                try SystemChatShortcuts.replyText(in: messages, excluding: nil)
            }
        }
        let loading = ChatMessage(role: .assistant, content: "部分答案")
        #expect(throws: ETOSSystemEntryError.noTextReply) {
            try SystemChatShortcuts.replyText(in: history + [loading], excluding: loading.id)
        }
    }

    @Test("空白提问不会启动模型请求")
    func emptyQuestion() async {
        await #expect(throws: ETOSSystemEntryError.emptyPrompt) {
            try await SystemChatShortcuts.ask(" \n ")
        }
    }
}

extension ChatServiceTests {
    @MainActor
    @Test("快捷指令在新的 Chat 会话中发送，保留前台会话并可继续追问")
    func shortcutChatRoundTrip() async throws {
        await cleanup()
        setupMockResponsesForChatAndTitle()
        let config = AppConfigStore.shared
        await config.waitForPersistentStoreLoaded()
        let streaming = config.enableStreaming
        config.enableStreaming = false
        defer { config.enableStreaming = streaming }

        let foreground = chatService.createSavedSession(name: "当前会话")
        let entry = SystemEntryCoordinator(chatService: chatService, memoryManager: memoryManager)
        let result = try await entry.startTask(prompt: "快捷指令问题", mode: .chat, requestID: UUID(), activate: false)
        let id = result.sessionID
        #expect(id != foreground.id)
        #expect(Persistence.localAgentMode(sessionID: id) == .chat)
        _ = try await entry.continueTask(sessionID: id, prompt: "再问一次", requestID: UUID())
        let messages = chatService.messagesSnapshot(for: id)
        #expect(messages.filter { $0.role == .user }.map(\.content) == ["快捷指令问题", "再问一次"])
        #expect(try SystemChatShortcuts.replyText(in: messages, excluding: nil) == "聊天回复")
        #expect(chatService.currentSessionSubject.value?.id == foreground.id)
        #expect(chatService.messagesSnapshot(for: foreground.id).isEmpty)
        let matches = try await SystemChatShortcuts.sessions(matching: " 快捷指令 ")
        #expect(matches.map(\.id) == [id])
        let restored = try await SystemChatShortcuts.sessions(identifiers: [foreground.id, UUID(), id])
        #expect(restored.map(\.id) == [foreground.id, id])
    }
}
