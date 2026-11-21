import AppIntents
import Foundation
import Testing
@testable import ETOS_LLM_Studio_App

@Suite("快捷指令动作搜索")
@MainActor
struct ShortcutActionSearchTests {
    @Test("输入 etos 也能匹配标题中没有应用名的动作")
    func brandKeywordMatchesActions() {
        let descriptions = [
            StartETOSAgentTaskIntent.description,
            ContinueETOSSessionIntent.description,
            GetETOSTaskStatusIntent.description,
            StopETOSTaskIntent.description,
            OpenETOSBrowserIntent.description,
            SendETOSChatMessageIntent.description,
            ListETOSSessionsIntent.description,
            GetETOSChatReplyIntent.description
        ]
        for description in descriptions {
            let keywords = description.searchKeywords.map { String(localized: $0).lowercased() }
            #expect(keywords.contains("etos"), "\(String(localized: description.descriptionText))")
        }
    }
}
