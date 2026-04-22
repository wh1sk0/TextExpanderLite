import AppKit

final class SnippetsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSplitViewDelegate, NSTextFieldDelegate {
    private let store: SnippetStore

    private var snippets: [Snippet] = []
    private var groups: [String] = []
    private var customGroups: Set<String> = []
    private var selectedGroup: String = "All"
    private let groupsDefaultsKey = "TextExpanderLite.customGroups"

    private let groupsTable = NSTableView()
    private let snippetsTable = NSTableView()

    private let labelField = NSTextField()
    private let abbreviationField = NSTextField()
    private let groupField = NSTextField()
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let contentView = FocusableTextView()

    init(store: SnippetStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snippets"
        window.center()
        super.init(window: window)
        buildUI()
        loadCustomGroups()
        reloadFromStore()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        reloadFromStore()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self

        let leftPane = NSView()
        let rightPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        rightPane.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(leftPane)
        split.addArrangedSubview(rightPane)

        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        setupGroupsPane(in: leftPane)
        setupSnippetsPane(in: rightPane)
        split.setPosition(200, ofDividerAt: 0)
    }

    private func setupGroupsPane(in view: NSView) {
        let header = NSTextField(labelWithString: "Groups")
        header.font = NSFont.boldSystemFont(ofSize: 12)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("group"))
        column.title = "Group"
        groupsTable.addTableColumn(column)
        groupsTable.headerView = nil
        groupsTable.dataSource = self
        groupsTable.delegate = self
        groupsTable.target = self
        groupsTable.action = #selector(groupSelectionChanged)
        scroll.documentView = groupsTable

        let addButton = NSButton(title: "Add", target: self, action: #selector(addGroup))
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeGroup))

        for v in [header, scroll, addButton, removeButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -10),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            removeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            removeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    private func setupSnippetsPane(in view: NSView) {
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8

        let addButton = NSButton(title: "Add Snippet", target: self, action: #selector(addSnippet))
        let removeButton = NSButton(title: "Delete", target: self, action: #selector(deleteSnippet))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSnippets))
        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadFromStore))

        topBar.addArrangedSubview(addButton)
        topBar.addArrangedSubview(removeButton)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBar.addArrangedSubview(spacer)
        topBar.addArrangedSubview(reloadButton)
        topBar.addArrangedSubview(saveButton)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let snippetsScroll = NSScrollView()
        snippetsScroll.hasVerticalScroller = true
        snippetsScroll.borderType = .bezelBorder

        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelColumn.title = "Label"
        labelColumn.width = 160
        let abbrevColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("abbrev"))
        abbrevColumn.title = "Abbrev"
        abbrevColumn.width = 120
        let groupColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("group"))
        groupColumn.title = "Group"
        groupColumn.width = 140
        let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledColumn.title = "On"
        enabledColumn.width = 50

        snippetsTable.addTableColumn(labelColumn)
        snippetsTable.addTableColumn(abbrevColumn)
        snippetsTable.addTableColumn(groupColumn)
        snippetsTable.addTableColumn(enabledColumn)
        snippetsTable.headerView = nil
        snippetsTable.delegate = self
        snippetsTable.dataSource = self
        snippetsTable.target = self
        snippetsTable.action = #selector(snippetSelectionChanged)
        snippetsScroll.documentView = snippetsTable

        let form = NSStackView()
        form.orientation = .vertical
        form.spacing = 6
        form.translatesAutoresizingMaskIntoConstraints = false

        labelField.placeholderString = "Label"
        abbreviationField.placeholderString = "Abbreviation"
        groupField.placeholderString = "Group (e.g. General)"

        labelField.delegate = self
        labelField.target = self
        labelField.action = #selector(fieldChanged)
        abbreviationField.delegate = self
        abbreviationField.target = self
        abbreviationField.action = #selector(fieldChanged)
        groupField.delegate = self
        groupField.target = self
        groupField.action = #selector(fieldChanged)
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(fieldChanged)

        let contentScroll = NSScrollView()
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .bezelBorder
        contentScroll.drawsBackground = true
        contentScroll.backgroundColor = NSColor.textBackgroundColor
        contentView.isRichText = false
        contentView.isEditable = true
        contentView.isSelectable = true
        contentView.drawsBackground = true
        contentView.backgroundColor = NSColor.textBackgroundColor
        contentView.textColor = NSColor.textColor
        contentView.insertionPointColor = NSColor.labelColor
        contentView.isHorizontallyResizable = false
        contentView.isVerticallyResizable = true
        contentView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        contentView.textContainer?.widthTracksTextView = true
        contentView.textContainer?.heightTracksTextView = false
        contentView.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        contentView.autoresizingMask = [.width]
        contentView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        contentView.delegate = self
        contentScroll.documentView = contentView

        form.addArrangedSubview(labelField)
        form.addArrangedSubview(abbreviationField)
        form.addArrangedSubview(groupField)
        form.addArrangedSubview(enabledCheckbox)
        form.addArrangedSubview(contentScroll)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        for v in [topBar, snippetsScroll, form] {
            view.addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            snippetsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            snippetsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            snippetsScroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            snippetsScroll.heightAnchor.constraint(equalToConstant: 160),

            form.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            form.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            form.topAnchor.constraint(equalTo: snippetsScroll.bottomAnchor, constant: 10),
            form.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        contentScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    }

    private func currentFilteredSnippets() -> [Snippet] {
        if selectedGroup == "All" {
            return snippets
        }
        return snippets.filter { $0.group == selectedGroup }
    }

    private func rebuildGroups() {
        let snippetGroups = Set(snippets.map { $0.group.isEmpty ? "General" : $0.group })
        customGroups = Set(customGroups.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let unique = snippetGroups.union(customGroups)
        let sorted = unique.sorted()
        groups = ["All"] + sorted
        if !groups.contains(selectedGroup) {
            selectedGroup = "All"
        }
        groupsTable.reloadData()
        if let index = groups.firstIndex(of: selectedGroup) {
            groupsTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    @objc private func reloadFromStore() {
        store.reload()
        snippets = store.snippets
        loadCustomGroups()
        rebuildGroups()
        snippetsTable.reloadData()
        selectFirstSnippet()
    }

    @objc private func saveSnippets() {
        updateSnippetFromForm()
        store.updateSnippets(snippets)
        saveCustomGroups()
        rebuildGroups()
        snippetsTable.reloadData()
    }

    @objc private func addGroup() {
        let alert = NSAlert()
        alert.messageText = "New Group"
        alert.informativeText = "Enter a group name"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            customGroups.insert(name)
            saveCustomGroups()
            if !groups.contains(name) {
                groups.append(name)
                groups = ["All"] + groups.filter { $0 != "All" }.sorted()
            }
            selectedGroup = name
            groupsTable.reloadData()
            if let idx = groups.firstIndex(of: selectedGroup) {
                groupsTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            }
        }
    }

    @objc private func removeGroup() {
        guard selectedGroup != "All", selectedGroup != "General" else { return }
        let alert = NSAlert()
        alert.messageText = "Remove Group"
        alert.informativeText = "Snippets in this group will move to General."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        snippets = snippets.map { snippet in
            if snippet.group == selectedGroup {
                var updated = snippet
                updated.group = "General"
                return updated
            }
            return snippet
        }
        customGroups.remove(selectedGroup)
        saveCustomGroups()
        selectedGroup = "All"
        rebuildGroups()
        snippetsTable.reloadData()
        selectFirstSnippet()
    }

    @objc private func addSnippet() {
        var newSnippet = Snippet(label: "New Snippet", abbreviation: ";new", content: "", enabled: true)
        newSnippet.group = selectedGroup == "All" ? "General" : selectedGroup
        snippets.append(newSnippet)
        rebuildGroups()
        snippetsTable.reloadData()
        selectSnippet(withId: newSnippet.id)
    }

    @objc private func deleteSnippet() {
        let row = snippetsTable.selectedRow
        let filtered = currentFilteredSnippets()
        guard row >= 0, row < filtered.count else { return }
        let target = filtered[row]
        snippets.removeAll { $0.id == target.id }
        rebuildGroups()
        snippetsTable.reloadData()
        selectFirstSnippet()
    }

    @objc private func groupSelectionChanged() {
        let row = groupsTable.selectedRow
        guard row >= 0, row < groups.count else { return }
        selectedGroup = groups[row]
        snippetsTable.reloadData()
        selectFirstSnippet()
    }

    @objc private func snippetSelectionChanged() {
        applySelectionToForm()
    }

    private func selectFirstSnippet() {
        if currentFilteredSnippets().isEmpty {
            clearForm()
            return
        }
        snippetsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        applySelectionToForm()
    }

    private func selectSnippet(withId id: UUID) {
        let filtered = currentFilteredSnippets()
        if let index = filtered.firstIndex(where: { $0.id == id }) {
            snippetsTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            applySelectionToForm()
        }
    }

    private func clearForm() {
        labelField.stringValue = ""
        abbreviationField.stringValue = ""
        groupField.stringValue = ""
        enabledCheckbox.state = .off
        contentView.string = ""
    }

    private func applySelectionToForm() {
        let row = snippetsTable.selectedRow
        let filtered = currentFilteredSnippets()
        guard row >= 0, row < filtered.count else {
            clearForm()
            return
        }
        let snippet = filtered[row]
        labelField.stringValue = snippet.label
        abbreviationField.stringValue = snippet.abbreviation
        groupField.stringValue = snippet.group
        enabledCheckbox.state = snippet.enabled ? .on : .off
        contentView.string = snippet.content
    }

    @objc private func fieldChanged() {
        updateSnippetFromForm()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        updateSnippetFromForm()
    }

    func textDidChange(_ notification: Notification) {
        updateSnippetFromForm()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateSnippetFromForm()
    }

    private func updateSnippetFromForm() {
        let row = snippetsTable.selectedRow
        let filtered = currentFilteredSnippets()
        guard row >= 0, row < filtered.count else { return }
        let selectedId = filtered[row].id
        guard let index = snippets.firstIndex(where: { $0.id == selectedId }) else { return }

        var snippet = snippets[index]
        snippet.label = labelField.stringValue
        snippet.abbreviation = abbreviationField.stringValue
        snippet.group = groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : groupField.stringValue
        snippet.enabled = enabledCheckbox.state == .on
        snippet.content = contentView.string
        snippets[index] = snippet

        let columnIndexes = IndexSet(integersIn: 0..<snippetsTable.tableColumns.count)
        snippetsTable.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columnIndexes)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == groupsTable {
            return groups.count
        }
        return currentFilteredSnippets().count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == groupsTable {
            let identifier = NSUserInterfaceItemIdentifier("group")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? NSTableCellView()
            let label = cell.textField ?? NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            if cell.textField == nil {
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
                    label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2)
                ])
            }
            label.stringValue = groups[row]
            cell.identifier = identifier
            return cell
        }

        let filtered = currentFilteredSnippets()
        guard row < filtered.count else { return nil }
        let snippet = filtered[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        if cell.textField == nil {
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2)
            ])
        }

        switch identifier.rawValue {
        case "label":
            label.stringValue = snippet.label
        case "abbrev":
            label.stringValue = snippet.abbreviation
        case "group":
            label.stringValue = snippet.group
        case "enabled":
            label.stringValue = snippet.enabled ? "On" : "Off"
        default:
            label.stringValue = snippet.label
        }

        cell.identifier = identifier
        return cell
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        140
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        320
    }

    private func loadCustomGroups() {
        let saved = UserDefaults.standard.stringArray(forKey: groupsDefaultsKey) ?? []
        customGroups = Set(saved.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "All" })
    }

    private func saveCustomGroups() {
        let sorted = customGroups.sorted()
        UserDefaults.standard.set(sorted, forKey: groupsDefaultsKey)
    }
}

final class FocusableTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
