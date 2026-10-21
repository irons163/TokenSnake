import Foundation

actor LocalUsageImporter {
    private let maximumLineBytes = 16 * 1_024 * 1_024

    func scan(settings: LocalSyncSettings, checkpoints: [String: UsageFileCheckpoint]) throws -> UsageScanResult {
        var result = UsageScanResult(checkpoints: checkpoints)
        for source in UsageSource.allCases {
            try Task.checkCancellation()
            let directory = settings.directory(for: source)
            var status = UsageSourceStatus(source: source, directory: directory.path,
                                           state: settings.isEnabled(source) ? .ready : .disabled)
            guard settings.isEnabled(source) else {
                result.statuses.append(status)
                continue
            }
            let roots = source == .codex
                ? [directory.appending(path: "sessions"), directory.appending(path: "archived_sessions")]
                : [directory.appending(path: "projects")]
            var foundDirectory = false
            for configuredRoot in roots {
                // Moving the standard session directory to another disk is common.
                let root = configuredRoot.resolvingSymlinksInPath()
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                foundDirectory = true
                // Attempt the read and handle its error. Permission preflights can
                // block in access(2) even after macOS grants removable-volume access.
                guard let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in status.unreadableFiles += 1; return true }
                ) else { status.unreadableFiles += 1; continue }
                for case let file as URL in enumerator {
                    try Task.checkCancellation()
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    guard values?.isRegularFile == true, file.pathExtension.lowercased() == "jsonl" else { continue }
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
            }
            if !foundDirectory { status.state = .missing }
            else if status.unreadableFiles > 0 && status.files == 0 { status.state = .failed }
            result.statuses.append(status)
        }
        return result
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
