import AppKit

/// How the working area fills the diff's buttons and menus.
extension WorkingAreaViewController {
    func connectDiff() {
        diff.selectsFiles = true
        diff.summaryAccessory = filterControl
        diff.describeGroup = { [weak self] group in
            guard let self, let group = WorkingAreaGroup(rawValue: group) else { return ("", []) }
            return (group.title, groupActions(group))
        }
        diff.fileActions = { [weak self] file in self?.fileActions(file) ?? [] }
        diff.hunkActions = { [weak self] file, hunk, lines in self?.hunkActions(file, hunk: hunk, lines: lines) ?? [] }
        diff.readFile = { [weak self] file in
            guard let self else { throw CancellationError() }
            return try await WorkingAreaDiff.readFile(
                file,
                options: diff.options.options,
                workTree: commands.repository.workTree,
                readingPatch: commands.readPatch
            )
        }
        diff.readImage = { [commands] file, isNew in
            try await WorkingAreaImages.read(file, isNew: isNew, workTree: commands.repository.workTree, running: commands.run)
        }
        diff.openFileWindow = { [weak self] file in
            guard let self else { return }
            openFileWindow?(FileWindowRequest(source: .workingArea, file: file, files: diff.files))
        }
        // Space stages or unstages the highlighted file, as it would check a box. Shift-Space still
        // pages up.
        diff.onTypedKey = { [weak self] key in
            guard key == " ", NSApp.currentEvent?.modifierFlags.contains(.shift) != true, let self else { return false }
            toggleFileStaging(nil)
            return true
        }
    }

    /// From the latest status rather than the diff, which isn't read while the working area isn't
    /// shown. Staging needs only their names.
    func files(in groups: Set<WorkingAreaGroup>) -> [DiffFile] {
        guard let status else { return [] }
        return WorkingAreaFiles.list(status).filter { groups.contains($0.group) }.map { entry in
            DiffFile(changed: entry.file, patch: FilePatch(), group: entry.group.rawValue)
        }
    }

    private func groupActions(_ group: WorkingAreaGroup) -> [DiffAction] {
        switch group {
        case .conflicted:
            [DiffAction(title: AppCommand.showConflicts.title) { [weak self] in self?.session.showConflicts?(nil) }]
        case .staged:
            [DiffAction(title: AppCommand.unstageAll.title) { [weak self] in self?.unstageAll(nil) }]
                + pickedAction("Unstage", in: group) { [weak self] files in self?.staging.unstage(files) }
        case .unstaged:
            [DiffAction(title: AppCommand.stageAll.title) { [weak self] in
                guard let self else { return }
                staging.stageTracked(excluding: files(in: [.conflicted]))
            }] + pickedAction("Stage", in: group) { [weak self] files in self?.staging.stage(files) }
        case .untracked:
            [DiffAction(title: AppCommand.stageAll.title) { [weak self] in
                guard let self else { return }
                staging.stageUntracked(files(in: [.untracked]))
            }] + pickedAction("Stage", in: group) { [weak self] files in self?.staging.stage(files) }
        }
    }

    /// Acts on the files picked in this group alone, since a heading speaks for its own files.
    /// Nothing while none of them is picked.
    private func pickedAction(_ verb: String, in group: WorkingAreaGroup, perform: @escaping ([DiffFile]) -> Void) -> [DiffAction] {
        let picked = diff.files.filter { diff.selectedFiles.contains($0.id) && WorkingAreaGroup($0) == group }
        guard !picked.isEmpty else { return [] }
        return [DiffAction(title: "\(verb) \(picked.count) Selected") { perform(picked) }]
    }

    /// The button that acts goes last, as in a dialog, after one that discards. A picked file's
    /// buttons act on every picked file they apply to, and say how many.
    private func fileActions(_ file: DiffFile) -> [DiffAction] {
        let targets = StagingTargets(files: diff.filesToActOn(from: file))
        let stageMenuTitle = StagingTargets.title("Stage", targets.toStage, one: "Stage File")
        let stage = DiffAction(title: targets.stageButtonTitle, menuTitle: stageMenuTitle) { [weak self] in
            self?.staging.stage(targets.toStage)
        }
        let discard = DiffAction(title: targets.discardButtonTitle, menuTitle: targets.discardTitle) { [weak self] in
            self?.staging.discard(targets.toDiscard)
        }
        switch WorkingAreaGroup(file) {
        case .conflicted:
            let resolve = DiffAction(title: "Resolve…", menuTitle: "Resolve in Conflict Window") { [weak self] in
                self?.session.showConflicts?(file.changed.path)
            }
            return [resolve, DiffAction(title: targets.resolveButtonTitle, menuTitle: "Mark as Resolved") { [weak self] in
                self?.staging.stage(targets.toResolve)
            }]
        case .staged:
            let menuTitle = StagingTargets.title("Unstage", targets.toUnstage, one: "Unstage File")
            return [DiffAction(title: targets.unstageButtonTitle, menuTitle: menuTitle) { [weak self] in
                self?.staging.unstage(targets.toUnstage)
            }]
        case .unstaged, .untracked:
            return [discard, stage]
        case nil:
            return []
        }
    }

    /// Worded for the lines picked in the hunk, when there are any.
    private func hunkActions(_ file: DiffFile, hunk: Int, lines: [Int]) -> [DiffAction] {
        let changedLines = lines.filter { file.patch.hunks[hunk].lines[$0].kind != .context }
        func action(_ operation: StagingWorkflow.Operation, _ verb: String) -> DiffAction {
            let isPicking = !changedLines.isEmpty
            let noun = !isPicking ? "Hunk" : changedLines.count == 1 ? "1 Line" : "\(changedLines.count) Lines"
            let ellipsis = operation == .discard ? "…" : ""
            let reason = staging.whyLinesCantBePicked(operation, of: file, isPicking: isPicking)
            return DiffAction(title: "\(verb) \(noun)\(ellipsis)", isEnabled: reason == nil, toolTip: reason) { [weak self] in
                self?.staging.apply(operation, lines: changedLines, hunk: hunk, of: file)
            }
        }
        switch WorkingAreaGroup(file) {
        case .staged:
            return [action(.unstage, "Unstage")]
        case .unstaged, .untracked:
            return [action(.discard, "Discard"), action(.stage, "Stage")]
        case .conflicted, nil:
            return []
        }
    }
}
