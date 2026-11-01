# Podcast HTML/DOCX Script Viewer

[Русский](README_RU.md) · Version 1.0.0 · [Release notes](RELEASE_NOTES.md)

Read podcast, voiceover, and post-production scripts inside REAPER. Open a DOCX file or a Google Docs HTML export, read the text with supported formatting and comments, and move between individual search matches.

By Aleksei Vorobev / Patch34.

## Requirements

- REAPER 7 or newer.
- ReaImGui 0.10 or newer, installed through ReaPack.

The script is one Lua file. SWS and external DOCX converters are not required.

## Installation

1. Copy `Podcast_HTML_DOCX_Script_Viewer.lua` to your REAPER Scripts folder. Use **Options → Show REAPER resource path in explorer/finder** to locate it.
2. Open **Actions → Show action list…**, choose the Main section, and use **New action → Load ReaScript…** to load the Lua file.
3. Run **Patch34: Podcast HTML/DOCX Script Viewer**. You can assign a shortcut in the action list.

For future updates, replace the Lua file at the same path. Keep its filename and existing action registration to retain the assigned shortcut.

## Open a script

Use **File → Open HTML/DOCX…** or the Open panel in the empty viewer.

For Google Docs HTML, choose **File → Download → Web Page (.html, zipped)** in Google Docs, unzip the download, and open the `.html` file. DOCX files open directly.

The viewer reads the source file; it does not edit or save changes to that document. Keep the source file at an accessible path.

## Reading and search

| Control | Action |
|---|---|
| Search field | Find a literal substring in the document |
| Enter / keypad Enter | Select the first match, then the next match |
| Shift+Enter | Select the previous match; from no selection, select the last match |
| Escape | Close the active About panel, top menu, or comment card; when none is open, clear search |
| Ctrl/Cmd + mouse wheel over the document | Change the document font size |
| View | Adjust typography and reading layout |
| Comments | Open or close the comments sidebar |
| Help → Скопировать логи | Copy the latest diagnostic events |

Search shortcuts apply while the viewer is focused and another control is not handling the keyboard. Open menus, About, and comment cards take priority.

The counter shows **current / total**, for example `9 / 16`. Before the first navigation step, it shows `0 / 16`. Navigation stops at the first and last match; it does not wrap. Each occurrence within a paragraph has its own position. Changing the query resets the selection.

Search keeps the whole document visible. It ignores English and Russian letter case and treats repeated spaces, tabs, non-breaking spaces, and line breaks within a paragraph as a single space. A phrase can cross formatting boundaries within a paragraph. Search does not cross paragraph boundaries; Russian `е` and `ё` remain distinct.

## Formatting, comments, and project state

Supported content includes text colors and highlights, bold, italic, underline, clickable HTTP/HTTPS links, and DOCX comments. DOCX direct strikethrough formatting is also supported. The comments sidebar provides navigation to comments in the document.

Reading settings include font size, margins, indentation, line and paragraph spacing, and visual page layout. Theme choices include Pages, REAPER Grey, and Google Docs White. The displayed pages are a reading layout, not a reproduction of Word pagination.

Each running viewer belongs to the REAPER project from which it was launched. Its window hides when another project tab is active and returns with the owner project. Closing the owner ends that instance. The viewer remembers the document path and reading settings per project on this computer; it does not embed the document in the RPP.

## Import limits

DOCX support is intended for text scripts. Tables, images, footnotes, tracked changes, and other complex Word content are not fully reproduced; unsupported blocks may appear as placeholders or be omitted. Formatting inherited from `styles.xml` and theme colors is not fully resolved. Compare an unfamiliar document with its original before relying on the imported view.

Encrypted DOCX archives and Zip64 are not supported. The built-in ZIP reader does not check CRC values. Import runs synchronously, so a large document can pause the interface while loading. No maximum document size or import-time guarantee has been established.

Google Docs HTML is the supported HTML export workflow. This is not a general web browser or a full word processor.

## Diagnostics

**Help → Скопировать логи** copies the last 100 events from the current session. Logs include the query, document basename, application versions, keyboard events, and layout/scroll coordinates. They do not include the full document text and are not sent automatically. Copy them before closing or restarting the script. When reporting a problem, include what you did, what happened, and what you expected.

## Validation and contact

The author confirmed the manual checks on REAPER 7.83 / macOS 64-bit with ReaImGui 0.10.0.5. Automated regression checks also passed. Windows behavior and quantitative performance limits have not been independently verified. See [validation details](docs/VALIDATION_RU.md).

[Patch34 on GitHub](https://github.com/patch-34) · [Support development](https://boosty.to/patch34/donate)
