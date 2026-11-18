unit uSynMarkdown;

{ A light Markdown highlighter for SynEdit: headings, code fences and
  inline code, quotes, list markers, bold/italic, links and table pipes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditTypes;

type
  TMdTokenKind = (mtkText, mtkHeading, mtkCode, mtkFence, mtkQuote, mtkList,
    mtkBold, mtkItalic, mtkLink, mtkRule, mtkTable, mtkSpace);

  TSynMarkdownSyn = class(TSynCustomHighlighter)
  private
    FText: string;
    FPos: Integer;        // 1-based position of the next char
    FTokStart: Integer;   // 1-based
    FTokKind: TMdTokenKind;
    FEol: Boolean;
    FInFence: Boolean;    // state at the start of the current line
    FNextInFence: Boolean;
    FLineKind: TMdTokenKind;  // whole-line kind, or mtkText for token scanning
    FListEnd: Integer;
    FHeadingAttri, FCodeAttri, FFenceAttri, FQuoteAttri, FListAttri,
    FBoldAttri, FItalicAttri, FLinkAttri, FRuleAttri, FTableAttri,
    FTextAttri: TSynHighlighterAttributes;
    function MakeAttr(const AName: string; AFore: TColor; AStyle: TFontStyles;
      ABack: TColor = clNone): TSynHighlighterAttributes;
  protected
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;
  public
    constructor Create(AOwner: TComponent); override;
    class function GetLanguageName: string; override;
    procedure SetLine(const NewValue: string; LineNumber: Integer); override;
    procedure Next; override;
    function GetEol: Boolean; override;
    function GetToken: string; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: Integer); override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;
    function GetRange: Pointer; override;
    procedure SetRange(Value: Pointer); override;
    procedure ResetRange; override;
  end;

implementation

function IsFenceLine(const T: string): Boolean;
begin
  Result := (Length(T) >= 3) and (((T[1] = '`') and (T[2] = '`') and (T[3] = '`')) or
    ((T[1] = '~') and (T[2] = '~') and (T[3] = '~')));
end;

function IsRuleLine(const T: string): Boolean;
var
  i, n: Integer;
  ch: Char;
begin
  Result := False;
  if (Length(T) < 3) or not (T[1] in ['-', '*', '_']) then
    Exit;
  ch := T[1];
  n := 0;
  for i := 1 to Length(T) do
    if T[i] = ch then
      Inc(n)
    else if T[i] <> ' ' then
      Exit;
  Result := n >= 3;
end;

constructor TSynMarkdownSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTextAttri := MakeAttr('Text', clNone, []);
  FHeadingAttri := MakeAttr('Heading', $00A05000, [fsBold]);
  FCodeAttri := MakeAttr('Code', $00123A9A, [], $00F6F4F3);
  FFenceAttri := MakeAttr('Fence', $00988F8A, [], $00F6F4F3);
  FQuoteAttri := MakeAttr('Quote', $006A6057, [fsItalic]);
  FListAttri := MakeAttr('ListMarker', $000060D0, [fsBold]);
  FBoldAttri := MakeAttr('Bold', clNone, [fsBold]);
  FItalicAttri := MakeAttr('Italic', clNone, [fsItalic]);
  FLinkAttri := MakeAttr('Link', $00C06000, [fsUnderline]);
  FRuleAttri := MakeAttr('Rule', $00A0A0A0, []);
  FTableAttri := MakeAttr('TablePipe', $00A0A0A0, [fsBold]);
  SetAttributesOnChange(@DefHighlightChange);
  fDefaultFilter := 'Markdown files (*.md)|*.md;*.markdown';
end;

function TSynMarkdownSyn.MakeAttr(const AName: string; AFore: TColor;
  AStyle: TFontStyles; ABack: TColor): TSynHighlighterAttributes;
begin
  Result := TSynHighlighterAttributes.Create(AName, AName);
  Result.Foreground := AFore;
  Result.Background := ABack;
  Result.Style := AStyle;
  AddAttribute(Result);
end;

class function TSynMarkdownSyn.GetLanguageName: string;
begin
  Result := 'Markdown';
end;

function TSynMarkdownSyn.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT: Result := FQuoteAttri;
    SYN_ATTR_IDENTIFIER: Result := FTextAttri;
    SYN_ATTR_KEYWORD: Result := FHeadingAttri;
    SYN_ATTR_STRING: Result := FCodeAttri;
    SYN_ATTR_WHITESPACE: Result := FTextAttri;
  else
    Result := nil;
  end;
end;

procedure TSynMarkdownSyn.SetLine(const NewValue: string; LineNumber: Integer);
var
  t: string;
  p: Integer;
begin
  inherited SetLine(NewValue, LineNumber);
  // SynEdit calls SetLine for the following line without SetRange
  // (ContinueNextLine), so carry the state on from the previous line.
  FInFence := FNextInFence;
  FText := NewValue;
  FPos := 1;
  FEol := False;
  FListEnd := 0;
  FNextInFence := FInFence;
  t := Trim(FText);
  if IsFenceLine(t) then
  begin
    FLineKind := mtkFence;
    FNextInFence := not FInFence;
  end
  else if FInFence then
    FLineKind := mtkCode
  else if (t <> '') and (t[1] = '#') then
    FLineKind := mtkHeading
  else if (t <> '') and (t[1] = '>') then
    FLineKind := mtkQuote
  else if IsRuleLine(t) then
    FLineKind := mtkRule
  else
  begin
    FLineKind := mtkText;
    // list marker at line start
    p := 1;
    while (p <= Length(FText)) and (FText[p] = ' ') do
      Inc(p);
    if (p < Length(FText)) and (FText[p] in ['-', '*', '+']) and (FText[p + 1] = ' ') then
      FListEnd := p
    else if (p <= Length(FText)) and (FText[p] in ['0'..'9']) then
    begin
      while (p <= Length(FText)) and (FText[p] in ['0'..'9']) do
        Inc(p);
      if (p < Length(FText)) and (FText[p] in ['.', ')']) and (FText[p + 1] = ' ') then
        FListEnd := p;
    end;
  end;
  Next;
end;

procedure TSynMarkdownSyn.Next;
var
  n, k: Integer;
  c: Char;
begin
  FTokStart := FPos;
  if FPos > Length(FText) then
  begin
    FEol := True;
    Exit;
  end;

  if FLineKind <> mtkText then
  begin
    FTokKind := FLineKind;
    FPos := Length(FText) + 1;
    Exit;
  end;

  c := FText[FPos];

  // leading spaces + list marker
  if (FListEnd > 0) and (FPos <= FListEnd) then
  begin
    while (FPos <= Length(FText)) and (FText[FPos] = ' ') do
      Inc(FPos);
    if FPos > FTokStart then
    begin
      FTokKind := mtkSpace;
      Exit;
    end;
    FPos := FListEnd + 1;
    FTokKind := mtkList;
    // task box [ ] / [x]
    if (FPos + 3 <= Length(FText)) and (FText[FPos + 1] = '[') and (FText[FPos + 3] = ']') then
      FPos := FPos + 4;
    Exit;
  end;

  case c of
    '`':
      begin
        n := 0;
        while (FPos + n <= Length(FText)) and (FText[FPos + n] = '`') do
          Inc(n);
        k := Pos(StringOfChar('`', n), Copy(FText, FPos + n, MaxInt));
        if k > 0 then
          FPos := FPos + n + k - 1 + n
        else
          FPos := FPos + n;
        FTokKind := mtkCode;
      end;
    '*', '_':
      begin
        n := 0;
        while (FPos + n <= Length(FText)) and (FText[FPos + n] = c) do
          Inc(n);
        if (n >= 2) then
        begin
          k := Pos(StringOfChar(c, 2), Copy(FText, FPos + n, MaxInt));
          if k > 0 then
          begin
            FPos := FPos + n + k - 1 + 2;
            FTokKind := mtkBold;
            Exit;
          end;
        end
        else if (FPos + 1 <= Length(FText)) and (FText[FPos + 1] <> ' ') and
          not ((c = '_') and (FPos > 1) and (FText[FPos - 1] in ['0'..'9', 'A'..'Z', 'a'..'z'])) then
        begin
          k := Pos(c, Copy(FText, FPos + 1, MaxInt));
          if k > 1 then
          begin
            FPos := FPos + 1 + k;
            FTokKind := mtkItalic;
            Exit;
          end;
        end;
        FPos := FPos + n;
        FTokKind := mtkText;
      end;
    '[':
      begin
        k := Pos(']', Copy(FText, FPos + 1, MaxInt));
        if k > 0 then
        begin
          FPos := FPos + k + 1;
          if (FPos <= Length(FText)) and (FText[FPos] = '(') then
          begin
            k := Pos(')', Copy(FText, FPos, MaxInt));
            if k > 0 then
              FPos := FPos + k;
          end;
          FTokKind := mtkLink;
        end
        else
        begin
          Inc(FPos);
          FTokKind := mtkText;
        end;
      end;
    '|':
      begin
        Inc(FPos);
        FTokKind := mtkTable;
      end;
  else
    begin
      while (FPos <= Length(FText)) and not (FText[FPos] in ['`', '*', '_', '[', '|']) do
        Inc(FPos);
      if FPos = FTokStart then
        Inc(FPos);
      FTokKind := mtkText;
    end;
  end;
end;

function TSynMarkdownSyn.GetEol: Boolean;
begin
  Result := FEol;
end;

function TSynMarkdownSyn.GetToken: string;
begin
  Result := Copy(FText, FTokStart, FPos - FTokStart);
end;

procedure TSynMarkdownSyn.GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
begin
  TokenLength := FPos - FTokStart;
  if TokenLength > 0 then
    TokenStart := @FText[FTokStart]
  else
    TokenStart := nil;
end;

function TSynMarkdownSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case FTokKind of
    mtkHeading: Result := FHeadingAttri;
    mtkCode: Result := FCodeAttri;
    mtkFence: Result := FFenceAttri;
    mtkQuote: Result := FQuoteAttri;
    mtkList: Result := FListAttri;
    mtkBold: Result := FBoldAttri;
    mtkItalic: Result := FItalicAttri;
    mtkLink: Result := FLinkAttri;
    mtkRule: Result := FRuleAttri;
    mtkTable: Result := FTableAttri;
  else
    Result := FTextAttri;
  end;
end;

function TSynMarkdownSyn.GetTokenKind: Integer;
begin
  Result := Ord(FTokKind);
end;

function TSynMarkdownSyn.GetTokenPos: Integer;
begin
  Result := FTokStart - 1;
end;

function TSynMarkdownSyn.GetRange: Pointer;
begin
  Result := Pointer(PtrUInt(Ord(FNextInFence)));
end;

procedure TSynMarkdownSyn.SetRange(Value: Pointer);
begin
  FInFence := PtrUInt(Value) <> 0;
  FNextInFence := FInFence;
end;

procedure TSynMarkdownSyn.ResetRange;
begin
  FInFence := False;
  FNextInFence := False;
end;

end.
