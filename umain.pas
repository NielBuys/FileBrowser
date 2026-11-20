unit uMain;

{ File Browser: a light folder browser with a Markdown viewer / editor.
  The window is built in code (see BuildUI) so the .lfm stays tiny. }

{$mode objfpc}{$H+}

interface

uses
  Windows, ShellApi, Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  ComCtrls, ExtCtrls, Menus, ActnList, StdCtrls, IniFiles, LCLType, LCLIntf,
  Clipbrd, LazFileUtils, LazUTF8, LConvEncoding,
  SynEdit, SynEditHighlighter, SynEditWrappedView, SynEditTypes, LazSynEditText,
  SynHighlighterSQL, SynHighlighterPas, SynHighlighterXML, SynHighlighterHTML,
  SynHighlighterJScript, SynHighlighterCpp, SynHighlighterPython,
  SynHighlighterIni, SynHighlighterBat, SynHighlighterDiff, SynHighlighterCss,
  IpHtml, uMarkdown, uSynMarkdown;

type
  TViewMode = (vmEdit, vmView);
  TFileEncoding = (feUTF8, feUTF8BOM, feUTF16LE, feAnsi);

  TNodeInfo = class
    Path: string;
    IsDir: Boolean;
    Loaded: Boolean;
  end;

  { One open file. The sheet owns an editor and (for Markdown / HTML) a viewer. }
  TDocSheet = class(TTabSheet)
  public
    FileName: string;
    Editor: TSynEdit;
    Viewer: TIpHtmlPanel;
    WrapPlugin: TLazSynEditLineWrapPlugin;
    WrapSpacer: TSynEditStringsLinked; // see ApplyWrap
    Mode: TViewMode;
    CanView: Boolean;
    IsMarkdown: Boolean;
    Encoding: TFileEncoding;
    LineBreak: string;
    TrailingEOL: Boolean;
    DiskStamp, DiskSize: Int64;
    ViewDirty: Boolean;
    Missing: Boolean;
    PendingAnchor: string;
  end;

  { TfrmMain }

  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    // layout
    FMenu: TMainMenu;
    FToolBar: TToolBar;
    FLeft: TPanel;
    FFolderLabel: TLabel;
    FFilterEdit: TEdit;
    FTree: TTreeView;
    FSplitter: TSplitter;
    FPages: TPageControl;
    FEmptyPanel: TPanel;
    FEmptyLabel: TLabel;
    FStatus: TStatusBar;
    FIcons: TImageList;
    FTreeMenu, FTabMenu, FViewerMenu: TPopupMenu;
    FRecentMenu: TMenuItem;
    FTimer, FFilterTimer, FMonitorTimer: TTimer;
    FLastMonitor: TMonitor;
    // actions
    FActions: TActionList;
    actOpenFolder, actRefresh, actSave, actSaveAll, actCloseTab, actCloseAll,
    actCloseOthers, actToggleMode, actDocsOnly, actWordWrap, actLineBreaks, actZoomIn,
    actZoomOut, actZoomReset, actNextTab, actPrevTab, actCopy, actFind, actFindNext,
    actExit, actNewFile, actRevealInTree, actShortcuts, actRefreshView: TAction;
    // highlighters
    FHlMarkdown: TSynMarkdownSyn;
    FHlSQL: TSynSQLSyn;
    FHlPas: TSynPasSyn;
    FHlXML: TSynXMLSyn;
    FHlHTML: TSynHTMLSyn;
    FHlJS: TSynJScriptSyn;
    FHlCpp: TSynCppSyn;
    FHlPython: TSynPythonSyn;
    FHlIni: TSynIniSyn;
    FHlBat: TSynBatSyn;
    FHlDiff: TSynDiffSyn;
    FHlCss: TSynCssSyn;
    // state
    FRoot: string;
    FIniName: string;
    FZoom: Integer;
    FDocsOnly: Boolean;
    FWordWrap: Boolean;
    FLineBreaks: Boolean;
    FDocsCache: TStringList;
    FTreeSig: string;
    FTick: Integer;
    FPreSearchExpanded: TStringList;
    FInSearch: Boolean;
    FLoadingSession: Boolean;
    FFindText: string;

    procedure BuildUI;
    procedure BuildActions;
    procedure BuildMenus;
    procedure BuildIcons;
    function NewAction(const ACaption: string; AShortCut: TShortCut;
      AHandler: TNotifyEvent; const AHint: string = ''): TAction;
    procedure AddToolButton(AAction: TAction; ACheck: Boolean = False);
    procedure AddToolSeparator;

    // settings
    procedure LoadSettings;
    procedure SaveSettings;
    procedure SaveSession;
    procedure RestoreSession;
    function SessionSection: string;
    procedure AddRecent(const ADir: string);
    procedure RebuildRecentMenu;
    procedure RecentClick(Sender: TObject);

    // tree
    function RelPath(const APath: string): string;
    function AbsPath(const ARel: string): string;
    function IsSkippedDir(const AName: string): Boolean;
    function PassesFilter(const AName: string; AIsDir: Boolean; const AFull: string): Boolean;
    function DirHasDocs(const ADir: string; ADepth: Integer): Boolean;
    procedure FillChildren(AParent: TTreeNode; const ADir: string);
    procedure LoadTree(AExpanded: TStrings; const ASelected, ATop: string);
    procedure FillSearchResults(const AText: string);
    procedure RefreshTree;
    function ExpandedPaths: TStringList;
    function NodePath(ANode: TTreeNode): string;
    function FindNode(const APath: string; AExpandParents: Boolean): TTreeNode;
    function ComputeTreeSig: string;
    procedure SelectInTree(const APath: string);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeExpandedChanged(Sender: TObject; Node: TTreeNode);
    procedure TreeDeletion(Sender: TObject; Node: TTreeNode);
    procedure TreeMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FilterTimer(Sender: TObject);

    // documents
    function ActiveDoc: TDocSheet;
    function FindDoc(const AFileName: string): TDocSheet;
    function IsTextFile(const AFileName: string): Boolean;
    function HighlighterFor(const AFileName: string): TSynCustomHighlighter;
    function OpenFile(const AFileName: string; AMode: Integer = -1): TDocSheet;
    procedure LoadDoc(ADoc: TDocSheet; AKeepPosition: Boolean);
    function SaveDoc(ADoc: TDocSheet): Boolean;
    function CloseDoc(ADoc: TDocSheet): Boolean;
    function CloseAllDocs(AExcept: TDocSheet = nil): Boolean;
    procedure SetDocMode(ADoc: TDocSheet; AMode: TViewMode);
    procedure RenderDoc(ADoc: TDocSheet; AKeepScroll: Boolean);
    procedure ApplyWrap(ADoc: TDocSheet);
    procedure ApplyZoom;
    procedure UpdateCaption(ADoc: TDocSheet);
    procedure UpdateUI;
    procedure CheckDiskChanges;
    procedure EditorChange(Sender: TObject);
    procedure EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
    procedure ViewerHotClick(Sender: TObject);
    procedure ViewerHotChange(Sender: TObject);
    procedure HandleLink(ADoc: TDocSheet; const AUrl: string);
    procedure PagesChange(Sender: TObject);
    procedure PagesMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PagesContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure AppActivate(Sender: TObject);
    procedure OpenFolder(const ADir: string);

    // action handlers
    procedure DoOpenFolder(Sender: TObject);
    procedure DoRefresh(Sender: TObject);
    procedure DoRefreshView(Sender: TObject);
    procedure RefreshViews;
    procedure FormBoundsChanged(Sender: TObject);
    procedure MonitorTimer(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure DoSaveAll(Sender: TObject);
    procedure DoCloseTab(Sender: TObject);
    procedure DoCloseAll(Sender: TObject);
    procedure DoCloseOthers(Sender: TObject);
    procedure DoToggleMode(Sender: TObject);
    procedure DoDocsOnly(Sender: TObject);
    procedure DoWordWrap(Sender: TObject);
    procedure DoLineBreaks(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoZoomReset(Sender: TObject);
    procedure DoNextTab(Sender: TObject);
    procedure DoPrevTab(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoFind(Sender: TObject);
    procedure DoFindNext(Sender: TObject);
    procedure DoExitApp(Sender: TObject);
    procedure DoNewFile(Sender: TObject);
    procedure DoRevealInTree(Sender: TObject);
    procedure DoShortcuts(Sender: TObject);
    procedure DoTreeOpen(Sender: TObject);
    procedure DoTreeOpenExternal(Sender: TObject);
    procedure DoTreeReveal(Sender: TObject);
    procedure DoTreeCopyPath(Sender: TObject);
    procedure DoTreeCopyRelPath(Sender: TObject);
    procedure DoTabCopyPath(Sender: TObject);
    procedure DoTabReveal(Sender: TObject);
    procedure DoTabOpenExternal(Sender: TObject);
    procedure DoViewerSelectAll(Sender: TObject);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

const
  AppTitle = 'File Browser';
  DocExts = '.md;.markdown;.txt;.pdf;';
  MarkdownExts = '.md;.markdown;.mdown;.mkd;';
  TextExts = '.md;.markdown;.mdown;.mkd;.txt;.log;.json;.xml;.sql;.cs;.csproj;.props;' +
    '.targets;.sln;.py;.js;.ts;.tsx;.jsx;.mjs;.html;.htm;.css;.scss;.ps1;.psm1;.bat;.cmd;' +
    '.ini;.cfg;.config;.yml;.yaml;.toml;.pas;.pp;.lpr;.lpi;.lfm;.lps;.inc;.patch;.diff;' +
    '.rest;.http;.gitignore;.gitattributes;.editorconfig;.runsettings;.example;.parked;' +
    '.csv;.tsv;.sh;.c;.h;.cpp;.hpp;.java;.php;.vb;.rb;.go;.rs;.env;.svg;.resx;.xaml;' +
    '.razor;.cshtml;.vue;.kt;.swift;.lua;.r;.dart;.gradle;.properties;.up2date;.cache;';
  BinaryExts = '.exe;.dll;.pdb;.so;.dylib;.zip;.7z;.rar;.gz;.tar;.png;.jpg;.jpeg;.gif;' +
    '.bmp;.ico;.pdf;.docx;.doc;.xlsx;.xls;.pptx;.ppt;.msi;.mp3;.mp4;.wav;.avi;.mov;' +
    '.webp;.tif;.tiff;.ttf;.otf;.woff;.woff2;.nupkg;.snk;.pfx;.bak;.mdf;.ldf;';
  SkipDirs = ';.git;.vs;.vscode;.idea;bin;obj;node_modules;packages;__pycache__;.venv;venv;';

  IconFolder = 0;
  IconFolderOpen = 1;
  IconMarkdown = 2;
  IconText = 3;
  IconBinary = 4;
  IconPdf = 5;

{ ---------- small helpers ---------- }

function ExtIn(const AFileName, AList: string): Boolean;
var
  e: string;
begin
  e := LowerCase(ExtractFileExt(AFileName));
  if e = '' then
    e := LowerCase(ExtractFileName(AFileName));   // .gitignore and friends
  Result := (e <> '') and (Pos(e + ';', AList) > 0);
end;

function GetFileStamp(const AFileName: string; out AStamp, ASize: Int64): Boolean;
var
  data: TWin32FileAttributeData;
  w: UnicodeString;
begin
  AStamp := 0;
  ASize := 0;
  w := UTF8Decode(AFileName);
  Result := GetFileAttributesExW(PWideChar(w), GetFileExInfoStandard, @data);
  if Result then
  begin
    AStamp := (Int64(data.ftLastWriteTime.dwHighDateTime) shl 32) or data.ftLastWriteTime.dwLowDateTime;
    ASize := (Int64(data.nFileSizeHigh) shl 32) or data.nFileSizeLow;
  end;
end;

function ReadAllBytes(const AFileName: string): RawByteString;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure WriteAllBytes(const AFileName: string; const AData: RawByteString);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if AData <> '' then
      fs.WriteBuffer(AData[1], Length(AData));
  finally
    fs.Free;
  end;
end;

function PercentDecode(const S: string): string;
var
  i: Integer;
  h: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) then
    begin
      h := Copy(S, i + 1, 2);
      if (h[1] in ['0'..'9', 'a'..'f', 'A'..'F']) and (h[2] in ['0'..'9', 'a'..'f', 'A'..'F']) then
      begin
        Result := Result + Chr(StrToInt('$' + h));
        Inc(i, 3);
        Continue;
      end;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

procedure ShellOpen(const AFile, AParams: string);
begin
  ShellExecuteW(0, 'open', PWideChar(UTF8Decode(AFile)), PWideChar(UTF8Decode(AParams)),
    nil, SW_SHOWNORMAL);
end;

procedure RevealInExplorer(const APath: string);
begin
  ShellOpen('explorer.exe', '/select,"' + APath + '"');
end;

function CompareDepth(List: TStringList; Index1, Index2: Integer): Integer;
var
  a, b, i: Integer;
begin
  a := 0;
  b := 0;
  for i := 1 to Length(List[Index1]) do
    if List[Index1][i] = '\' then Inc(a);
  for i := 1 to Length(List[Index2]) do
    if List[Index2][i] = '\' then Inc(b);
  Result := a - b;
  if Result = 0 then
    Result := CompareText(List[Index1], List[Index2]);
end;

function CompareNames(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := UTF8CompareText(List[Index1], List[Index2]);
end;

{ ---------- form setup ---------- }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FDocsCache := TStringList.Create;
  FDocsCache.Sorted := True;
  FDocsCache.CaseSensitive := False;
  FPreSearchExpanded := TStringList.Create;
  FZoom := 10;
  FWordWrap := True;
  FLineBreaks := True;
  // %LOCALAPPDATA%\FileBrowser\FileBrowser.ini (fall back to the exe folder)
  if GetEnvironmentVariableUTF8('LOCALAPPDATA') <> '' then
    FIniName := AppendPathDelim(GetEnvironmentVariableUTF8('LOCALAPPDATA')) + 'FileBrowser\FileBrowser.ini'
  else
    FIniName := ChangeFileExt(Application.ExeName, '.ini');
  ForceDirectoriesUTF8(ExtractFilePath(FIniName));

  BuildIcons;
  BuildActions;
  BuildUI;
  BuildMenus;

  FHlMarkdown := TSynMarkdownSyn.Create(Self);
  FHlSQL := TSynSQLSyn.Create(Self);
  FHlSQL.SQLDialect := sqlMSSQL2K;
  FHlPas := TSynPasSyn.Create(Self);
  FHlXML := TSynXMLSyn.Create(Self);
  FHlHTML := TSynHTMLSyn.Create(Self);
  FHlJS := TSynJScriptSyn.Create(Self);
  FHlCpp := TSynCppSyn.Create(Self);
  FHlPython := TSynPythonSyn.Create(Self);
  FHlIni := TSynIniSyn.Create(Self);
  FHlBat := TSynBatSyn.Create(Self);
  FHlDiff := TSynDiffSyn.Create(Self);
  FHlCss := TSynCssSyn.Create(Self);

  Application.OnActivate := @AppActivate;
  OnChangeBounds := @FormBoundsChanged;
  LoadSettings;

  if (ParamCount > 0) and DirectoryExistsUTF8(ParamStr(1)) then
    OpenFolder(ParamStr(1))
  else if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then
    OpenFolder(FRoot)
  else
  begin
    FRoot := '';
    UpdateUI;
  end;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  Application.OnActivate := nil;
  FTimer.Enabled := False;
  FTree.Items.Clear;
  FDocsCache.Free;
  FPreSearchExpanded.Free;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  i: Integer;
  d: TDocSheet;
begin
  for i := 0 to FPages.PageCount - 1 do
  begin
    d := TDocSheet(FPages.Pages[i]);
    if d.Editor.Modified then
    begin
      FPages.ActivePage := d;
      case MessageDlg(AppTitle, 'Save changes to ' + ExtractFileName(d.FileName) + '?',
        mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
        mrYes:
          if not SaveDoc(d) then
          begin
            CanClose := False;
            Exit;
          end;
        mrNo: ;
      else
        CanClose := False;
        Exit;
      end;
    end;
  end;
  SaveSession;
  SaveSettings;
  CanClose := True;
end;

function TfrmMain.NewAction(const ACaption: string; AShortCut: TShortCut;
  AHandler: TNotifyEvent; const AHint: string): TAction;
begin
  Result := TAction.Create(FActions);
  Result.ActionList := FActions;
  Result.Caption := ACaption;
  Result.ShortCut := AShortCut;
  Result.OnExecute := AHandler;
  if AHint <> '' then
    Result.Hint := AHint
  else
    Result.Hint := StringReplace(ACaption, '&', '', [rfReplaceAll]);
end;

procedure TfrmMain.BuildActions;
begin
  FActions := TActionList.Create(Self);
  actOpenFolder := NewAction('&Open Folder...', ShortCut(VK_O, [ssCtrl]), @DoOpenFolder);
  actRefresh := NewAction('&Refresh', ShortCut(VK_F5, []), @DoRefresh, 'Reload the folder tree');
  actRefreshView := NewAction('Refresh &View', ShortCut(VK_R, [ssCtrl]), @DoRefreshView,
    'Redraw the open documents (Ctrl+R), e.g. after moving the window to another screen');
  actSave := NewAction('&Save', ShortCut(VK_S, [ssCtrl]), @DoSave);
  actSaveAll := NewAction('Save A&ll', ShortCut(VK_S, [ssCtrl, ssShift]), @DoSaveAll);
  actCloseTab := NewAction('&Close Tab', ShortCut(VK_W, [ssCtrl]), @DoCloseTab);
  actCloseAll := NewAction('Close &All Tabs', ShortCut(VK_W, [ssCtrl, ssShift]), @DoCloseAll);
  actCloseOthers := NewAction('Close &Other Tabs', 0, @DoCloseOthers);
  actToggleMode := NewAction('&Edit', ShortCut(VK_E, [ssCtrl]), @DoToggleMode,
    'Switch between the formatted view and editing (Ctrl+E)');
  actDocsOnly := NewAction('&Documents Only', ShortCut(VK_D, [ssCtrl, ssShift]), @DoDocsOnly,
    'Show only .md, .txt and .pdf files');
  actWordWrap := NewAction('&Word Wrap', ShortCut(VK_Z, [ssAlt]), @DoWordWrap);
  actLineBreaks := NewAction('Keep &Line Breaks', 0, @DoLineBreaks,
    'Show each line break in a paragraph as a new line, as GitHub comments do');
  actZoomIn := NewAction('Zoom &In', ShortCut(VK_OEM_PLUS, [ssCtrl]), @DoZoomIn);
  actZoomOut := NewAction('Zoom O&ut', ShortCut(VK_OEM_MINUS, [ssCtrl]), @DoZoomOut);
  actZoomReset := NewAction('&Reset Zoom', ShortCut(VK_0, [ssCtrl]), @DoZoomReset);
  actNextTab := NewAction('&Next Tab', ShortCut(VK_TAB, [ssCtrl]), @DoNextTab);
  actPrevTab := NewAction('&Previous Tab', ShortCut(VK_TAB, [ssCtrl, ssShift]), @DoPrevTab);
  actCopy := NewAction('&Copy', ShortCut(VK_C, [ssCtrl]), @DoCopy);
  actFind := NewAction('&Find...', ShortCut(VK_F, [ssCtrl]), @DoFind);
  actFindNext := NewAction('Find &Next', ShortCut(VK_F3, []), @DoFindNext);
  actExit := NewAction('E&xit', 0, @DoExitApp);
  actNewFile := NewAction('&New Markdown File...', ShortCut(VK_N, [ssCtrl]), @DoNewFile);
  actRevealInTree := NewAction('Show in &Tree', ShortCut(VK_E, [ssCtrl, ssShift]), @DoRevealInTree);
  actShortcuts := NewAction('&Keyboard Shortcuts', ShortCut(VK_F1, []), @DoShortcuts);
end;

procedure TfrmMain.AddToolButton(AAction: TAction; ACheck: Boolean);
var
  b: TToolButton;
begin
  b := TToolButton.Create(FToolBar);
  b.Left := FToolBar.ButtonCount * 200 + 10000;
  b.Parent := FToolBar;
  b.Action := AAction;
  b.ShowHint := True;
  if ACheck then
    b.Style := tbsCheck;
end;

procedure TfrmMain.AddToolSeparator;
var
  b: TToolButton;
begin
  b := TToolButton.Create(FToolBar);
  b.Left := FToolBar.ButtonCount * 200 + 10000;
  b.Style := tbsDivider;
  b.Parent := FToolBar;
end;

procedure TfrmMain.BuildUI;
begin
  Caption := AppTitle;
  ShowHint := True;

  FToolBar := TToolBar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.ShowCaptions := True;
  FToolBar.List := True;
  FToolBar.Flat := True;
  FToolBar.AutoSize := True;

  AddToolButton(actOpenFolder);
  AddToolButton(actRefresh);
  AddToolButton(actRefreshView);
  AddToolSeparator;
  AddToolButton(actToggleMode);
  AddToolButton(actSave);
  AddToolButton(actCloseTab);
  AddToolSeparator;
  AddToolButton(actDocsOnly, True);
  AddToolButton(actWordWrap, True);

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := False;
  with FStatus.Panels.Add do Width := 560;
  with FStatus.Panels.Add do Width := 70;
  with FStatus.Panels.Add do Width := 110;
  with FStatus.Panels.Add do Width := 140;

  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self;
  FLeft.Align := alLeft;
  FLeft.Width := Scale96ToForm(300);
  FLeft.BevelOuter := bvNone;

  FFolderLabel := TLabel.Create(Self);
  FFolderLabel.Parent := FLeft;
  FFolderLabel.Align := alTop;
  FFolderLabel.BorderSpacing.Around := 4;
  FFolderLabel.Font.Style := [fsBold];
  FFolderLabel.Caption := 'No folder open';
  FFolderLabel.ShowHint := True;

  FFilterEdit := TEdit.Create(Self);
  FFilterEdit.Parent := FLeft;
  FFilterEdit.Align := alTop;
  FFilterEdit.Top := 100;
  FFilterEdit.BorderSpacing.Left := 2;
  FFilterEdit.BorderSpacing.Right := 2;
  FFilterEdit.BorderSpacing.Bottom := 2;
  FFilterEdit.TextHint := 'Find files by name...  (Esc clears)';
  FFilterEdit.OnChange := @FilterChange;
  FFilterEdit.OnKeyDown := @FilterKeyDown;

  FTree := TTreeView.Create(Self);
  FTree.Parent := FLeft;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.Images := FIcons;
  FTree.RightClickSelect := True;
  FTree.HideSelection := False;
  FTree.Options := FTree.Options + [tvoRightClickSelect, tvoHotTrack, tvoRowSelect, tvoAutoItemHeight] - [tvoShowLines];
  FTree.BorderStyle := bsNone;
  FTree.ScrollBars := ssAutoBoth;
  FTree.OnExpanding := @TreeExpanding;
  FTree.OnExpanded := @TreeExpandedChanged;
  FTree.OnCollapsed := @TreeExpandedChanged;
  FTree.OnDeletion := @TreeDeletion;
  FTree.OnMouseUp := @TreeMouseUp;
  FTree.OnKeyDown := @TreeKeyDown;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alLeft;
  FSplitter.Left := FLeft.Width + 1;
  FSplitter.Width := 5;

  FEmptyPanel := TPanel.Create(Self);
  FEmptyPanel.Parent := Self;
  FEmptyPanel.Align := alClient;
  FEmptyPanel.BevelOuter := bvNone;
  FEmptyPanel.Color := clWindow;
  FEmptyLabel := TLabel.Create(Self);
  FEmptyLabel.Parent := FEmptyPanel;
  FEmptyLabel.Align := alClient;
  FEmptyLabel.Alignment := taCenter;
  FEmptyLabel.Layout := tlCenter;
  FEmptyLabel.Font.Color := clGrayText;
  FEmptyLabel.Font.Size := 11;
  FEmptyLabel.WordWrap := True;
  FEmptyLabel.AutoSize := False;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.OnChange := @PagesChange;
  FPages.OnMouseUp := @PagesMouseUp;
  FPages.OnContextPopup := @PagesContextPopup;
  FPages.Visible := False;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1500;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;

  FFilterTimer := TTimer.Create(Self);
  FFilterTimer.Interval := 300;
  FFilterTimer.Enabled := False;
  FFilterTimer.OnTimer := @FilterTimer;

  FMonitorTimer := TTimer.Create(Self);
  FMonitorTimer.Interval := 600;
  FMonitorTimer.Enabled := False;
  FMonitorTimer.OnTimer := @MonitorTimer;
end;

procedure TfrmMain.BuildMenus;

  function Item(AParent: TMenuItem; AAction: TAction): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Action := AAction;
    AParent.Add(Result);
  end;

  function ItemH(AParent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    AParent.Add(Result);
  end;

  function Top(const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    FMenu.Items.Add(Result);
  end;

var
  m: TMenuItem;
begin
  FMenu := TMainMenu.Create(Self);
  Menu := FMenu;

  m := Top('&File');
  Item(m, actOpenFolder);
  FRecentMenu := TMenuItem.Create(Self);
  FRecentMenu.Caption := 'Open &Recent';
  m.Add(FRecentMenu);
  m.AddSeparator;
  Item(m, actNewFile);
  Item(m, actSave);
  Item(m, actSaveAll);
  m.AddSeparator;
  Item(m, actCloseTab);
  Item(m, actCloseOthers);
  Item(m, actCloseAll);
  m.AddSeparator;
  Item(m, actExit);

  m := Top('&Edit');
  Item(m, actCopy);
  Item(m, actFind);
  Item(m, actFindNext);

  m := Top('&View');
  Item(m, actToggleMode);
  Item(m, actWordWrap).AutoCheck := False;
  Item(m, actLineBreaks).AutoCheck := False;
  m.AddSeparator;
  Item(m, actDocsOnly);
  Item(m, actRefresh);
  Item(m, actRefreshView);
  Item(m, actRevealInTree);
  m.AddSeparator;
  Item(m, actNextTab);
  Item(m, actPrevTab);
  m.AddSeparator;
  Item(m, actZoomIn);
  Item(m, actZoomOut);
  Item(m, actZoomReset);

  m := Top('&Help');
  Item(m, actShortcuts);

  // tree popup
  FTreeMenu := TPopupMenu.Create(Self);
  ItemH(FTreeMenu.Items, 'Open', @DoTreeOpen).Default := True;
  ItemH(FTreeMenu.Items, 'Open with Default App', @DoTreeOpenExternal);
  ItemH(FTreeMenu.Items, 'Reveal in File Explorer', @DoTreeReveal);
  FTreeMenu.Items.AddSeparator;
  ItemH(FTreeMenu.Items, 'Copy Path', @DoTreeCopyPath);
  ItemH(FTreeMenu.Items, 'Copy Relative Path', @DoTreeCopyRelPath);
  FTreeMenu.Items.AddSeparator;
  Item(FTreeMenu.Items, actNewFile);
  Item(FTreeMenu.Items, actRefresh);
  FTree.PopupMenu := FTreeMenu;

  // tab popup
  FTabMenu := TPopupMenu.Create(Self);
  Item(FTabMenu.Items, actCloseTab);
  Item(FTabMenu.Items, actCloseOthers);
  Item(FTabMenu.Items, actCloseAll);
  FTabMenu.Items.AddSeparator;
  ItemH(FTabMenu.Items, 'Copy Path', @DoTabCopyPath);
  Item(FTabMenu.Items, actRevealInTree);
  ItemH(FTabMenu.Items, 'Reveal in File Explorer', @DoTabReveal);
  ItemH(FTabMenu.Items, 'Open with Default App', @DoTabOpenExternal);

  // viewer popup
  FViewerMenu := TPopupMenu.Create(Self);
  Item(FViewerMenu.Items, actCopy);
  ItemH(FViewerMenu.Items, 'Select All', @DoViewerSelectAll);
  FViewerMenu.Items.AddSeparator;
  Item(FViewerMenu.Items, actToggleMode);
end;

procedure TfrmMain.BuildIcons;
var
  sz: Integer;
  f: Double;

  function R(x1, y1, x2, y2: Double): TRect;
  begin
    Result := Rect(Round(x1 * f), Round(y1 * f), Round(x2 * f), Round(y2 * f));
  end;

  procedure AddIcon(AKind: Integer);
  var
    bmp: TBitmap;
    c: TCanvas;
    i: Integer;
  begin
    bmp := TBitmap.Create;
    try
      bmp.SetSize(sz, sz);
      c := bmp.Canvas;
      c.Brush.Color := clFuchsia;
      c.FillRect(0, 0, sz, sz);
      c.Pen.Width := 1;
      case AKind of
        IconFolder, IconFolderOpen:
          begin
            c.Pen.Color := $00309CC8;
            c.Brush.Color := $0040B8E8;
            c.Rectangle(R(1, 3, 7, 6));
            if AKind = IconFolder then
              c.Brush.Color := $0060CCF4
            else
              c.Brush.Color := $0090E0FA;
            c.Rectangle(R(1, 5, 15, 14));
          end;
      else
        begin
          c.Pen.Color := $00909090;
          c.Brush.Color := clWhite;
          if AKind = IconBinary then
            c.Brush.Color := $00E0E0E0;
          c.Rectangle(R(3, 1, 13.5, 15.5));
          case AKind of
            IconMarkdown:
              begin
                c.Brush.Color := $00D07020;
                c.Pen.Color := $00D07020;
                c.Rectangle(R(3, 1, 13.5, 6));
              end;
            IconPdf:
              begin
                c.Brush.Color := $002020D0;
                c.Pen.Color := $002020D0;
                c.Rectangle(R(3, 1, 13.5, 6));
              end;
          end;
          c.Pen.Color := $00A0A0A0;
          for i := 0 to 3 do
          begin
            if (AKind in [IconMarkdown, IconPdf]) and (i < 2) then
              Continue;
            c.Line(Round(5 * f), Round((4 + i * 3) * f), Round(11.5 * f), Round((4 + i * 3) * f));
          end;
        end;
      end;
      FIcons.AddMasked(bmp, clFuchsia);
    finally
      bmp.Free;
    end;
  end;

begin
  sz := Scale96ToScreen(16);
  f := sz / 16;
  FIcons := TImageList.Create(Self);
  FIcons.Width := sz;
  FIcons.Height := sz;
  AddIcon(IconFolder);
  AddIcon(IconFolderOpen);
  AddIcon(IconMarkdown);
  AddIcon(IconText);
  AddIcon(IconBinary);
  AddIcon(IconPdf);
end;

{ ---------- settings ---------- }

procedure TfrmMain.LoadSettings;
var
  ini: TIniFile;
  l, t, w, h: Integer;
begin
  ini := TIniFile.Create(FIniName);
  try
    l := ini.ReadInteger('Window', 'Left', Left);
    t := ini.ReadInteger('Window', 'Top', Top);
    w := ini.ReadInteger('Window', 'Width', Width);
    h := ini.ReadInteger('Window', 'Height', Height);
    // keep the window on a visible monitor
    if Screen.MonitorFromPoint(Point(l + 50, t + 20), mdNull) = nil then
    begin
      l := 100;
      t := 100;
    end;
    SetBounds(l, t, w, h);
    if ini.ReadBool('Window', 'Maximized', False) then
      WindowState := wsMaximized;
    FLeft.Width := ini.ReadInteger('Window', 'TreeWidth', FLeft.Width);
    FZoom := ini.ReadInteger('View', 'FontSize', 10);
    FDocsOnly := ini.ReadBool('View', 'DocumentsOnly', False);
    FWordWrap := ini.ReadBool('View', 'WordWrap', True);
    FLineBreaks := ini.ReadBool('View', 'KeepLineBreaks', True);
    FRoot := ini.ReadString('Main', 'Folder', '');
  finally
    ini.Free;
  end;
  actDocsOnly.Checked := FDocsOnly;
  actWordWrap.Checked := FWordWrap;
  actLineBreaks.Checked := FLineBreaks;
  RebuildRecentMenu;
end;

procedure TfrmMain.SaveSettings;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(FIniName);
  try
    ini.WriteBool('Window', 'Maximized', WindowState = wsMaximized);
    if WindowState = wsNormal then
    begin
      ini.WriteInteger('Window', 'Left', Left);
      ini.WriteInteger('Window', 'Top', Top);
      ini.WriteInteger('Window', 'Width', ScaleFormTo96(Width));
      ini.WriteInteger('Window', 'Height', ScaleFormTo96(Height));
    end;
    ini.WriteInteger('Window', 'TreeWidth', ScaleFormTo96(FLeft.Width));
    ini.WriteInteger('View', 'FontSize', FZoom);
    ini.WriteBool('View', 'DocumentsOnly', FDocsOnly);
    ini.WriteBool('View', 'WordWrap', FWordWrap);
    ini.WriteBool('View', 'KeepLineBreaks', FLineBreaks);
    ini.WriteString('Main', 'Folder', FRoot);
  finally
    ini.Free;
  end;
end;

function TfrmMain.SessionSection: string;
begin
  Result := 'Session ' + LowerCase(FRoot);
end;

procedure TfrmMain.SaveSession;
var
  ini: TIniFile;
  i: Integer;
  d: TDocSheet;
  exp: TStringList;
  sec: string;
begin
  if FRoot = '' then
    Exit;
  ini := TIniFile.Create(FIniName);
  try
    sec := SessionSection;
    ini.EraseSection(sec);
    ini.WriteInteger(sec, 'Count', FPages.PageCount);
    for i := 0 to FPages.PageCount - 1 do
    begin
      d := TDocSheet(FPages.Pages[i]);
      ini.WriteString(sec, 'File' + IntToStr(i), RelPath(d.FileName));
      if d.Mode = vmView then
        ini.WriteString(sec, 'Mode' + IntToStr(i), 'view')
      else
        ini.WriteString(sec, 'Mode' + IntToStr(i), 'edit');
      ini.WriteInteger(sec, 'Line' + IntToStr(i), d.Editor.TopLine);
    end;
    ini.WriteInteger(sec, 'Active', FPages.ActivePageIndex);
    if FInSearch then
      exp := TStringList.Create
    else
      exp := ExpandedPaths;
    try
      if FInSearch then
        exp.Assign(FPreSearchExpanded);
      exp.Delimiter := '|';
      exp.StrictDelimiter := True;
      ini.WriteString(sec, 'Expanded', exp.DelimitedText);
    finally
      exp.Free;
    end;
    if (not FInSearch) and (FTree.Selected <> nil) then
      ini.WriteString(sec, 'Selected', RelPath(NodePath(FTree.Selected)));
    if (not FInSearch) and (FTree.TopItem <> nil) then
      ini.WriteString(sec, 'TopItem', RelPath(NodePath(FTree.TopItem)));
  finally
    ini.Free;
  end;
end;

procedure TfrmMain.RestoreSession;
var
  ini: TIniFile;
  i, n, act: Integer;
  sec, fn, md: string;
  exp: TStringList;
  d: TDocSheet;
begin
  ini := TIniFile.Create(FIniName);
  exp := TStringList.Create;
  FLoadingSession := True;
  try
    sec := SessionSection;
    exp.Delimiter := '|';
    exp.StrictDelimiter := True;
    exp.DelimitedText := ini.ReadString(sec, 'Expanded', '');
    for i := 0 to exp.Count - 1 do
      exp[i] := AbsPath(exp[i]);
    LoadTree(exp, AbsPath(ini.ReadString(sec, 'Selected', '')),
      AbsPath(ini.ReadString(sec, 'TopItem', '')));

    n := ini.ReadInteger(sec, 'Count', 0);
    for i := 0 to n - 1 do
    begin
      fn := AbsPath(ini.ReadString(sec, 'File' + IntToStr(i), ''));
      if (fn = '') or not FileExistsUTF8(fn) then
        Continue;
      md := ini.ReadString(sec, 'Mode' + IntToStr(i), '');
      if md = 'edit' then
        d := OpenFile(fn, Ord(vmEdit))
      else if md = 'view' then
        d := OpenFile(fn, Ord(vmView))
      else
        d := OpenFile(fn);
      if d <> nil then
        d.Editor.TopLine := ini.ReadInteger(sec, 'Line' + IntToStr(i), 1);
    end;
    act := ini.ReadInteger(sec, 'Active', 0);
    if (act >= 0) and (act < FPages.PageCount) then
      FPages.ActivePageIndex := act;
  finally
    FLoadingSession := False;
    exp.Free;
    ini.Free;
  end;
  UpdateUI;
end;

procedure TfrmMain.AddRecent(const ADir: string);
var
  ini: TIniFile;
  list: TStringList;
  i: Integer;
begin
  ini := TIniFile.Create(FIniName);
  list := TStringList.Create;
  try
    for i := 0 to 14 do
      if ini.ValueExists('Recent', 'Folder' + IntToStr(i)) then
        list.Add(ini.ReadString('Recent', 'Folder' + IntToStr(i), ''));
    for i := list.Count - 1 downto 0 do
      if SameText(list[i], ADir) or (list[i] = '') then
        list.Delete(i);
    list.Insert(0, ADir);
    while list.Count > 15 do
      list.Delete(list.Count - 1);
    ini.EraseSection('Recent');
    for i := 0 to list.Count - 1 do
      ini.WriteString('Recent', 'Folder' + IntToStr(i), list[i]);
  finally
    list.Free;
    ini.Free;
  end;
  RebuildRecentMenu;
end;

procedure TfrmMain.RebuildRecentMenu;
var
  ini: TIniFile;
  i: Integer;
  s: string;
  mi: TMenuItem;
begin
  FRecentMenu.Clear;
  ini := TIniFile.Create(FIniName);
  try
    for i := 0 to 14 do
    begin
      s := ini.ReadString('Recent', 'Folder' + IntToStr(i), '');
      if s = '' then
        Continue;
      mi := TMenuItem.Create(FRecentMenu);
      mi.Caption := StringReplace(s, '&', '&&', [rfReplaceAll]);
      mi.Hint := s;
      mi.Tag := i;
      mi.OnClick := @RecentClick;
      FRecentMenu.Add(mi);
    end;
  finally
    ini.Free;
  end;
  FRecentMenu.Enabled := FRecentMenu.Count > 0;
end;

procedure TfrmMain.RecentClick(Sender: TObject);
var
  s: string;
begin
  s := TMenuItem(Sender).Hint;
  if DirectoryExistsUTF8(s) then
    OpenFolder(s)
  else
    MessageDlg(AppTitle, 'The folder no longer exists:' + LineEnding + s, mtWarning, [mbOK], 0);
end;

{ ---------- folder / tree ---------- }

procedure TfrmMain.OpenFolder(const ADir: string);
var
  dir: string;
begin
  dir := ExpandFileNameUTF8(ADir);
  if (Length(dir) > 3) then
    dir := ChompPathDelim(dir);
  if FRoot <> '' then
  begin
    if FPages.PageCount > 0 then
      SaveSession;
    if not CloseAllDocs then
      Exit;
  end;
  FRoot := dir;
  FInSearch := False;
  FFilterEdit.OnChange := nil;
  FFilterEdit.Text := '';
  FFilterEdit.OnChange := @FilterChange;
  FFolderLabel.Caption := ExtractFileName(ChompPathDelim(dir));
  if FFolderLabel.Caption = '' then
    FFolderLabel.Caption := dir;
  FFolderLabel.Hint := dir;
  Caption := FFolderLabel.Caption + ' - ' + AppTitle;
  AddRecent(dir);
  SaveSettings;
  RestoreSession;
end;

function TfrmMain.RelPath(const APath: string): string;
var
  root: string;
begin
  root := AppendPathDelim(FRoot);
  if (APath <> '') and SameText(Copy(APath, 1, Length(root)), root) then
    Result := Copy(APath, Length(root) + 1, MaxInt)
  else
    Result := APath;
end;

function TfrmMain.AbsPath(const ARel: string): string;
begin
  if ARel = '' then
    Result := ''
  else if (Length(ARel) > 1) and ((ARel[2] = ':') or (Copy(ARel, 1, 2) = '\\')) then
    Result := ARel
  else
    Result := AppendPathDelim(FRoot) + ARel;
end;

function TfrmMain.IsSkippedDir(const AName: string): Boolean;
begin
  Result := Pos(';' + LowerCase(AName) + ';', SkipDirs) > 0;
end;

function TfrmMain.PassesFilter(const AName: string; AIsDir: Boolean; const AFull: string): Boolean;
begin
  if AIsDir then
  begin
    if SameText(AName, '.git') then
      Exit(False);
    if FDocsOnly then
      Result := (not IsSkippedDir(AName)) and DirHasDocs(AFull, 0)
    else
      Result := True;
  end
  else
    Result := (not FDocsOnly) or ExtIn(AName, DocExts);
end;

function TfrmMain.DirHasDocs(const ADir: string; ADepth: Integer): Boolean;
var
  sr: TSearchRec;
  idx: Integer;
begin
  idx := FDocsCache.IndexOf(ADir);
  if idx >= 0 then
    Exit(FDocsCache.Objects[idx] <> nil);
  Result := False;
  if ADepth > 8 then
    Exit;
  if FindFirstUTF8(AppendPathDelim(ADir) + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      if (sr.Attr and faDirectory) = 0 then
        if ExtIn(sr.Name, DocExts) then
        begin
          Result := True;
          Break;
        end;
    until FindNextUTF8(sr) <> 0;
  finally
    FindCloseUTF8(sr);
  end;
  if not Result then
    if FindFirstUTF8(AppendPathDelim(ADir) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then
          Continue;
        if ((sr.Attr and faDirectory) <> 0) and not IsSkippedDir(sr.Name) then
          if DirHasDocs(AppendPathDelim(ADir) + sr.Name, ADepth + 1) then
          begin
            Result := True;
            Break;
          end;
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
  FDocsCache.AddObject(ADir, TObject(PtrInt(Ord(Result))));
end;

procedure TfrmMain.FillChildren(AParent: TTreeNode; const ADir: string);
var
  sr: TSearchRec;
  dirs, files: TStringList;
  i: Integer;
  node: TTreeNode;
  info: TNodeInfo;
  full: string;
begin
  dirs := TStringList.Create;
  files := TStringList.Create;
  try
    if FindFirstUTF8(AppendPathDelim(ADir) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then
          Continue;
        full := AppendPathDelim(ADir) + sr.Name;
        if (sr.Attr and faDirectory) <> 0 then
        begin
          if PassesFilter(sr.Name, True, full) then
            dirs.Add(sr.Name);
        end
        else if PassesFilter(sr.Name, False, full) then
          files.Add(sr.Name);
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
    dirs.CustomSort(@CompareNames);
    files.CustomSort(@CompareNames);
    for i := 0 to dirs.Count - 1 do
    begin
      info := TNodeInfo.Create;
      info.Path := AppendPathDelim(ADir) + dirs[i];
      info.IsDir := True;
      node := FTree.Items.AddChildObject(AParent, dirs[i], info);
      node.ImageIndex := IconFolder;
      node.SelectedIndex := IconFolder;
      node.HasChildren := True;
    end;
    for i := 0 to files.Count - 1 do
    begin
      info := TNodeInfo.Create;
      info.Path := AppendPathDelim(ADir) + files[i];
      info.IsDir := False;
      node := FTree.Items.AddChildObject(AParent, files[i], info);
      if ExtIn(files[i], MarkdownExts) then
        node.ImageIndex := IconMarkdown
      else if ExtIn(files[i], '.pdf;') then
        node.ImageIndex := IconPdf
      else if ExtIn(files[i], TextExts) then
        node.ImageIndex := IconText
      else
        node.ImageIndex := IconBinary;
      node.SelectedIndex := node.ImageIndex;
    end;
    if AParent <> nil then
    begin
      TNodeInfo(AParent.Data).Loaded := True;
      AParent.HasChildren := AParent.Count > 0;
    end;
  finally
    dirs.Free;
    files.Free;
  end;
end;

function TfrmMain.NodePath(ANode: TTreeNode): string;
begin
  if (ANode <> nil) and (ANode.Data <> nil) then
    Result := TNodeInfo(ANode.Data).Path
  else
    Result := '';
end;

function TfrmMain.ExpandedPaths: TStringList;
var
  n: TTreeNode;
begin
  Result := TStringList.Create;
  n := FTree.Items.GetFirstNode;
  while n <> nil do
  begin
    if n.Expanded and (n.Data <> nil) and TNodeInfo(n.Data).IsDir then
      Result.Add(RelPath(TNodeInfo(n.Data).Path));
    n := n.GetNext;
  end;
end;

function TfrmMain.FindNode(const APath: string; AExpandParents: Boolean): TTreeNode;
var
  rel, part: string;
  parts: TStringList;
  i: Integer;
  n, parentNode: TTreeNode;
begin
  Result := nil;
  if (APath = '') or FInSearch then
  begin
    if FInSearch then
    begin
      n := FTree.Items.GetFirstNode;
      while n <> nil do
      begin
        if SameText(NodePath(n), APath) then
          Exit(n);
        n := n.GetNextSibling;
      end;
    end;
    Exit;
  end;
  rel := RelPath(APath);
  if SameText(rel, APath) then
    Exit;   // outside the root
  parts := TStringList.Create;
  try
    parts.Delimiter := PathDelim;
    parts.StrictDelimiter := True;
    parts.DelimitedText := rel;
    parentNode := nil;
    for i := 0 to parts.Count - 1 do
    begin
      part := parts[i];
      if parentNode = nil then
        n := FTree.Items.GetFirstNode
      else
      begin
        if (parentNode.Data <> nil) and not TNodeInfo(parentNode.Data).Loaded then
        begin
          if not AExpandParents then
            Exit;
          FillChildren(parentNode, TNodeInfo(parentNode.Data).Path);
        end;
        n := parentNode.GetFirstChild;
      end;
      while (n <> nil) and not SameText(n.Text, part) do
        n := n.GetNextSibling;
      if n = nil then
        Exit;
      if (i < parts.Count - 1) and AExpandParents then
        n.Expanded := True;
      parentNode := n;
    end;
    Result := parentNode;
  finally
    parts.Free;
  end;
end;

procedure TfrmMain.LoadTree(AExpanded: TStrings; const ASelected, ATop: string);
var
  exp: TStringList;
  i: Integer;
  n: TTreeNode;
begin
  FTree.Items.BeginUpdate;
  try
    FDocsCache.Clear;
    FTree.Items.Clear;
    if FRoot = '' then
      Exit;
    FillChildren(nil, FRoot);
    if AExpanded <> nil then
    begin
      exp := TStringList.Create;
      try
        for i := 0 to AExpanded.Count - 1 do
          exp.Add(RelPath(AExpanded[i]));
        exp.CustomSort(@CompareDepth);
        for i := 0 to exp.Count - 1 do
        begin
          n := FindNode(AbsPath(exp[i]), False);
          if n <> nil then
            n.Expanded := True;
        end;
      finally
        exp.Free;
      end;
    end;
    n := FindNode(ASelected, False);
    if n <> nil then
      n.Selected := True;
  finally
    FTree.Items.EndUpdate;
  end;
  n := FindNode(ATop, False);
  if n <> nil then
    FTree.TopItem := n;
  FTreeSig := ComputeTreeSig;
end;

procedure TfrmMain.FillSearchResults(const AText: string);
var
  needle: string;
  count: Integer;

  procedure Walk(const ADir: string; ADepth: Integer);
  var
    sr: TSearchRec;
    full: string;
    info: TNodeInfo;
    node: TTreeNode;
    subdirs: TStringList;
    i: Integer;
  begin
    if (ADepth > 12) or (count >= 1000) then
      Exit;
    subdirs := TStringList.Create;
    try
      if FindFirstUTF8(AppendPathDelim(ADir) + '*', faAnyFile, sr) = 0 then
      try
        repeat
          if (sr.Name = '.') or (sr.Name = '..') then
            Continue;
          full := AppendPathDelim(ADir) + sr.Name;
          if (sr.Attr and faDirectory) <> 0 then
          begin
            if not IsSkippedDir(sr.Name) then
              subdirs.Add(full);
          end
          else if PassesFilter(sr.Name, False, full) and
            (Pos(needle, UTF8LowerCase(sr.Name)) > 0) then
          begin
            info := TNodeInfo.Create;
            info.Path := full;
            node := FTree.Items.AddChildObject(nil, RelPath(full), info);
            if ExtIn(sr.Name, MarkdownExts) then
              node.ImageIndex := IconMarkdown
            else if ExtIn(sr.Name, '.pdf;') then
              node.ImageIndex := IconPdf
            else if ExtIn(sr.Name, TextExts) then
              node.ImageIndex := IconText
            else
              node.ImageIndex := IconBinary;
            node.SelectedIndex := node.ImageIndex;
            Inc(count);
          end;
        until FindNextUTF8(sr) <> 0;
      finally
        FindCloseUTF8(sr);
      end;
      subdirs.Sort;
      for i := 0 to subdirs.Count - 1 do
        Walk(subdirs[i], ADepth + 1);
    finally
      subdirs.Free;
    end;
  end;

begin
  needle := UTF8LowerCase(Trim(AText));
  count := 0;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    if FRoot <> '' then
      Walk(FRoot, 0);
  finally
    FTree.Items.EndUpdate;
  end;
  if count = 0 then
    FStatus.Panels[0].Text := 'No files match "' + AText + '"'
  else
    FStatus.Panels[0].Text := IntToStr(count) + ' file(s) match "' + AText + '"';
end;

procedure TfrmMain.RefreshTree;
var
  exp: TStringList;
  sel, topPath: string;
begin
  if FRoot = '' then
    Exit;
  if FInSearch then
  begin
    FillSearchResults(FFilterEdit.Text);
    Exit;
  end;
  exp := ExpandedPaths;
  try
    sel := NodePath(FTree.Selected);
    topPath := NodePath(FTree.TopItem);
    LoadTree(exp, sel, topPath);
  finally
    exp.Free;
  end;
end;

function TfrmMain.ComputeTreeSig: string;

  function Listing(const ADir: string): string;
  var
    sr: TSearchRec;
  begin
    Result := '';
    if FindFirstUTF8(AppendPathDelim(ADir) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        Result := Result + sr.Name + '/';
      until FindNextUTF8(sr) <> 0;
    finally
      FindCloseUTF8(sr);
    end;
  end;

var
  n: TTreeNode;
begin
  Result := '';
  if (FRoot = '') or FInSearch then
    Exit;
  Result := Listing(FRoot);
  n := FTree.Items.GetFirstNode;
  while n <> nil do
  begin
    if (n.Data <> nil) and TNodeInfo(n.Data).IsDir and TNodeInfo(n.Data).Loaded then
      Result := Result + '|' + Listing(TNodeInfo(n.Data).Path);
    n := n.GetNext;
  end;
end;

procedure TfrmMain.SelectInTree(const APath: string);
var
  n: TTreeNode;
begin
  if FInSearch then
  begin
    FFilterEdit.Text := '';
    FilterTimer(nil);
  end;
  n := FindNode(APath, True);
  if n <> nil then
  begin
    n.Selected := True;
    n.MakeVisible;
  end;
end;

procedure TfrmMain.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  info: TNodeInfo;
begin
  info := TNodeInfo(Node.Data);
  if (info <> nil) and info.IsDir and not info.Loaded then
    FillChildren(Node, info.Path);
  AllowExpansion := True;
end;

procedure TfrmMain.TreeExpandedChanged(Sender: TObject; Node: TTreeNode);
begin
  if (Node.Data <> nil) and TNodeInfo(Node.Data).IsDir then
  begin
    if Node.Expanded then
      Node.ImageIndex := IconFolderOpen
    else
      Node.ImageIndex := IconFolder;
    Node.SelectedIndex := Node.ImageIndex;
  end;
end;

procedure TfrmMain.TreeDeletion(Sender: TObject; Node: TTreeNode);
begin
  TObject(Node.Data).Free;
  Node.Data := nil;
end;

procedure TfrmMain.TreeMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  n: TTreeNode;
  hit: THitTests;
begin
  if Button <> mbLeft then
    Exit;
  hit := FTree.GetHitTestInfoAt(X, Y);
  if (hit * [htOnItem, htOnIcon, htOnLabel]) = [] then
    Exit;
  n := FTree.GetNodeAt(X, Y);
  if (n = nil) or (n.Data = nil) then
    Exit;
  if TNodeInfo(n.Data).IsDir then
  begin
    if not (htOnButton in hit) then
      n.Expanded := not n.Expanded;
  end
  else
    OpenFile(TNodeInfo(n.Data).Path);
end;

procedure TfrmMain.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  n: TTreeNode;
begin
  n := FTree.Selected;
  if (Key = VK_RETURN) and (n <> nil) and (n.Data <> nil) then
  begin
    if TNodeInfo(n.Data).IsDir then
      n.Expanded := not n.Expanded
    else
      OpenFile(TNodeInfo(n.Data).Path);
    Key := 0;
  end;
end;

procedure TfrmMain.FilterChange(Sender: TObject);
begin
  FFilterTimer.Enabled := False;
  FFilterTimer.Enabled := True;
end;

procedure TfrmMain.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    FFilterEdit.Text := '';
    FilterTimer(nil);
    FTree.SetFocus;
    Key := 0;
  end
  else if (Key = VK_DOWN) or (Key = VK_RETURN) then
  begin
    FilterTimer(nil);
    FTree.SetFocus;
    if (FTree.Selected = nil) and (FTree.Items.GetFirstNode <> nil) then
      FTree.Items.GetFirstNode.Selected := True;
    Key := 0;
  end;
end;

procedure TfrmMain.FilterTimer(Sender: TObject);
var
  txt: string;
  exp: TStringList;
begin
  FFilterTimer.Enabled := False;
  txt := Trim(FFilterEdit.Text);
  if txt <> '' then
  begin
    if not FInSearch then
    begin
      exp := ExpandedPaths;
      try
        FPreSearchExpanded.Clear;
        FPreSearchExpanded.AddStrings(exp);
      finally
        exp.Free;
      end;
      FInSearch := True;
    end;
    FillSearchResults(txt);
  end
  else if FInSearch then
  begin
    FInSearch := False;
    LoadTree(FPreSearchExpanded, '', '');
    UpdateUI;
  end;
end;

{ ---------- documents ---------- }

function TfrmMain.ActiveDoc: TDocSheet;
begin
  if (FPages.ActivePage <> nil) and (FPages.ActivePage is TDocSheet) then
    Result := TDocSheet(FPages.ActivePage)
  else
    Result := nil;
end;

function TfrmMain.FindDoc(const AFileName: string): TDocSheet;
var
  i: Integer;
begin
  for i := 0 to FPages.PageCount - 1 do
    if SameText(TDocSheet(FPages.Pages[i]).FileName, AFileName) then
      Exit(TDocSheet(FPages.Pages[i]));
  Result := nil;
end;

function TfrmMain.IsTextFile(const AFileName: string): Boolean;
var
  fs: TFileStream;
  buf: array[0..4095] of Byte;
  n, i: Integer;
begin
  if ExtIn(AFileName, TextExts) then
    Exit(True);
  if ExtIn(AFileName, BinaryExts) then
    Exit(False);
  // unknown: look for NUL bytes in the first 4 KB
  Result := False;
  try
    fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      n := fs.Read(buf, SizeOf(buf));
    finally
      fs.Free;
    end;
    if (n >= 2) and (((buf[0] = $FF) and (buf[1] = $FE)) or ((buf[0] = $FE) and (buf[1] = $FF))) then
      Exit(True);
    for i := 0 to n - 1 do
      if buf[i] = 0 then
        Exit(False);
    Result := True;
  except
    Result := False;
  end;
end;

function TfrmMain.HighlighterFor(const AFileName: string): TSynCustomHighlighter;
begin
  if ExtIn(AFileName, MarkdownExts) then Result := FHlMarkdown
  else if ExtIn(AFileName, '.sql;') then Result := FHlSQL
  else if ExtIn(AFileName, '.pas;.pp;.lpr;.inc;.dpr;') then Result := FHlPas
  else if ExtIn(AFileName, '.xml;.csproj;.props;.targets;.lpi;.lps;.config;.runsettings;.svg;.resx;.xaml;') then Result := FHlXML
  else if ExtIn(AFileName, '.html;.htm;.cshtml;.razor;.vue;') then Result := FHlHTML
  else if ExtIn(AFileName, '.js;.ts;.tsx;.jsx;.mjs;.json;') then Result := FHlJS
  else if ExtIn(AFileName, '.cs;.c;.h;.cpp;.hpp;.java;.kt;.swift;.go;.rs;.dart;') then Result := FHlCpp
  else if ExtIn(AFileName, '.py;') then Result := FHlPython
  else if ExtIn(AFileName, '.ini;.cfg;.editorconfig;.toml;.properties;.env;') then Result := FHlIni
  else if ExtIn(AFileName, '.bat;.cmd;') then Result := FHlBat
  else if ExtIn(AFileName, '.patch;.diff;') then Result := FHlDiff
  else if ExtIn(AFileName, '.css;.scss;') then Result := FHlCss
  else Result := nil;
end;

function TfrmMain.OpenFile(const AFileName: string; AMode: Integer): TDocSheet;
var
  d: TDocSheet;
begin
  Result := nil;
  if not FileExistsUTF8(AFileName) then
    Exit;
  d := FindDoc(AFileName);
  if d <> nil then
  begin
    FPages.ActivePage := d;
    if AMode >= 0 then
      SetDocMode(d, TViewMode(AMode));
    UpdateUI;
    Exit(d);
  end;
  if not IsTextFile(AFileName) then
  begin
    if not FLoadingSession then
      OpenDocument(AFileName);
    Exit;
  end;

  d := TDocSheet.Create(FPages);
  d.PageControl := FPages;
  d.FileName := AFileName;
  d.IsMarkdown := ExtIn(AFileName, MarkdownExts);
  d.CanView := d.IsMarkdown or ExtIn(AFileName, '.html;.htm;');
  d.Caption := ExtractFileName(AFileName);

  d.Editor := TSynEdit.Create(d);
  d.Editor.Parent := d;
  d.Editor.Align := alClient;
  d.Editor.BorderStyle := bsNone;
  d.Editor.Font.Name := 'Consolas';
  d.Editor.Font.Quality := fqCleartypeNatural;
  d.Editor.Highlighter := HighlighterFor(AFileName);
  d.Editor.Options := d.Editor.Options + [eoTabsToSpaces] - [eoSmartTabs, eoScrollPastEol];
  d.Editor.TabWidth := 4;
  d.Editor.RightEdge := -1;
  d.Editor.OnChange := @EditorChange;
  d.Editor.OnStatusChange := @EditorStatus;

  if d.CanView then
  begin
    d.Viewer := TIpHtmlPanel.Create(d);
    d.Viewer.Parent := d;
    d.Viewer.Align := alClient;
    d.Viewer.BorderStyle := bsNone;
    d.Viewer.DefaultTypeFace := 'Segoe UI';
    d.Viewer.FixedTypeface := 'Consolas';
    d.Viewer.MarginWidth := 24;
    d.Viewer.MarginHeight := 16;
    d.Viewer.LinkColor := $00D26909;
    d.Viewer.VLinkColor := $00D26909;
    d.Viewer.ShowHints := False;
    d.Viewer.OnHotClick := @ViewerHotClick;
    d.Viewer.OnHotChange := @ViewerHotChange;
    d.Viewer.PopupMenu := FViewerMenu;
    // IPro measures words on the control's canvas but, with a paint buffer,
    // draws them on a bitmap whose fonts keep the startup DPI. After the
    // window moves to a monitor with other scaling the two disagree and the
    // words overlap. Drawing straight onto the control canvas keeps them equal.
    d.Viewer.UsePaintBuffer := False;
  end;

  LoadDoc(d, False);
  ApplyWrap(d);
  d.Editor.Font.Size := FZoom;
  if d.Viewer <> nil then
    d.Viewer.DefaultFontSize := FZoom;

  if AMode >= 0 then
    SetDocMode(d, TViewMode(AMode))
  else if d.IsMarkdown then
    SetDocMode(d, vmView)
  else
    SetDocMode(d, vmEdit);

  FPages.ActivePage := d;
  UpdateUI;
  Result := d;
end;

procedure TfrmMain.LoadDoc(ADoc: TDocSheet; AKeepPosition: Boolean);
var
  raw: RawByteString;
  txt: string;
  ws: UnicodeString;
  topLine: Integer;
  caret: TPoint;
  stamp, size: Int64;
begin
  try
    raw := ReadAllBytes(ADoc.FileName);
  except
    on E: Exception do
    begin
      MessageDlg(AppTitle, 'Could not read ' + ADoc.FileName + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  GetFileStamp(ADoc.FileName, stamp, size);
  ADoc.DiskStamp := stamp;
  ADoc.DiskSize := size;
  ADoc.Missing := False;

  if (Length(raw) >= 3) and (raw[1] = #$EF) and (raw[2] = #$BB) and (raw[3] = #$BF) then
  begin
    ADoc.Encoding := feUTF8BOM;
    txt := Copy(raw, 4, MaxInt);
  end
  else if (Length(raw) >= 2) and (raw[1] = #$FF) and (raw[2] = #$FE) then
  begin
    ADoc.Encoding := feUTF16LE;
    SetLength(ws, (Length(raw) - 2) div 2);
    if Length(ws) > 0 then
      Move(raw[3], ws[1], Length(ws) * 2);
    txt := UTF8Encode(ws);
  end
  else if FindInvalidUTF8Codepoint(PChar(raw), Length(raw)) >= 0 then
  begin
    ADoc.Encoding := feAnsi;
    txt := CP1252ToUTF8(raw);
  end
  else
  begin
    ADoc.Encoding := feUTF8;
    txt := raw;
  end;

  if Pos(#13#10, txt) > 0 then
    ADoc.LineBreak := #13#10
  else if Pos(#10, txt) > 0 then
    ADoc.LineBreak := #10
  else
    ADoc.LineBreak := #13#10;
  ADoc.TrailingEOL := (txt <> '') and (txt[Length(txt)] in [#10, #13]);

  topLine := ADoc.Editor.TopLine;
  caret := ADoc.Editor.CaretXY;
  ADoc.Editor.BeginUpdate;
  try
    ADoc.Editor.Lines.Text := txt;
  finally
    ADoc.Editor.EndUpdate;
  end;
  ADoc.Editor.Modified := False;
  if AKeepPosition then
  begin
    if caret.Y > ADoc.Editor.Lines.Count then
      caret.Y := ADoc.Editor.Lines.Count;
    if caret.Y < 1 then
      caret.Y := 1;
    ADoc.Editor.CaretXY := caret;
    ADoc.Editor.TopLine := topLine;
  end;
  ADoc.ViewDirty := True;
  // a reloaded tab in the background keeps its old page (and place) until it
  // is shown; PagesChange redraws it then
  if (ADoc.Mode = vmView) and ((ADoc = FPages.ActivePage) or not AKeepPosition) then
    RenderDoc(ADoc, AKeepPosition);
  UpdateCaption(ADoc);
end;

function TfrmMain.SaveDoc(ADoc: TDocSheet): Boolean;
var
  i: Integer;
  txt: string;
  sb: TStringStream;
  raw: RawByteString;
  ws: UnicodeString;
  stamp, size: Int64;
begin
  Result := False;
  sb := TStringStream.Create('');
  try
    for i := 0 to ADoc.Editor.Lines.Count - 1 do
    begin
      sb.WriteString(ADoc.Editor.Lines[i]);
      if (i < ADoc.Editor.Lines.Count - 1) or ADoc.TrailingEOL then
        sb.WriteString(ADoc.LineBreak);
    end;
    txt := sb.DataString;
  finally
    sb.Free;
  end;
  case ADoc.Encoding of
    feUTF8BOM: raw := #$EF#$BB#$BF + txt;
    feUTF16LE:
      begin
        ws := UTF8Decode(txt);
        SetLength(raw, 2 + Length(ws) * 2);
        raw[1] := #$FF;
        raw[2] := #$FE;
        if Length(ws) > 0 then
          Move(ws[1], raw[3], Length(ws) * 2);
      end;
    feAnsi: raw := UTF8ToCP1252(txt);
  else
    raw := txt;
  end;
  try
    WriteAllBytes(ADoc.FileName, raw);
  except
    on E: Exception do
    begin
      MessageDlg(AppTitle, 'Could not save ' + ADoc.FileName + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  GetFileStamp(ADoc.FileName, stamp, size);
  ADoc.DiskStamp := stamp;
  ADoc.DiskSize := size;
  ADoc.Missing := False;
  ADoc.Editor.Modified := False;
  ADoc.Editor.MarkTextAsSaved;
  UpdateCaption(ADoc);
  UpdateUI;
  Result := True;
end;

function TfrmMain.CloseDoc(ADoc: TDocSheet): Boolean;
begin
  Result := False;
  if ADoc = nil then
    Exit;
  if ADoc.Editor.Modified then
  begin
    FPages.ActivePage := ADoc;
    case MessageDlg(AppTitle, 'Save changes to ' + ExtractFileName(ADoc.FileName) + '?',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes:
        if not SaveDoc(ADoc) then
          Exit;
      mrNo: ;
    else
      Exit;
    end;
  end;
  { Close Tab can fire while the tab's own viewer or editor is still handling
    the key (Alt+C, Ctrl+W), and freeing it then leaves that handler running on
    a freed control. So the tab leaves the page control now and is freed once
    the current message is done. }
  ADoc.PageControl := nil;
  Application.ReleaseComponent(ADoc);
  Result := True;
  UpdateUI;
end;

function TfrmMain.CloseAllDocs(AExcept: TDocSheet): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := FPages.PageCount - 1 downto 0 do
    if FPages.Pages[i] <> AExcept then
      if not CloseDoc(TDocSheet(FPages.Pages[i])) then
        Exit(False);
end;

type
  // gives access to the frame's protected page panel
  TIpFrameAccess = class(TIpHtmlFrame);

{ IPro lays a new page out (and so sets its scroll height) only when it first
  paints it, so a scroll position set straight after SetHtmlFromStr is clamped
  to 0 and the view jumps to the top. Lay the page out first, then scroll. }
procedure RestoreViewerScroll(AViewer: TIpHtmlPanel; APos: Integer);
var
  hp: TIpHtmlInternalPanel;
  r: TRect;
begin
  if AViewer.MasterFrame <> nil then
  begin
    hp := TIpFrameAccess(AViewer.MasterFrame).HyperPanel;
    if (hp <> nil) and AViewer.HandleAllocated then
    begin
      hp.HandleNeeded;
      r := hp.PageRect;  // reading it lays the page out and sets the scroll range
    end;
  end;
  AViewer.VScrollPos := APos;
end;

procedure TfrmMain.RenderDoc(ADoc: TDocSheet; AKeepScroll: Boolean);
var
  html: string;
  pos: Integer;
begin
  if ADoc.Viewer = nil then
    Exit;
  pos := 0;
  if AKeepScroll then
    pos := ADoc.Viewer.VScrollPos;
  if ADoc.IsMarkdown then
    html := MarkdownToHtml(ADoc.Editor.Lines.Text, FZoom, FLineBreaks)
  else
    html := ADoc.Editor.Lines.Text;
  try
    ADoc.Viewer.SetHtmlFromStr(html);
  except
    on E: Exception do
      ADoc.Viewer.SetHtmlFromStr('<html><body><p><b>Could not show this file:</b> ' +
        HtmlEscape(E.Message) + '</p></body></html>');
  end;
  ADoc.ViewDirty := False;
  if AKeepScroll and (pos > 0) then
    RestoreViewerScroll(ADoc.Viewer, pos);
  if ADoc.PendingAnchor <> '' then
  begin
    ADoc.Viewer.MakeAnchorVisible(ADoc.PendingAnchor);
    ADoc.PendingAnchor := '';
  end;
end;

procedure TfrmMain.SetDocMode(ADoc: TDocSheet; AMode: TViewMode);
begin
  if not ADoc.CanView then
    AMode := vmEdit;
  ADoc.Mode := AMode;
  if AMode = vmView then
  begin
    if ADoc.ViewDirty then
      RenderDoc(ADoc, True);
    ADoc.Viewer.Visible := True;
    ADoc.Editor.Visible := False;
    if ADoc.Viewer.CanFocus and Visible and not FLoadingSession then
      ADoc.Viewer.SetFocus;
  end
  else
  begin
    if ADoc.Viewer <> nil then
      ADoc.Viewer.Visible := False;
    ADoc.Editor.Visible := True;
    if ADoc.Editor.CanFocus and Visible and not FLoadingSession then
      ADoc.Editor.SetFocus;
  end;
  UpdateUI;
end;

procedure TfrmMain.ApplyWrap(ADoc: TDocSheet);
begin
  { SynEdit (Lazarus 4.8) crashes when the top text view is removed: the
    caret then unhooks from that view after it has lost its manager. Freeing
    the wrap plugin removes its view, which is on top. So before freeing it,
    a pass-through view goes on top and the caret moves there first; when wrap
    comes back on, the new wrap view is on top and the spacer can go. }
  if FWordWrap and (ADoc.WrapPlugin = nil) then
  begin
    ADoc.WrapPlugin := TLazSynEditLineWrapPlugin.Create(ADoc.Editor);
    if ADoc.WrapSpacer <> nil then
    begin
      ADoc.Editor.TextViewsManager.RemoveSynTextView(ADoc.WrapSpacer, True);
      ADoc.WrapSpacer := nil;
    end;
  end
  else if (not FWordWrap) and (ADoc.WrapPlugin <> nil) then
  begin
    if ADoc.WrapSpacer = nil then
    begin
      ADoc.WrapSpacer := TSynEditStringsLinked.Create;
      ADoc.Editor.TextViewsManager.AddTextView(ADoc.WrapSpacer);
    end;
    ADoc.WrapPlugin.Free;
    ADoc.WrapPlugin := nil;
  end;
end;

procedure TfrmMain.ApplyZoom;
var
  i: Integer;
  d: TDocSheet;
begin
  for i := 0 to FPages.PageCount - 1 do
  begin
    d := TDocSheet(FPages.Pages[i]);
    d.Editor.Font.Size := FZoom;
    if d.Viewer <> nil then
    begin
      d.Viewer.DefaultFontSize := FZoom;
      d.ViewDirty := True;
      if d.Mode = vmView then
        RenderDoc(d, True);
    end;
  end;
  FStatus.Panels[3].Text := 'Zoom ' + IntToStr(FZoom) + 'pt';
end;

procedure TfrmMain.UpdateCaption(ADoc: TDocSheet);
var
  s: string;
begin
  s := ExtractFileName(ADoc.FileName);
  if ADoc.Missing then
    s := s + ' (deleted)';
  if ADoc.Editor.Modified then
    s := s + ' *';
  if ADoc.Caption <> s then
    ADoc.Caption := s;
  ADoc.Hint := ADoc.FileName;
end;

procedure TfrmMain.UpdateUI;
var
  d: TDocSheet;
  enc: string;
begin
  d := ActiveDoc;
  FPages.Visible := FPages.PageCount > 0;
  FEmptyPanel.Visible := not FPages.Visible;
  if FRoot = '' then
    FEmptyLabel.Caption := 'Open a folder to start  (File > Open Folder, Ctrl+O)'
  else
    FEmptyLabel.Caption := 'Pick a file on the left to open it.' + LineEnding + LineEnding +
      'Markdown opens formatted; press Ctrl+E to edit it.';

  actSave.Enabled := (d <> nil);
  actSaveAll.Enabled := FPages.PageCount > 0;
  actCloseTab.Enabled := d <> nil;
  actCloseAll.Enabled := FPages.PageCount > 0;
  actCloseOthers.Enabled := FPages.PageCount > 1;
  actToggleMode.Enabled := (d <> nil) and d.CanView;
  actRevealInTree.Enabled := (d <> nil) and (FRoot <> '');
  actNewFile.Enabled := FRoot <> '';
  actRefresh.Enabled := FRoot <> '';
  actRefreshView.Enabled := FPages.PageCount > 0;
  if (d <> nil) and (d.Mode = vmEdit) then
    actToggleMode.Caption := '&View'
  else
    actToggleMode.Caption := '&Edit';
  actDocsOnly.Checked := FDocsOnly;
  actWordWrap.Checked := FWordWrap;
  // wrap is an editor setting; the formatted view always wraps its text
  actWordWrap.Enabled := (d = nil) or (d.Mode <> vmView);

  if d = nil then
  begin
    if not FInSearch then
      FStatus.Panels[0].Text := FRoot;
    FStatus.Panels[1].Text := '';
    FStatus.Panels[2].Text := '';
    FStatus.Panels[3].Text := '';
    Exit;
  end;
  FStatus.Panels[0].Text := RelPath(d.FileName);
  if d.Mode = vmView then
  begin
    FStatus.Panels[1].Text := 'View';
    FStatus.Panels[2].Text := '';
  end
  else
  begin
    FStatus.Panels[1].Text := 'Edit';
    FStatus.Panels[2].Text := Format('Ln %d, Col %d', [d.Editor.CaretY, d.Editor.CaretX]);
  end;
  case d.Encoding of
    feUTF8BOM: enc := 'UTF-8 BOM';
    feUTF16LE: enc := 'UTF-16 LE';
    feAnsi: enc := 'Windows-1252';
  else
    enc := 'UTF-8';
  end;
  if d.LineBreak = #10 then
    enc := enc + '  LF'
  else
    enc := enc + '  CRLF';
  FStatus.Panels[3].Text := enc;
end;

procedure TfrmMain.CheckDiskChanges;
var
  i: Integer;
  d: TDocSheet;
  stamp, size: Int64;
begin
  for i := FPages.PageCount - 1 downto 0 do
  begin
    d := TDocSheet(FPages.Pages[i]);
    if not GetFileStamp(d.FileName, stamp, size) then
    begin
      if not d.Missing then
      begin
        d.Missing := True;
        UpdateCaption(d);
      end;
      Continue;
    end;
    if (stamp = d.DiskStamp) and (size = d.DiskSize) and not d.Missing then
      Continue;
    if not d.Editor.Modified then
      LoadDoc(d, True)
    else
    begin
      // remember the new stamp first so we ask only once per change
      d.DiskStamp := stamp;
      d.DiskSize := size;
      d.Missing := False;
      UpdateCaption(d);
      FPages.ActivePage := d;
      if MessageDlg(AppTitle, ExtractFileName(d.FileName) +
        ' was changed outside this app, and you have unsaved changes here.' + LineEnding + LineEnding +
        'Reload it from disk and lose your changes?', mtWarning, [mbYes, mbNo], 0) = mrYes then
        LoadDoc(d, True);
    end;
  end;
end;

procedure TfrmMain.EditorChange(Sender: TObject);
var
  d: TDocSheet;
begin
  d := TDocSheet(TSynEdit(Sender).Parent);
  d.ViewDirty := True;
  UpdateCaption(d);
end;

procedure TfrmMain.EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
var
  d: TDocSheet;
begin
  d := TDocSheet(TSynEdit(Sender).Parent);
  if d = ActiveDoc then
  begin
    FStatus.Panels[2].Text := Format('Ln %d, Col %d', [d.Editor.CaretY, d.Editor.CaretX]);
    if scModified in Changes then
      UpdateCaption(d);
  end;
end;

procedure TfrmMain.ViewerHotChange(Sender: TObject);
var
  url: string;
begin
  url := TIpHtmlPanel(Sender).HotURL;
  if url <> '' then
    FStatus.Panels[0].Text := url
  else if ActiveDoc <> nil then
    FStatus.Panels[0].Text := RelPath(ActiveDoc.FileName);
end;

procedure TfrmMain.ViewerHotClick(Sender: TObject);
var
  p: TIpHtmlPanel;
begin
  p := TIpHtmlPanel(Sender);
  HandleLink(TDocSheet(p.Parent), p.HotURL);
end;

procedure TfrmMain.HandleLink(ADoc: TDocSheet; const AUrl: string);
var
  url, anchor, target: string;
  k: Integer;
  d: TDocSheet;
begin
  url := Trim(AUrl);
  if url = '' then
    Exit;
  if url[1] = '#' then
  begin
    ADoc.Viewer.MakeAnchorVisible(Copy(url, 2, MaxInt));
    Exit;
  end;
  if (Pos('://', url) > 0) and (Pos('file://', LowerCase(url)) <> 1) or
     (Pos('mailto:', LowerCase(url)) = 1) then
  begin
    OpenURL(url);
    Exit;
  end;
  if Pos('file:///', LowerCase(url)) = 1 then
    url := Copy(url, 9, MaxInt)
  else if Pos('file://', LowerCase(url)) = 1 then
    url := Copy(url, 8, MaxInt);
  anchor := '';
  k := Pos('#', url);
  if k > 0 then
  begin
    anchor := Copy(url, k + 1, MaxInt);
    url := Copy(url, 1, k - 1);
  end;
  url := StringReplace(PercentDecode(url), '/', PathDelim, [rfReplaceAll]);
  if (Length(url) > 1) and ((url[2] = ':') or (Copy(url, 1, 2) = '\\')) then
    target := url
  else
    target := ExpandFileNameUTF8(ExtractFilePath(ADoc.FileName) + url);
  // ":12" style line suffix (file.md:12) - drop it if the file has none
  if not FileExistsUTF8(target) and not DirectoryExistsUTF8(target) then
  begin
    k := LastDelimiter(':', target);
    if (k > 2) and FileExistsUTF8(Copy(target, 1, k - 1)) then
      target := Copy(target, 1, k - 1);
  end;
  if DirectoryExistsUTF8(target) then
  begin
    SelectInTree(target);
    FTree.SetFocus;
  end
  else if FileExistsUTF8(target) then
  begin
    d := OpenFile(target);
    if (d <> nil) and (anchor <> '') and (d.Viewer <> nil) then
    begin
      if d.Mode = vmView then
        d.Viewer.MakeAnchorVisible(anchor)
      else
        d.PendingAnchor := anchor;
    end;
  end
  else
    MessageDlg(AppTitle, 'Link target not found:' + LineEnding + target, mtInformation, [mbOK], 0);
end;

procedure TfrmMain.PagesChange(Sender: TObject);
var
  d: TDocSheet;
begin
  // a tab marked for redraw while hidden is drawn when it is shown
  d := ActiveDoc;
  if (d <> nil) and (d.Mode = vmView) and d.ViewDirty then
    RenderDoc(d, True);
  UpdateUI;
end;

procedure TfrmMain.RefreshViews;
var
  i: Integer;
  d: TDocSheet;
begin
  for i := 0 to FPages.PageCount - 1 do
  begin
    d := TDocSheet(FPages.Pages[i]);
    if d.Viewer = nil then
      Continue;
    d.ViewDirty := True;
    if (d = ActiveDoc) and (d.Mode = vmView) then
      RenderDoc(d, True);
  end;
  // the editors repaint themselves; just make sure the window is redrawn
  Invalidate;
end;

procedure TfrmMain.DoRefreshView(Sender: TObject);
begin
  RefreshViews;
end;

procedure TfrmMain.FormBoundsChanged(Sender: TObject);
begin
  // moving to another screen can change the scaling; redraw once the
  // window has settled there
  if (FMonitorTimer = nil) or (Monitor = nil) then
    Exit;
  if FLastMonitor = nil then
    FLastMonitor := Monitor
  else if Monitor <> FLastMonitor then
  begin
    FLastMonitor := Monitor;
    FMonitorTimer.Enabled := False;
    FMonitorTimer.Enabled := True;
  end;
end;

procedure TfrmMain.MonitorTimer(Sender: TObject);
begin
  FMonitorTimer.Enabled := False;
  RefreshViews;
end;

procedure TfrmMain.PagesMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
begin
  if Button = mbMiddle then
  begin
    idx := FPages.IndexOfTabAt(X, Y);
    if (idx >= 0) and (idx < FPages.PageCount) then
      CloseDoc(TDocSheet(FPages.Pages[idx]));
  end;
end;

procedure TfrmMain.PagesContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  idx: Integer;
begin
  idx := FPages.IndexOfTabAt(MousePos.X, MousePos.Y);
  if idx < 0 then
    Exit;   // not on a tab: let the page content handle it
  FPages.ActivePageIndex := idx;
  UpdateUI;
  MousePos := FPages.ClientToScreen(MousePos);
  FTabMenu.PopUp(MousePos.X, MousePos.Y);
  Handled := True;
end;

procedure TfrmMain.TimerTick(Sender: TObject);
var
  sig: string;
begin
  if not Application.Active then
    Exit;
  if FPages.PageCount > 0 then
    CheckDiskChanges;
  Inc(FTick);
  if (FTick mod 2 = 0) and (FRoot <> '') and not FInSearch then
  begin
    sig := ComputeTreeSig;
    if sig <> FTreeSig then
      RefreshTree;
  end;
end;

procedure TfrmMain.AppActivate(Sender: TObject);
begin
  // catch up straight away when the user comes back to the app
  FTick := 1;
  TimerTick(nil);
end;

{ ---------- actions ---------- }

procedure TfrmMain.DoOpenFolder(Sender: TObject);
var
  dlg: TSelectDirectoryDialog;
begin
  dlg := TSelectDirectoryDialog.Create(Self);
  try
    dlg.Title := 'Open Folder';
    if FRoot <> '' then
      dlg.InitialDir := FRoot;
    dlg.Options := dlg.Options + [ofPathMustExist];
    if dlg.Execute then
      OpenFolder(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.DoRefresh(Sender: TObject);
var
  i: Integer;
begin
  RefreshTree;
  for i := 0 to FPages.PageCount - 1 do
    if not TDocSheet(FPages.Pages[i]).Editor.Modified then
      LoadDoc(TDocSheet(FPages.Pages[i]), True);
end;

procedure TfrmMain.DoSave(Sender: TObject);
begin
  if ActiveDoc <> nil then
    SaveDoc(ActiveDoc);
end;

procedure TfrmMain.DoSaveAll(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to FPages.PageCount - 1 do
    if TDocSheet(FPages.Pages[i]).Editor.Modified then
      SaveDoc(TDocSheet(FPages.Pages[i]));
end;

procedure TfrmMain.DoCloseTab(Sender: TObject);
begin
  CloseDoc(ActiveDoc);
end;

procedure TfrmMain.DoCloseAll(Sender: TObject);
begin
  CloseAllDocs;
  UpdateUI;
end;

procedure TfrmMain.DoCloseOthers(Sender: TObject);
begin
  CloseAllDocs(ActiveDoc);
  UpdateUI;
end;

procedure TfrmMain.DoToggleMode(Sender: TObject);
var
  d: TDocSheet;
begin
  d := ActiveDoc;
  if (d = nil) or not d.CanView then
    Exit;
  if d.Mode = vmView then
    SetDocMode(d, vmEdit)
  else
    SetDocMode(d, vmView);
end;

procedure TfrmMain.DoDocsOnly(Sender: TObject);
begin
  FDocsOnly := not FDocsOnly;
  actDocsOnly.Checked := FDocsOnly;
  if FInSearch then
    FillSearchResults(FFilterEdit.Text)
  else
    RefreshTree;
end;

procedure TfrmMain.DoWordWrap(Sender: TObject);
var
  i: Integer;
begin
  FWordWrap := not FWordWrap;
  actWordWrap.Checked := FWordWrap;
  for i := 0 to FPages.PageCount - 1 do
    ApplyWrap(TDocSheet(FPages.Pages[i]));
end;

procedure TfrmMain.DoLineBreaks(Sender: TObject);
begin
  FLineBreaks := not FLineBreaks;
  actLineBreaks.Checked := FLineBreaks;
  RefreshViews;
end;

procedure TfrmMain.DoZoomIn(Sender: TObject);
begin
  if FZoom < 32 then
    Inc(FZoom);
  ApplyZoom;
end;

procedure TfrmMain.DoZoomOut(Sender: TObject);
begin
  if FZoom > 6 then
    Dec(FZoom);
  ApplyZoom;
end;

procedure TfrmMain.DoZoomReset(Sender: TObject);
begin
  FZoom := 10;
  ApplyZoom;
end;

procedure TfrmMain.DoNextTab(Sender: TObject);
begin
  if FPages.PageCount > 1 then
    FPages.ActivePageIndex := (FPages.ActivePageIndex + 1) mod FPages.PageCount;
  UpdateUI;
end;

procedure TfrmMain.DoPrevTab(Sender: TObject);
begin
  if FPages.PageCount > 1 then
    FPages.ActivePageIndex := (FPages.ActivePageIndex + FPages.PageCount - 1) mod FPages.PageCount;
  UpdateUI;
end;

procedure TfrmMain.DoCopy(Sender: TObject);
var
  d: TDocSheet;
begin
  if ActiveControl is TCustomEdit then
    TCustomEdit(ActiveControl).CopyToClipboard
  else if ActiveControl is TCustomSynEdit then
    TCustomSynEdit(ActiveControl).CopyToClipboard
  else if ActiveControl = FTree then
  begin
    if FTree.Selected <> nil then
      Clipboard.AsText := NodePath(FTree.Selected);
  end
  else
  begin
    d := ActiveDoc;
    if d = nil then
      Exit;
    if (d.Mode = vmView) and (d.Viewer <> nil) then
      d.Viewer.CopyToClipboard
    else
      d.Editor.CopyToClipboard;
  end;
end;

procedure TfrmMain.DoFind(Sender: TObject);
var
  d: TDocSheet;
  s: string;
begin
  d := ActiveDoc;
  if d = nil then
  begin
    FFilterEdit.SetFocus;
    Exit;
  end;
  s := FFindText;
  if d.Editor.SelAvail and (Pos(#10, d.Editor.SelText) = 0) then
    s := d.Editor.SelText;
  if not InputQuery('Find', 'Find text in ' + ExtractFileName(d.FileName) +
    ' (F3 finds the next one):', s) then
    Exit;
  if s = '' then
    Exit;
  FFindText := s;
  DoFindNext(nil);
end;

procedure TfrmMain.DoFindNext(Sender: TObject);
var
  d: TDocSheet;
  s, line: string;
  startY, startX, y, x, i: Integer;
  found: Boolean;
begin
  d := ActiveDoc;
  s := FFindText;
  if (d = nil) or (d.Editor.Lines.Count = 0) then
    Exit;
  if s = '' then
  begin
    DoFind(nil);
    Exit;
  end;
  // search from the caret forward, wrapping around once.
  // The formatted view has no search, so switch to the editor to show the hit.
  if d.Mode = vmView then
    SetDocMode(d, vmEdit);
  startY := d.Editor.CaretY;
  startX := d.Editor.LogicalCaretXY.X;
  if d.Editor.SelAvail then
    startX := d.Editor.BlockEnd.X;
  found := False;
  for i := 0 to d.Editor.Lines.Count do
  begin
    y := ((startY - 1 + i) mod d.Editor.Lines.Count) + 1;
    line := UTF8LowerCase(d.Editor.Lines[y - 1]);
    if i = 0 then
      x := Pos(UTF8LowerCase(s), Copy(line, startX, MaxInt))
    else
      x := Pos(UTF8LowerCase(s), line);
    if x > 0 then
    begin
      if i = 0 then
        x := x + startX - 1;
      d.Editor.BlockBegin := Point(x, y);
      d.Editor.BlockEnd := Point(x + Length(s), y);
      d.Editor.LogicalCaretXY := Point(x + Length(s), y);
      d.Editor.EnsureCursorPosVisible;
      found := True;
      Break;
    end;
  end;
  if not found then
    MessageDlg(AppTitle, '"' + s + '" was not found.', mtInformation, [mbOK], 0);
end;

procedure TfrmMain.DoExitApp(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.DoNewFile(Sender: TObject);
var
  dir, newName, full: string;
  n: TTreeNode;
begin
  if FRoot = '' then
    Exit;
  dir := FRoot;
  n := FTree.Selected;
  if (n <> nil) and (n.Data <> nil) then
  begin
    if TNodeInfo(n.Data).IsDir then
      dir := TNodeInfo(n.Data).Path
    else
      dir := ExtractFileDir(TNodeInfo(n.Data).Path);
  end;
  newName := 'New document.md';
  if not InputQuery('New Markdown File', 'File name (in ' + RelPath(dir) + '):', newName) then
    Exit;
  newName := Trim(newName);
  if newName = '' then
    Exit;
  if ExtractFileExt(newName) = '' then
    newName := newName + '.md';
  full := AppendPathDelim(dir) + newName;
  if FileExistsUTF8(full) then
  begin
    MessageDlg(AppTitle, 'That file already exists.', mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    WriteAllBytes(full, '# ' + ChangeFileExt(newName, '') + #13#10#13#10);
  except
    on E: Exception do
    begin
      MessageDlg(AppTitle, 'Could not create the file:' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshTree;
  SelectInTree(full);
  OpenFile(full, Ord(vmEdit));
end;

procedure TfrmMain.DoRevealInTree(Sender: TObject);
begin
  if ActiveDoc <> nil then
  begin
    SelectInTree(ActiveDoc.FileName);
    FTree.SetFocus;
  end;
end;

procedure TfrmMain.DoShortcuts(Sender: TObject);
begin
  MessageDlg('Keyboard Shortcuts',
    'Ctrl+O' + #9 + 'Open folder' + LineEnding +
    'F5' + #9 + 'Refresh tree and unchanged files' + LineEnding +
    'Ctrl+R' + #9 + 'Refresh View: redraw the open documents' + LineEnding +
    'Ctrl+E' + #9 + 'Switch Markdown between View and Edit' + LineEnding +
    'Ctrl+S' + #9 + 'Save  (Ctrl+Shift+S saves all)' + LineEnding +
    'Ctrl+N' + #9 + 'New Markdown file' + LineEnding +
    'Ctrl+W' + #9 + 'Close tab  (Ctrl+Shift+W closes all; middle-click a tab closes it)' + LineEnding +
    'Ctrl+Tab' + #9 + 'Next tab  (Ctrl+Shift+Tab previous)' + LineEnding +
    'Ctrl+F' + #9 + 'Find in the file  (F3 next)' + LineEnding +
    'Ctrl+Shift+E' + #9 + 'Show the open file in the tree' + LineEnding +
    'Ctrl+Shift+D' + #9 + 'Documents only (.md .txt .pdf)' + LineEnding +
    'Alt+Z' + #9 + 'Word wrap in the editor' + LineEnding +
    'Ctrl+ +/-/0' + #9 + 'Zoom in / out / reset' + LineEnding + LineEnding +
    'Files changed on disk reload by themselves. New files show up in the tree within a few seconds.',
    mtInformation, [mbOK], 0);
end;

procedure TfrmMain.DoTreeOpen(Sender: TObject);
var
  n: TTreeNode;
begin
  n := FTree.Selected;
  if (n = nil) or (n.Data = nil) then
    Exit;
  if TNodeInfo(n.Data).IsDir then
    n.Expanded := True
  else
    OpenFile(TNodeInfo(n.Data).Path);
end;

procedure TfrmMain.DoTreeOpenExternal(Sender: TObject);
begin
  if FTree.Selected <> nil then
    OpenDocument(NodePath(FTree.Selected));
end;

procedure TfrmMain.DoTreeReveal(Sender: TObject);
begin
  if FTree.Selected <> nil then
    RevealInExplorer(NodePath(FTree.Selected));
end;

procedure TfrmMain.DoTreeCopyPath(Sender: TObject);
begin
  if FTree.Selected <> nil then
    Clipboard.AsText := NodePath(FTree.Selected);
end;

procedure TfrmMain.DoTreeCopyRelPath(Sender: TObject);
begin
  if FTree.Selected <> nil then
    Clipboard.AsText := RelPath(NodePath(FTree.Selected));
end;

procedure TfrmMain.DoTabCopyPath(Sender: TObject);
begin
  if ActiveDoc <> nil then
    Clipboard.AsText := ActiveDoc.FileName;
end;

procedure TfrmMain.DoTabReveal(Sender: TObject);
begin
  if ActiveDoc <> nil then
    RevealInExplorer(ActiveDoc.FileName);
end;

procedure TfrmMain.DoTabOpenExternal(Sender: TObject);
begin
  if ActiveDoc <> nil then
    OpenDocument(ActiveDoc.FileName);
end;

procedure TfrmMain.DoViewerSelectAll(Sender: TObject);
begin
  if (ActiveDoc <> nil) and (ActiveDoc.Viewer <> nil) then
    ActiveDoc.Viewer.SelectAll;
end;

end.
