# TextExpanderLite

TextExpanderLite is a native macOS menu bar text expander built with AppKit and Swift.

It watches global keyboard input, matches enabled snippet abbreviations like `;em`, and replaces them with snippet content across apps.

## Repo Layout

- `TextExpanderLite.xcodeproj`: Xcode project
- `TextExpanderLite/`: app source
- `README.md`: repo quick-start

## Open In Xcode

```bash
cd /Users/nickfletcher/Documents/AI/Apps/text-expander/TextExpanderLite/TextExpanderLite
open TextExpanderLite.xcodeproj
```

## First Run

1. Build and run from Xcode.
2. Grant these permissions in `System Settings > Privacy & Security`:
   - `Accessibility`
   - `Input Monitoring`
3. Confirm `Tx` appears in the menu bar.
4. Use `Tx > Restart Listener` if the listener needs a manual reset after permissions change.

## Daily Use

1. Click `Tx > Snippets...` to create or edit snippets.
2. Add:
   - `Label`: human-readable name
   - `Abbreviation`: trigger such as `;em`
   - `Content`: text to insert
3. Save the snippet.
4. In another app, type the abbreviation followed by `space`, `tab`, or `return`.

Example:

- Abbreviation: `;em`
- Content: `nick.fletcher@siriusxm.com`

Typing `;em` then `space` should insert the email address.

## Search And Fill-In Snippets

- `Command + Shift + Space`: open snippet search
- `[[Prompt]]` inside snippet content: ask for fill-in values before insertion

Example content:

```text
Hello [[Name]],
```

## Snippet Storage

Snippets live at:

`~/Library/Application Support/TextExpanderLite/snippets.json`

The snippets editor writes to that file directly.

## Troubleshooting

- `Tx` means the listener is active.
- `Tx!` means the listener needs attention.
- Use `Tx > Open Debug Log` to inspect `/tmp/TextExpanderLite-debug.log`.
- If expansion stops working after a rebuild or restart, re-check `Accessibility` and `Input Monitoring` for the exact built app.

## Common Git Commands

```bash
git status
git add .
git commit -m "Describe your changes"
git push
```
