# CLAUDE.md — File Browser

A small Windows desktop app (Lazarus / Free Pascal) for browsing a folder and reading or
editing its Markdown files, so a second editor window doesn't have to stay open just to read
documents.

## This repository is public

Everything committed here is world-readable: code, comments, commit messages, docs, test
files, screenshots, the installer and its script. Nothing in it may carry personal, client or
internal information.

- **No real people.** No names, email addresses, phone numbers or usernames of staff,
  customers or anyone else in code, comments, docs or commit messages. When an example needs a
  person, use a made-up one: `Sam Sample`, `sam@example.com`, `000 000 0000`.
- **No clients or their work.** Don't name the companies, products, projects or repositories
  this app is used with, and don't copy text from the documents it is used to read (reviews,
  tickets, notes) into code, comments, tests, docs or screenshots. Write generic examples.
- **No internal details.** No internal hostnames, IP addresses, database or server names,
  internal repository URLs, or paths from a developer's PC (`C:\Users\<name>\...`,
  `C:\Development\<private project>\...`). Paths in docs use placeholders such as
  `C:\path\to\folder`.
- **No secrets.** No passwords, API keys or tokens, real or real-looking.
- **Test data and screenshots** use only made-up Markdown files in a sample folder created
  for the purpose, never a real working folder.
- **Commit messages and PR text** follow the same rules: describe the change, not the
  private document or client that prompted it.

### Check before every commit

Search what is about to be committed (not what you remember putting in):

```bash
git diff --cached -U0 | grep -niE '[a-z0-9._-]+@[a-z0-9-]+\.[a-z.]{2,}|[a-z]:[\\/]users[\\/]|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b|password|secret|api[_-]?key|access[_-]?token|bearer'
```

Expected noise: version numbers such as `4.8.0.0` match the IP pattern, and this file matches
its own example address.

Then read the staged file list (`git diff --cached --stat`) for anything that should not be
there: built files, settings files, logs, sample documents from a real folder. Anything a
match turns up gets replaced with a placeholder before committing. If something genuinely needs
a real name, ask the repository owner first.

## Build

- Lazarus 4.8 / FPC 3.2.2, 64-bit Windows. Packages: LCL, SynEdit, TurboPowerIPro.
- App: `lazbuild FileBrowser.lpi` (Lazarus's `lazbuild.exe`, default install `C:\lazarus`).
  Close a running File Browser first: Windows locks the exe.
- Installer: `installer\build-installer.ps1` runs lazbuild, then Inno Setup 6 (`ISCC.exe`) on
  `installer\FileBrowser.iss`; output goes to `installer\Output\` (not committed).
- Icon: `python tools\make_icon.py` redraws `FileBrowser.ico` (needs Pillow).
- Version: set in `FileBrowser.lpi` (`VersionInfo`); the installer reads it from the exe.

## Layout

| File | What it holds |
|---|---|
| `FileBrowser.lpr` / `.lpi` | Program and project (icon, version info, required packages) |
| `umain.pas` / `.lfm` | Main window. The UI is built in code (`BuildUI`, `BuildActions`, `BuildMenus`), so the `.lfm` is nearly empty |
| `umarkdown.pas` | Markdown → HTML converter (CommonMark/GFM subset) |
| `usynmarkdown.pas` | SynEdit highlighter for Markdown |
| `installer/` | Inno Setup script and build script |
| `tools/make_icon.py` | Draws the icon |

Settings (last folder, open tabs per folder, window layout) are stored per user in
`%LOCALAPPDATA%\FileBrowser\FileBrowser.ini`, never in the repository.

## Things learned the hard way

- **IPro shows `<pre>` raw:** entities are not decoded and a `<` starts a tag. Code blocks
  are rendered as `<tt>` lines with `&nbsp;` and `<br>` instead (`CodeBlockHtml`).
- **IPro and monitors with different scaling:** with its paint buffer on, IPro measures words
  on the control canvas but draws on a bitmap with the startup DPI, so words overlap. Keep
  `UsePaintBuffer := False`. It also caches word widths, so after the window moves to another
  monitor the views are redrawn (`FormBoundsChanged` → `RefreshViews`; also Ctrl+R).
- **IPro lays a new page out only when it paints it,** so setting `VScrollPos` right after
  `SetHtmlFromStr` is clamped to 0 and the view jumps to the top. `RestoreViewerScroll`
  forces the layout first (reads the page panel's `PageRect`), then scrolls.
- **IPro ignores `bgcolor` on `<table>`;** put it on `<tr>`. `<p>` inside `<li>` runs
  together, so list items render "tight" with `<br>` between paragraphs.
- **Icons must be bitmap frames.** LCL can't read PNG-compressed `.ico` frames (the app fails
  at startup with "Bitmap with unknown compression"). `tools/make_icon.py` writes 32-bit BMP
  frames for that reason; don't switch it to Pillow's default ICO writer.
- **SynEdit highlighters** carry range state across lines themselves: `ContinueNextLine` calls
  `SetLine` without `SetRange`.
- **Removing SynEdit's top text view crashes** (Lazarus 4.8): the caret then unhooks from a
  view that has already lost its manager. Freeing `TLazSynEditLineWrapPlugin` removes its view,
  which is on top, so turning word wrap off puts a pass-through view on top first (`ApplyWrap`,
  `WrapSpacer`). Removing a view that is not on top is safe.
- **Never free a tab while one of its controls is handling a message.** Alt+C or Ctrl+W with the
  focus in a tab's viewer runs Close Tab inside that viewer's key handling; freeing the tab there
  crashed only sometimes. `CloseDoc` takes the tab out of the page control and frees it with
  `Application.ReleaseComponent`.
- **Window sizes** are saved in 96-DPI units (`ScaleFormTo96`) because they are applied in
  `FormCreate`, before LCL scales the form.
