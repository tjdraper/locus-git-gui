import AppKit

/// How the diff fills the views laid over it: file headers, notices, images, group headings and the
/// buttons on each hunk's band.
extension DiffViewController {
    func connectBlockViews() {
        blockViews.configureHeader = { [weak self] view, file in self?.configure(view, file: file) }
        blockViews.configureNotice = { [weak self] view, file, notice in self?.configure(view, file: file, notice: notice) }
        blockViews.configureImages = { [weak self] view, file in
            guard let self else { return }
            view.show(images.state(of: files[file]))
        }
        blockViews.configureGroup = { [weak self] view, file in self?.configure(view, file: file) }
        canvas.onSelectionChange = { [weak self] in
            guard let self else { return }
            if canvas.selection != nil {
                markedFile = nil
            }
            blockViews.update()
        }
        canvas.onFocusChange = { [weak self] in
            guard self?.highlightsCurrentFile == true else { return }
            self?.blockViews.update()
        }
        connectHunkBars()
    }

    /// Hunks only have views over them when there's something to do with them.
    func connectHunkBars() {
        blockViews.configureHunk = hunkActions == nil ? nil : { [weak self] view, file, hunk in
            guard let self, let hunkActions else { return }
            view.show(hunkActions(files[file], hunk, selectedLines(inFile: file, hunk: hunk)))
        }
        blockViews.removeAll()
        blockViews.update()
    }

    /// The lines of a hunk in the rows the selection covers, both sides of a side-by-side row.
    func selectedLines(inFile file: Int, hunk: Int) -> [Int] {
        guard let content = canvas.content, let selection = canvas.selection else { return [] }
        return selection.lines(inFile: file, hunk: hunk, document: content.document)
    }

    private func configure(_ view: DiffFileHeaderView, file index: Int) {
        let file = files[index]
        let id = file.id
        let path = file.changed.path
        view.show(DiffFileHeaderView.Content(
            file: file.changed,
            added: file.patch.added,
            removed: file.patch.removed,
            isCollapsed: collapsedFiles.contains(id),
            isInWorkingTree: isInWorkingTree(path),
            isCurrent: highlightsCurrentFile && canvas.hasFocus && commandTarget?.file == index,
            isSelected: selectsFiles && selectedFiles.contains(id)
        ))
        view.onCommandClick = selectsFiles ? { [weak self] in self?.toggleSelection(of: id) } : nil
        view.onShiftClick = selectsFiles ? { [weak self] in self?.extendSelection(to: id) } : nil
        view.show(actions: fileActions?(file) ?? [])
        view.onToggle = { [weak self] in self?.toggleCollapsed(id) }
        view.onToggleAll = { [weak self] in self?.toggleAllCollapsed(like: id) }
        view.onOpenInEditor = { [weak self] in self?.openInEditor(path: path) }
        view.makeMenu = { [weak self] in
            guard let self, let index = self.index(of: id) else { return NSMenu() }
            return menu(forFile: index).make()
        }
    }

    private func configure(_ view: DiffNoticeView, file index: Int, notice: DiffDocument.Notice) {
        view.show(notice)
        let id = files[index].id
        view.onShow = { [weak self] in self?.showChanges(ofFile: id) }
        view.onShowDetails = { [weak self] in
            guard let self, let failure = leftOut.failure(for: id) else { return }
            showFailure?(failure) { [weak self] in self?.showChanges(ofFile: id) }
        }
    }

    private func configure(_ view: DiffGroupHeaderView, file index: Int) {
        guard let group = files[index].group, let described = describeGroup?(group) else { return }
        let count = files[index...].prefix { $0.group == group }.count
        view.show(DiffGroupHeaderView.Content(title: described.title, fileCount: count, actions: described.actions))
    }
}
