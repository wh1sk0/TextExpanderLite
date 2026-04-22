import AppKit

final class SearchWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: SnippetStore
    private let textInjector: TextInjector
    private let prompter: FillInPrompter
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var filtered: [Snippet] = []
    private var previousApp: NSRunningApplication?

    init(store: SnippetStore, textInjector: TextInjector, prompter: FillInPrompter) {
        self.store = store
        self.textInjector = textInjector
        self.prompter = prompter
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Search Snippets"
        window.center()
        super.init(window: window)
        buildUI()
        reloadSnippets()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(previousApp: NSRunningApplication?) {
        if let app = previousApp,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousApp = app
        } else {
            self.previousApp = nil
        }
        reloadSnippets()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reloadSnippets() {
        filtered = store.snippets.filter { $0.enabled }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = "Type to filter (label, abbreviation, content, group)"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(insertSelected)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let columnLabel = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        columnLabel.title = "Label"
        columnLabel.width = 180

        let columnAbbrev = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("abbrev"))
        columnAbbrev.title = "Abbrev"
        columnAbbrev.width = 100

        let columnGroup = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("group"))
        columnGroup.title = "Group"
        columnGroup.width = 100

        let columnContent = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        columnContent.title = "Content"
        columnContent.width = 180

        tableView.addTableColumn(columnLabel)
        tableView.addTableColumn(columnAbbrev)
        tableView.addTableColumn(columnGroup)
        tableView.addTableColumn(columnContent)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.doubleAction = #selector(insertSelected)

        scrollView.documentView = tableView

        let insertButton = NSButton(title: "Insert", target: self, action: #selector(insertSelected))

        for view in [searchField, scrollView, insertButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: insertButton.topAnchor, constant: -12),

            insertButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            insertButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
        case "content":
            label.stringValue = snippet.content
        default:
            label.stringValue = snippet.label
        }

        cell.identifier = identifier
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = store.snippets.filter { $0.enabled }
        } else {
            let lower = query.lowercased()
            filtered = store.snippets.filter {
                $0.enabled && (
                    $0.label.lowercased().contains(lower) ||
                    $0.abbreviation.lowercased().contains(lower) ||
                    $0.content.lowercased().contains(lower) ||
                    $0.group.lowercased().contains(lower)
                )
            }
        }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func insertSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let snippet = filtered[row]
        window?.orderOut(nil)

        let targetApp = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            targetApp?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let resolved = self.prompter.resolve(snippet.content) {
                    self.textInjector.paste(text: resolved)
                }
            }
        }
    }
}
