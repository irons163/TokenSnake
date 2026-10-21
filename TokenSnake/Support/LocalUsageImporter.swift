import Foundation

actor LocalUsageImporter {
    private let maximumLineBytes = 16 * 1_024 * 1_024
    private let cursorTransport: CursorUsageImporter.Transport?
    private let now: @Sendable () -> Date

    init(cursorTransport: CursorUsageImporter.Transport? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.cursorTransport = cursorTransport
        self.now = now
    }

    func scan(settings: LocalSyncSettings, checkpoints: [String: UsageFileCheckpoint],
              opencodeCheckpoint: OpenCodeCheckpoint? = nil,
              cursorCheckpoint: CursorCheckpoint? = nil,
              forceRemote: Bool = false) async throws -> UsageScanResult {
        var result = UsageScanResult(checkpoints: checkpoints, opencodeCheckpoint: opencodeCheckpoint,
                                     cursorCheckpoint: cursorCheckpoint)
        for source in UsageSource.allCases {
            try Task.checkCancellation()
            let directory = settings.directory(for: source)
            var status = UsageSourceStatus(source: source, directory: directory.path,
                                           state: settings.isEnabled(source) ? .ready : .disabled)
            guard settings.isEnabled(source) else {
                result.statuses.append(status)
                continue
            }
            if source == .opencode {
                try scanOpenCode(directory: directory, into: &result, status: &status)
                result.statuses.append(status)
                continue
            }
            if source == .cursor {
                try await scanCursor(directory: directory, into: &result, status: &status, force: forceRemote)
                result.statuses.append(status)
                continue
            }
            let roots = source == .codex
                ? [directory.appending(path: "sessions"), directory.appending(path: "archived_sessions")]
                : [directory.appending(path: "projects")]
            let collected = Self.collectFiles(in: roots)
            status.unreadableFiles += collected.unreadable
            for file in collected.files {
                try Task.checkCancellation()
                status.files += 1
                let key = "\(source.rawValue):\(file.standardizedFileURL.path)"
                do {
                    let scan = try read(file, source: source, checkpoint: result.checkpoints[key])
                    result.entries.append(contentsOf: scan.entries)
                    result.checkpoints[key] = scan.checkpoint
                    result.bytesRead += scan.bytesRead
                    status.skippedLines += scan.skippedLines
                } catch is CancellationError { throw CancellationError() }
                catch { status.unreadableFiles += 1 }
            }
            if !collected.foundRoot { status.state = .missing }
            else if status.unreadableFiles > 0 && status.files == 0 { status.state = .failed }
            result.statuses.append(status)
        }
        return result
    }

    private func scanOpenCode(directory: URL, into result: inout UsageScanResult,
                              status: inout UsageSourceStatus) throws {
        let database = OpenCodeUsageImporter.databaseURL(in: directory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: database.path) else {
            status.state = .missing
            return
        }
        do {
            let scan = try OpenCodeUsageImporter.scan(directory: directory, checkpoint: result.opencodeCheckpoint)
            status.files = 1
            status.skippedLines = scan.skippedRecords
            result.entries.append(contentsOf: scan.entries)
            result.opencodeCheckpoint = scan.checkpoint
            result.bytesRead += scan.bytesRead
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            status.state = .failed
            status.unreadableFiles += 1
        }
    }

    private struct CollectedFiles {
        var files: [URL] = []
        var foundRoot = false
        var unreadable = 0
    }

    private static func collectFiles(in roots: [URL]) -> CollectedFiles {
        var collected = CollectedFiles()
        for configuredRoot in roots {
            // Moving the standard session directory to another disk is common.
            let root = configuredRoot.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            collected.foundRoot = true
            // Attempt the read and handle its error. Permission preflights can
            // block in access(2) even after macOS grants removable-volume access.
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in collected.unreadable += 1; return true }
            ) else { collected.unreadable += 1; continue }
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values?.isRegularFile == true, file.pathExtension.lowercased() == "jsonl" else { continue }
                collected.files.append(file)
            }
        }
        return collected
    }

    private func scanCursor(directory: URL, into result: inout UsageScanResult,
                            status: inout UsageSourceStatus, force: Bool) async throws {
        let scan: CursorUsageImporter.Scan
        do {
            scan = try await CursorUsageImporter.scan(directory: directory, checkpoint: result.cursorCheckpoint,
                                                      force: force, now: now(), transport: cursorTransport)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            status.state = .failed
            status.detail = "無法讀取 Cursor 資料"
            return
        }
        result.cursorCheckpoint = scan.checkpoint
        result.entries.append(contentsOf: scan.entries)
        result.bytesRead += scan.bytesRead
        status.skippedLines = scan.skippedRecords
        switch scan.failure {
        case .missingDatabase:
            status.state = .missing
            status.detail = "找不到 Cursor 資料庫"
        case .notSignedIn:
            status.state = .failed
            status.detail = "Cursor 未登入，請先登入 Cursor App"
        case .unauthorized:
            status.state = .failed
            status.detail = "Cursor 登入已過期，請重新登入後再試"
        case .network:
            status.state = .failed
            status.detail = "無法連線 cursor.com，稍後會自動重試"
        case .invalidResponse:
            status.state = .failed
            status.detail = "Cursor 回傳格式無法解析"
        case nil:
            status.state = .ready
            if scan.throttled {
                status.detail = "Cursor 於 5 分鐘內已同步，略過本次"
            } else {
                status.files = scan.entries.count
                status.detail = scan.entries.isEmpty ? "已連線 Cursor，近 90 天沒有用量"
                    : "已從 Cursor 匯入 \(scan.entries.count) 筆（近 90 天）"
            }
        }
    }

    private struct FileScan {
        var entries: [TokenEntry] = []
        var checkpoint: UsageFileCheckpoint
        var bytesRead: UInt64 = 0
        var skippedLines = 0
    }

    private func read(_ url: URL, source: UsageSource, checkpoint previous: UsageFileCheckpoint?) throws -> FileScan {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let fileID = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        var checkpoint = previous ?? UsageFileCheckpoint()
        if checkpoint.fileID != fileID || size < checkpoint.size || size < checkpoint.offset
            || (size == checkpoint.size && modifiedAt != checkpoint.modifiedAt) {
            checkpoint = UsageFileCheckpoint()
        }
        checkpoint.fileID = fileID
        checkpoint.size = size
        checkpoint.modifiedAt = modifiedAt
        var scan = FileScan(checkpoint: checkpoint)
        if checkpoint.offset == size { return scan }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: checkpoint.offset)
        var pending = Data()
        var pendingByteCount: UInt64 = 0
        var discardingLongLine = false
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            scan.bytesRead += UInt64(chunk.count)
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let end = chunk[start...].firstIndex(of: 0x0a) ?? chunk.endIndex
                let piece = chunk[start..<end]
                pendingByteCount += UInt64(piece.count)
                if !discardingLongLine {
                    if pending.count + piece.count <= maximumLineBytes { pending.append(contentsOf: piece) }
                    else { pending.removeAll(keepingCapacity: false); discardingLongLine = true }
                }
                if end < chunk.endIndex {
                    if discardingLongLine { scan.skippedLines += 1 }
                    else if !pending.isEmpty {
                        do {
                            if let entry = try UsageLogParser.parse(pending, source: source, context: &scan.checkpoint.context) {
                                scan.entries.append(entry)
                            }
                        } catch { scan.skippedLines += 1 }
                    }
                    scan.checkpoint.offset += pendingByteCount + 1
                    pending.removeAll(keepingCapacity: true)
                    pendingByteCount = 0
                    discardingLongLine = false
                    start = chunk.index(after: end)
                } else { start = end }
            }
        }
        // A complete JSON object without a trailing newline is valid. Incomplete writes stay unread.
        if !pending.isEmpty, !discardingLongLine,
           (try? JSONSerialization.jsonObject(with: pending)) != nil {
            do {
                if let entry = try UsageLogParser.parse(pending, source: source, context: &scan.checkpoint.context) {
                    scan.entries.append(entry)
                }
            } catch { scan.skippedLines += 1 }
            scan.checkpoint.offset += pendingByteCount
        }
        return scan
    }
}
