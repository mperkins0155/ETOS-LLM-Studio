import Foundation
import GRDB

public enum SessionInsertionError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case alreadyExists
    case invalidSession

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return NSLocalizedString("The conversation could not be saved.", comment: "单会话插入失败")
        case .alreadyExists:
            return NSLocalizedString("A conversation with this identifier already exists.", comment: "单会话插入标识冲突")
        case .invalidSession:
            return NSLocalizedString("Only a permanent top-level conversation can be inserted.", comment: "单会话插入范围约束")
        }
    }
}

extension Persistence {
    /// 创建和捕获归档不能用旧目录快照整表回写，否则会删除其他窗口刚保存的会话。
    public static func insertChatSession(_ session: ChatSession, messages: [ChatMessage]) throws {
        guard let store = activeGRDBStore() else { throw SessionInsertionError.storageUnavailable }
        try store.insertChatSession(session, messages: messages)
        WatchDatabaseSyncService.markDatabaseChanged(.chat)
        postCloudSyncLocalDataDidChange()
    }
}

extension PersistenceGRDBStore {
    func insertChatSession(_ session: ChatSession, messages: [ChatMessage]) throws {
        let normalized = normalizeToolCallsPlacement(in: messages)
        try dbPool.write { db in
            let now = Date()
            try insertChatSession(session, at: now, in: db)
            for (index, message) in normalized.enumerated() {
                let record = try makePersistedMessageRecord(db, message: message, sessionID: session.id,
                    position: index, fallbackTimestamp: now.addingTimeInterval(Double(index) * 0.000_001))
                try upsertMessageRecord(db, record: record)
            }
        }
    }

    func insertChatSession(_ session: ChatSession, at date: Date, in db: Database) throws {
        guard !session.isTemporary, !session.isEmbeddedSubagent else { throw SessionInsertionError.invalidSession }
        let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE id = ?",
            arguments: [session.id.uuidString]) ?? 0
        guard exists == 0 else { throw SessionInsertionError.alreadyExists }
        try db.execute(sql: "UPDATE sessions SET sort_index = sort_index + 1 WHERE is_temporary = 0 AND container_session_id IS NULL")
        try upsertSession(db, session: session, sortIndex: 0, updatedAt: date,
            conversationSummary: nil, conversationSummaryUpdatedAt: nil, preserveExistingSummary: false)
        let tagIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM session_tags"))
        try saveSessionTagAssignments(db, sessionID: session.id, tagIDs: session.tagIDs, existingTagIDStrings: tagIDs)
    }
}
