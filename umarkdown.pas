unit uMarkdown;

{ Small Markdown (CommonMark / GitHub flavour subset) to HTML converter.
  The HTML is kept simple so the TurboPower IPro viewer can show it:
  headings, paragraphs, bold/italic/strike, inline code, fenced and
  indented code blocks, block quotes, nested bullet / numbered / task
  lists, pipe tables, horizontal rules, links, reference links, autolinks. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function MarkdownToHtml(const ASource: string; AFontSize: Integer = 10): string;
function HtmlEscape(const S: string): string;
function MakeSlug(const S: string): string;

implementation

const
  HardBreak = #11;   // marker for a hard line break inside a paragraph

type
  TMdRenderer = class
  private
    FRefs: TStringList;   // reference link definitions: name=url
    FSlugs: TStringList;  // slugs already used, to keep anchors unique
    function UniqueSlug(const AText: string): string;
    function RenderInline(const S: string): string;
    function RenderBlocks(ALines: TStrings; ATight: Boolean): string;
    procedure CollectRefs(ALines: TStrings);
  public
    constructor Create;
    destructor Destroy; override;
    function Render(const ASource: string): string;
  end;

{ ---------- helpers ---------- }

function HtmlEscape(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      HardBreak: Result := Result + '<br>';
    else
      Result := Result + c;
    end;
  end;
end;

function IsSpaceChar(c: Char): Boolean; inline;
begin
  Result := c in [' ', #9, #10, #13, HardBreak];
end;

function IsPunct(c: Char): Boolean; inline;
begin
  Result := c in ['!'..'/', ':'..'@', '['..'`', '{'..'~'];
end;

function IsAlnum(c: Char): Boolean; inline;
begin
  Result := (c in ['0'..'9', 'A'..'Z', 'a'..'z']) or (Ord(c) >= 128);
end;

function LeadingSpaces(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] = ' ') do
    Inc(Result);
end;

function ExpandTabs(const S: string): string;
var
  i, col: Integer;
begin
  if Pos(#9, S) = 0 then
    Exit(S);
  Result := '';
  col := 0;
  for i := 1 to Length(S) do
    if S[i] = #9 then
    begin
      repeat
        Result := Result + ' ';
        Inc(col);
      until col mod 4 = 0;
    end
    else
    begin
      Result := Result + S[i];
      // count UTF-8 lead bytes only, so the column is per character
      if (Ord(S[i]) and $C0) <> $80 then
        Inc(col);
    end;
end;

function StripSpaces(const S: string; N: Integer): string;
var
  k: Integer;
begin
  k := LeadingSpaces(S);
  if k > N then
    k := N;
  Result := Copy(S, k + 1, MaxInt);
end;

function MakeSlug(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z'] then
      Result := Result + Chr(Ord(c) + 32)
    else if (c in ['a'..'z', '0'..'9', '_', '-']) or (Ord(c) >= 128) then
      Result := Result + c
    else if c = ' ' then
      Result := Result + '-';
  end;
end;

function IsHorizontalRule(const T: string): Boolean;
var
  i, n: Integer;
  ch: Char;
begin
  Result := False;
  if Length(T) < 3 then
    Exit;
  ch := T[1];
  if not (ch in ['-', '*', '_']) then
    Exit;
  n := 0;
  for i := 1 to Length(T) do
    if T[i] = ch then
      Inc(n)
    else if T[i] <> ' ' then
      Exit;
  Result := n >= 3;
end;

function IsFence(const T: string; out AChar: Char; out ALen: Integer): Boolean;
begin
  Result := False;
  ALen := 0;
  if (Length(T) < 3) or not (T[1] in ['`', '~']) then
    Exit;
  AChar := T[1];
  while (ALen < Length(T)) and (T[ALen + 1] = AChar) do
    Inc(ALen);
  Result := ALen >= 3;
  // a backtick fence may not contain backticks in its info string
  if Result and (AChar = '`') and (Pos('`', Copy(T, ALen + 1, MaxInt)) > 0) then
    Result := False;
end;

function HeadingLevel(const T: string): Integer;
begin
  Result := 0;
  while (Result < Length(T)) and (T[Result + 1] = '#') do
    Inc(Result);
  if (Result = 0) or (Result > 6) then
    Exit(0);
  if (Length(T) > Result) and (T[Result + 1] <> ' ') then
    Result := 0;
end;

{ List item: returns True and fills in the details when the line starts a
  list item. AContent is the column (0-based, in spaces) where content starts. }
function ParseListItem(const S: string; out AOrdered: Boolean;
  out AMarker: Char; out AStart: Integer; out AContent: Integer;
  out AText: string): Boolean;
var
  ind, p, numLen, sp: Integer;
begin
  Result := False;
  AOrdered := False;
  AMarker := #0;
  AStart := 1;
  AContent := 0;
  AText := '';
  ind := LeadingSpaces(S);
  p := ind + 1;
  if p > Length(S) then
    Exit;
  if S[p] in ['-', '*', '+'] then
  begin
    AMarker := S[p];
    Inc(p);
  end
  else if S[p] in ['0'..'9'] then
  begin
    numLen := 0;
    while (p + numLen <= Length(S)) and (S[p + numLen] in ['0'..'9']) and (numLen < 9) do
      Inc(numLen);
    if (p + numLen > Length(S)) or not (S[p + numLen] in ['.', ')']) then
      Exit;
    AStart := StrToIntDef(Copy(S, p, numLen), 1);
    AMarker := S[p + numLen];
    AOrdered := True;
    Inc(p, numLen + 1);
  end
  else
    Exit;
  // marker must be followed by a space or end of line
  if p <= Length(S) then
  begin
    if S[p] <> ' ' then
      Exit;
    sp := 0;
    while (p + sp <= Length(S)) and (S[p + sp] = ' ') do
      Inc(sp);
    if p + sp > Length(S) then
      sp := 1                       // blank item
    else if sp > 4 then
      sp := 1;                      // content is indented code: keep one space
    AContent := (p - 1) + sp;
    AText := Copy(S, AContent + 1, MaxInt);
  end
  else
  begin
    AContent := p;                  // "-" alone on a line
    AText := '';
  end;
  Result := True;
end;

function IsTableDelimiterRow(const T: string): Boolean;
var
  i: Integer;
  hasDash, hasPipe: Boolean;
begin
  Result := False;
  if T = '' then
    Exit;
  hasDash := False;
  hasPipe := False;
  for i := 1 to Length(T) do
    case T[i] of
      '-': hasDash := True;
      '|': hasPipe := True;
      ':', ' ': ;
    else
      Exit;
    end;
  Result := hasDash and hasPipe;
end;

procedure SplitTableRow(const ARow: string; ACells: TStrings);
var
  s, cell: string;
  i: Integer;
  inCode: Boolean;
begin
  ACells.Clear;
  s := Trim(ARow);
  if (s <> '') and (s[1] = '|') then
    Delete(s, 1, 1);
  if (s <> '') and (s[Length(s)] = '|') and ((Length(s) < 2) or (s[Length(s) - 1] <> '\')) then
    Delete(s, Length(s), 1);
  cell := '';
  inCode := False;
  i := 1;
  while i <= Length(s) do
  begin
    if (s[i] = '\') and (i < Length(s)) and (s[i + 1] = '|') then
    begin
      cell := cell + '|';
      Inc(i, 2);
      Continue;
    end;
    if s[i] = '`' then
      inCode := not inCode;
    if (s[i] = '|') and not inCode then
    begin
      ACells.Add(Trim(cell));
      cell := '';
    end
    else
      cell := cell + s[i];
    Inc(i);
  end;
  ACells.Add(Trim(cell));
end;

{ IPro shows <pre> text raw (entities are not decoded and a "<" would start
  a tag), so a code block is drawn as monospace lines instead: spaces become
  &nbsp; and line breaks <br>. AText is already HTML-escaped. }
function CodeBlockHtml(const AText: string): string;
var
  body: string;
begin
  body := StringReplace(AText, ' ', '&nbsp;', [rfReplaceAll]);
  body := StringReplace(body, LineEnding, '&nbsp;<br>', [rfReplaceAll]);
  Result := '<table width="100%" border="0" cellspacing="0" cellpadding="10">' +
    '<tr bgcolor="#EEF0F3"><td><tt>' + body + '&nbsp;</tt></td></tr></table>' + LineEnding;
end;

{ ---------- TMdRenderer ---------- }

constructor TMdRenderer.Create;
begin
  inherited Create;
  FRefs := TStringList.Create;
  FRefs.CaseSensitive := False;
  FSlugs := TStringList.Create;
end;

destructor TMdRenderer.Destroy;
begin
  FRefs.Free;
  FSlugs.Free;
  inherited Destroy;
end;

function TMdRenderer.UniqueSlug(const AText: string): string;
var
  base: string;
  n: Integer;
begin
  base := MakeSlug(AText);
  Result := base;
  n := 0;
  while FSlugs.IndexOf(Result) >= 0 do
  begin
    Inc(n);
    Result := base + '-' + IntToStr(n);
  end;
  FSlugs.Add(Result);
end;

procedure TMdRenderer.CollectRefs(ALines: TStrings);
var
  i, p: Integer;
  t, name, url: string;
  inFence: Boolean;
  fc: Char;
  fl: Integer;
begin
  inFence := False;
  i := 0;
  while i < ALines.Count do
  begin
    t := Trim(ALines[i]);
    if IsFence(t, fc, fl) then
      inFence := not inFence;
    if (not inFence) and (LeadingSpaces(ALines[i]) < 4) and (Length(t) > 3) and (t[1] = '[') then
    begin
      p := Pos(']:', t);
      if (p > 2) and (t[2] <> '^') then
      begin
        name := Copy(t, 2, p - 2);
        url := Trim(Copy(t, p + 2, MaxInt));
        // drop an optional title
        if Pos(' ', url) > 0 then
          url := Copy(url, 1, Pos(' ', url) - 1);
        if (url <> '') and (url[1] = '<') and (url[Length(url)] = '>') then
          url := Copy(url, 2, Length(url) - 2);
        if url <> '' then
        begin
          FRefs.Values[LowerCase(name)] := url;
          ALines.Delete(i);
          Continue;
        end;
      end;
    end;
    Inc(i);
  end;
end;

function FindClosing(const S, ADelim: string; AFrom: Integer): Integer;
{ Finds ADelim at or after AFrom that can close an emphasis run: the
  character before it is not a space. Skips code spans. }
var
  i, n, k: Integer;
begin
  Result := 0;
  i := AFrom;
  while i <= Length(S) - Length(ADelim) + 1 do
  begin
    if S[i] = '\' then
    begin
      Inc(i, 2);
      Continue;
    end;
    if S[i] = '`' then
    begin
      n := 0;
      while (i + n <= Length(S)) and (S[i + n] = '`') do
        Inc(n);
      k := Pos(StringOfChar('`', n), Copy(S, i + n, MaxInt));
      if k > 0 then
      begin
        i := i + n + k - 1 + n;
        Continue;
      end;
      Inc(i, n);
      Continue;
    end;
    if (Copy(S, i, Length(ADelim)) = ADelim) and (i > AFrom) and not IsSpaceChar(S[i - 1]) then
    begin
      // for single * or _ do not match part of a double run
      if (Length(ADelim) = 1) and (i < Length(S)) and (S[i + 1] = ADelim[1]) then
      begin
        // skip the whole run
        n := 0;
        while (i + n <= Length(S)) and (S[i + n] = ADelim[1]) do
          Inc(n);
        if n = 3 then
          Exit(i + 2);   // ***x*** style: the last one closes the single
        Inc(i, n);
        Continue;
      end;
      // underscore must not be inside a word
      if (ADelim[1] = '_') and (i + Length(ADelim) <= Length(S)) and IsAlnum(S[i + Length(ADelim)]) then
      begin
        Inc(i);
        Continue;
      end;
      Exit(i);
    end;
    Inc(i);
  end;
end;

function TMdRenderer.RenderInline(const S: string): string;
var
  i, n, k, depth, j, close: Integer;
  c: Char;
  code, text, url, rest, delim, tag, lowered: string;
  isImage: Boolean;

  function LinkHtml(const AUrl, AText: string): string;
  begin
    Result := '<a href="' + HtmlEscape(AUrl) + '">' + AText + '</a>';
  end;

begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];

    // backslash escape
    if (c = '\') and (i < Length(S)) and IsPunct(S[i + 1]) then
    begin
      Result := Result + HtmlEscape(S[i + 1]);
      Inc(i, 2);
      Continue;
    end;

    // code span
    if c = '`' then
    begin
      n := 0;
      while (i + n <= Length(S)) and (S[i + n] = '`') do
        Inc(n);
      // find a closing run of exactly n backticks
      close := 0;
      k := i + n;
      while k <= Length(S) do
      begin
        if S[k] = '`' then
        begin
          j := 0;
          while (k + j <= Length(S)) and (S[k + j] = '`') do
            Inc(j);
          if j = n then
          begin
            close := k;
            Break;
          end;
          Inc(k, j);
        end
        else
          Inc(k);
      end;
      if close > 0 then
      begin
        code := Copy(S, i + n, close - i - n);
        code := StringReplace(code, HardBreak, ' ', [rfReplaceAll]);
        if (Length(code) >= 2) and (code[1] = ' ') and (code[Length(code)] = ' ') and (Trim(code) <> '') then
          code := Copy(code, 2, Length(code) - 2);
        Result := Result + '<code>' + HtmlEscape(code) + '</code>';
        i := close + n;
        Continue;
      end;
      Result := Result + StringOfChar('`', n);
      Inc(i, n);
      Continue;
    end;

    // autolink <http://...>
    if (c = '<') then
    begin
      k := Pos('>', Copy(S, i + 1, MaxInt));
      if k > 0 then
      begin
        url := Copy(S, i + 1, k - 1);
        lowered := LowerCase(url);
        if ((Pos('http://', lowered) = 1) or (Pos('https://', lowered) = 1) or
            (Pos('mailto:', lowered) = 1)) and (Pos(' ', url) = 0) then
        begin
          Result := Result + LinkHtml(url, HtmlEscape(url));
          i := i + k + 1;
          Continue;
        end;
        if (Pos('@', url) > 1) and (Pos(' ', url) = 0) and (Pos('.', url) > 0) then
        begin
          Result := Result + LinkHtml('mailto:' + url, HtmlEscape(url));
          i := i + k + 1;
          Continue;
        end;
        // <br> and friends
        tag := LowerCase(StringReplace(url, ' ', '', [rfReplaceAll]));
        if (tag = 'br') or (tag = 'br/') then
        begin
          Result := Result + '<br>';
          i := i + k + 1;
          Continue;
        end;
        if (tag = 'b') or (tag = '/b') or (tag = 'i') or (tag = '/i') or
           (tag = 'u') or (tag = '/u') or (tag = 'sub') or (tag = '/sub') or
           (tag = 'sup') or (tag = '/sup') or (tag = 'kbd') or (tag = '/kbd') then
        begin
          if tag = 'kbd' then tag := 'code';
          if tag = '/kbd' then tag := '/code';
          Result := Result + '<' + tag + '>';
          i := i + k + 1;
          Continue;
        end;
        // skip html comments
        if Copy(S, i, 4) = '<!--' then
        begin
          k := Pos('-->', Copy(S, i + 4, MaxInt));
          if k > 0 then
          begin
            i := i + 4 + k + 2;
            Continue;
          end;
        end;
      end;
    end;

    // links and images
    isImage := (c = '!') and (i < Length(S)) and (S[i + 1] = '[');
    if (c = '[') or isImage then
    begin
      j := i;
      if isImage then
        Inc(j);
      // find matching ]
      depth := 0;
      k := j;
      close := 0;
      while k <= Length(S) do
      begin
        if (S[k] = '\') then
        begin
          Inc(k, 2);
          Continue;
        end;
        if S[k] = '[' then
          Inc(depth)
        else if S[k] = ']' then
        begin
          Dec(depth);
          if depth = 0 then
          begin
            close := k;
            Break;
          end;
        end;
        Inc(k);
      end;
      if close > 0 then
      begin
        text := Copy(S, j + 1, close - j - 1);
        url := '';
        rest := '';
        // inline link (url "title")
        if (close < Length(S)) and (S[close + 1] = '(') then
        begin
          depth := 0;
          k := close + 1;
          while k <= Length(S) do
          begin
            if S[k] = '(' then
              Inc(depth)
            else if S[k] = ')' then
            begin
              Dec(depth);
              if depth = 0 then
                Break;
            end;
            Inc(k);
          end;
          if k <= Length(S) then
          begin
            url := Trim(Copy(S, close + 2, k - close - 2));
            if (url <> '') and (url[1] = '<') and (Pos('>', url) > 0) then
              url := Copy(url, 2, Pos('>', url) - 2)
            else if Pos(' ', url) > 0 then
              url := Copy(url, 1, Pos(' ', url) - 1);
            if isImage then
              Result := Result + LinkHtml(url, '[image: ' + RenderInline(text) + ']')
            else
              Result := Result + LinkHtml(url, RenderInline(text));
            i := k + 1;
            Continue;
          end;
        end;
        // reference link [text][ref] or [text][] or [ref]
        if (close < Length(S)) and (S[close + 1] = '[') then
        begin
          k := Pos(']', Copy(S, close + 2, MaxInt));
          if k > 0 then
          begin
            rest := Copy(S, close + 2, k - 1);
            if rest = '' then
              rest := text;
            url := FRefs.Values[LowerCase(rest)];
            if url <> '' then
            begin
              Result := Result + LinkHtml(url, RenderInline(text));
              i := close + 1 + k + 1;
              Continue;
            end;
          end;
        end;
        url := FRefs.Values[LowerCase(text)];
        if (url <> '') and not isImage then
        begin
          Result := Result + LinkHtml(url, RenderInline(text));
          i := close + 1;
          Continue;
        end;
      end;
    end;

    // bare URL
    if (c in ['h', 'H']) and ((i = 1) or not IsAlnum(S[i - 1])) then
    begin
      lowered := LowerCase(Copy(S, i, 8));
      if (Pos('http://', lowered) = 1) or (lowered = 'https://') then
      begin
        k := i;
        while (k <= Length(S)) and not IsSpaceChar(S[k]) and (S[k] <> '<') do
          Inc(k);
        url := Copy(S, i, k - i);
        while (url <> '') and (url[Length(url)] in ['.', ',', ';', ':', '!', '?', ')', '''', '"', '*', '_']) do
          Delete(url, Length(url), 1);
        if Length(url) > 8 then
        begin
          Result := Result + LinkHtml(url, HtmlEscape(url));
          Inc(i, Length(url));
          Continue;
        end;
      end;
    end;

    // emphasis / strong / strikethrough
    if c in ['*', '_', '~'] then
    begin
      n := 0;
      while (i + n <= Length(S)) and (S[i + n] = c) do
        Inc(n);
      // opening run must be followed by a non-space
      if (i + n <= Length(S)) and not IsSpaceChar(S[i + n]) and
         not ((c = '_') and (i > 1) and IsAlnum(S[i - 1])) then
      begin
        if c = '~' then
        begin
          if n = 2 then
          begin
            close := FindClosing(S, '~~', i + 2);
            if close > 0 then
            begin
              Result := Result + '<strike>' + RenderInline(Copy(S, i + 2, close - i - 2)) + '</strike>';
              i := close + 2;
              Continue;
            end;
          end;
        end
        else
        begin
          if n >= 3 then
          begin
            delim := StringOfChar(c, 3);
            close := FindClosing(S, delim, i + 3);
            if close > 0 then
            begin
              Result := Result + '<b><i>' + RenderInline(Copy(S, i + 3, close - i - 3)) + '</i></b>';
              i := close + 3;
              Continue;
            end;
          end;
          if n >= 2 then
          begin
            delim := StringOfChar(c, 2);
            close := FindClosing(S, delim, i + 2);
            if close > 0 then
            begin
              Result := Result + '<b>' + RenderInline(Copy(S, i + 2, close - i - 2)) + '</b>';
              i := close + 2;
              Continue;
            end;
          end;
          if n = 1 then
          begin
            close := FindClosing(S, c, i + 1);
            if close > 0 then
            begin
              Result := Result + '<i>' + RenderInline(Copy(S, i + 1, close - i - 1)) + '</i>';
              i := close + 1;
              Continue;
            end;
          end;
        end;
      end;
      Result := Result + StringOfChar(c, n);
      Inc(i, n);
      Continue;
    end;

    // HTML entities written in the source (&amp; &mdash; &#123;) pass through
    if c = '&' then
    begin
      k := 1;
      while (i + k <= Length(S)) and (k < 10) and (S[i + k] in ['a'..'z', 'A'..'Z', '0'..'9', '#']) do
        Inc(k);
      if (k > 1) and (i + k <= Length(S)) and (S[i + k] = ';') then
      begin
        Result := Result + Copy(S, i, k + 1);
        Inc(i, k + 1);
        Continue;
      end;
    end;

    Result := Result + HtmlEscape(c);
    Inc(i);
  end;
end;

function TMdRenderer.RenderBlocks(ALines: TStrings; ATight: Boolean): string;
var
  i, j, k, ind, lvl, fl, fl2, contentCol, startNum, itemContent, colCount: Integer;
  line, t, t2, s, para, lang, itemText, cellHtml, align: string;
  fc, fc2, marker, marker2: Char;
  ordered, ordered2, loose, sawBlank, firstRow: Boolean;
  sub, cells, aligns: TStringList;
  items: TList;
  itemLines: TStringList;
  isSetext: Integer;

  function StartsBlock(const L: string): Boolean;
  var
    tt, dummyT: string;
    dc: Char;
    dl, dn, dcol: Integer;
    dord: Boolean;
  begin
    tt := Trim(L);
    Result := (tt = '') or (HeadingLevel(tt) > 0) or IsFence(tt, dc, dl) or
      ((tt <> '') and (tt[1] = '>')) or IsHorizontalRule(tt);
    if (not Result) and (LeadingSpaces(L) < 4) and ParseListItem(L, dord, dc, dn, dcol, dummyT) then
      // an ordered item only interrupts a paragraph when it starts at 1
      Result := (dummyT <> '') and ((not dord) or (dn = 1));
  end;

begin
  Result := '';
  sub := TStringList.Create;
  cells := TStringList.Create;
  aligns := TStringList.Create;
  try
    i := 0;
    while i < ALines.Count do
    begin
      line := ALines[i];
      t := Trim(line);
      ind := LeadingSpaces(line);

      if t = '' then
      begin
        Inc(i);
        Continue;
      end;

      // HTML comment block
      if (ind < 4) and (Copy(t, 1, 4) = '<!--') then
      begin
        while (i < ALines.Count) and (Pos('-->', ALines[i]) = 0) do
          Inc(i);
        Inc(i);
        Continue;
      end;

      // fenced code
      if (ind < 4) and IsFence(t, fc, fl) then
      begin
        lang := Trim(Copy(t, fl + 1, MaxInt));
        s := '';
        Inc(i);
        while i < ALines.Count do
        begin
          t2 := Trim(ALines[i]);
          if IsFence(t2, fc2, fl2) and (fc2 = fc) and (fl2 >= fl) and (Trim(Copy(t2, fl2 + 1, MaxInt)) = '') then
          begin
            Inc(i);
            Break;
          end;
          s := s + HtmlEscape(StripSpaces(ALines[i], ind)) + LineEnding;
          Inc(i);
        end;
        if (s <> '') and (Copy(s, Length(s) - Length(LineEnding) + 1, MaxInt) = LineEnding) then
          SetLength(s, Length(s) - Length(LineEnding));
        Result := Result + CodeBlockHtml(s);
        Continue;
      end;

      // indented code
      if ind >= 4 then
      begin
        sub.Clear;
        while (i < ALines.Count) and ((Trim(ALines[i]) = '') or (LeadingSpaces(ALines[i]) >= 4)) do
        begin
          sub.Add(StripSpaces(ALines[i], 4));
          Inc(i);
        end;
        while (sub.Count > 0) and (Trim(sub[sub.Count - 1]) = '') do
          sub.Delete(sub.Count - 1);
        s := '';
        for j := 0 to sub.Count - 1 do
        begin
          if j > 0 then
            s := s + LineEnding;
          s := s + HtmlEscape(sub[j]);
        end;
        Result := Result + CodeBlockHtml(s);
        Continue;
      end;

      // ATX heading
      lvl := HeadingLevel(t);
      if lvl > 0 then
      begin
        s := Trim(Copy(t, lvl + 1, MaxInt));
        // strip closing #'s
        k := Length(s);
        while (k > 0) and (s[k] = '#') do
          Dec(k);
        if (k = 0) or (s[k] = ' ') then
          s := Trim(Copy(s, 1, k));
        Result := Result + '<a name="' + UniqueSlug(s) + '"></a><h' + IntToStr(lvl) + '>' +
          RenderInline(s) + '</h' + IntToStr(lvl) + '>' + LineEnding;
        if lvl <= 2 then
          Result := Result + '<hr size="1" color="#D8DEE4" noshade>' + LineEnding;
        Inc(i);
        Continue;
      end;

      // horizontal rule
      if IsHorizontalRule(t) then
      begin
        Result := Result + '<hr size="2" color="#D8DEE4" noshade>' + LineEnding;
        Inc(i);
        Continue;
      end;

      // table: header row + delimiter row
      if (Pos('|', t) > 0) and (i + 1 < ALines.Count) and (Pos('-', ALines[i + 1]) > 0) and
         IsTableDelimiterRow(Trim(ALines[i + 1])) then
      begin
        SplitTableRow(ALines[i + 1], cells);
        aligns.Clear;
        for j := 0 to cells.Count - 1 do
        begin
          s := cells[j];
          if (s <> '') and (s[1] = ':') and (s[Length(s)] = ':') then
            aligns.Add('center')
          else if (s <> '') and (s[Length(s)] = ':') then
            aligns.Add('right')
          else
            aligns.Add('left');
        end;
        colCount := aligns.Count;
        Result := Result + '<table border="1" cellspacing="0" cellpadding="5" bordercolor="#D0D7DE">' + LineEnding;
        firstRow := True;
        while i < ALines.Count do
        begin
          t2 := Trim(ALines[i]);
          if (t2 = '') or ((not firstRow) and (Pos('|', t2) = 0)) then
            Break;
          if (not firstRow) and IsTableDelimiterRow(t2) then
          begin
            Inc(i);
            Continue;
          end;
          SplitTableRow(t2, cells);
          if firstRow then
            Result := Result + '<tr bgcolor="#EEF0F3">'
          else
            Result := Result + '<tr>';
          for j := 0 to colCount - 1 do
          begin
            if j < cells.Count then
              cellHtml := RenderInline(cells[j])
            else
              cellHtml := '';
            if cellHtml = '' then
              cellHtml := '&nbsp;';
            align := aligns[j];
            if firstRow then
              Result := Result + '<th align="' + align + '" valign="top">' + cellHtml + '</th>'
            else
              Result := Result + '<td align="' + align + '" valign="top">' + cellHtml + '</td>';
          end;
          Result := Result + '</tr>' + LineEnding;
          firstRow := False;
          Inc(i);
        end;
        Result := Result + '</table>' + LineEnding;
        Continue;
      end;

      // block quote
      if (ind < 4) and (t[1] = '>') then
      begin
        sub.Clear;
        while i < ALines.Count do
        begin
          t2 := Trim(ALines[i]);
          if t2 = '' then
            Break;
          if t2[1] = '>' then
          begin
            s := TrimLeft(ALines[i]);
            Delete(s, 1, 1);
            if (s <> '') and (s[1] = ' ') then
              Delete(s, 1, 1);
            sub.Add(s);
          end
          else if StartsBlock(ALines[i]) then
            Break
          else
            sub.Add(ALines[i]);    // lazy continuation
          Inc(i);
        end;
        Result := Result + '<table border="0" cellspacing="0" cellpadding="0"><tr>' +
          '<td width="4" bgcolor="#D0D7DE">&nbsp;</td><td width="14">&nbsp;</td><td><font color="#57606A">' +
          RenderBlocks(sub, False) + '</font></td></tr></table>' + LineEnding;
        Continue;
      end;

      // list
      if ParseListItem(line, ordered, marker, startNum, contentCol, itemText) then
      begin
        items := TList.Create;
        loose := False;
        try
          // gather items; each item is a TStringList of its own lines
          while i < ALines.Count do
          begin
            line := ALines[i];
            if not ParseListItem(line, ordered2, marker2, k, itemContent, itemText) then
              Break;
            if (ordered2 <> ordered) or (marker2 <> marker) then
              Break;
            contentCol := itemContent;
            itemLines := TStringList.Create;
            items.Add(itemLines);
            itemLines.Add(itemText);
            Inc(i);
            sawBlank := False;
            while i < ALines.Count do
            begin
              line := ALines[i];
              if Trim(line) = '' then
              begin
                sawBlank := True;
                itemLines.Add('');
                Inc(i);
                Continue;
              end;
              if LeadingSpaces(line) >= contentCol then
              begin
                if sawBlank then
                  loose := True;
                itemLines.Add(StripSpaces(line, contentCol));
                sawBlank := False;
                Inc(i);
                Continue;
              end;
              // a sibling item?
              if ParseListItem(line, ordered2, marker2, k, itemContent, itemText) and
                 (ordered2 = ordered) and (marker2 = marker) then
              begin
                if sawBlank then
                  loose := True;
                Break;
              end;
              // lazy paragraph continuation
              if (not sawBlank) and not StartsBlock(line) then
              begin
                itemLines.Add(Trim(line));
                Inc(i);
                Continue;
              end;
              Break;
            end;
            // trailing blank lines do not belong to the item
            while (itemLines.Count > 1) and (Trim(itemLines[itemLines.Count - 1]) = '') do
              itemLines.Delete(itemLines.Count - 1);
          end;

          if ordered then
          begin
            if startNum <> 1 then
              Result := Result + '<ol start="' + IntToStr(startNum) + '">'
            else
              Result := Result + '<ol>';
          end
          else
            Result := Result + '<ul>';
          Result := Result + LineEnding;
          for j := 0 to items.Count - 1 do
          begin
            itemLines := TStringList(items[j]);
            s := '';
            if itemLines.Count > 0 then
            begin
              t2 := itemLines[0];
              // task list item
              if (Length(t2) >= 3) and (t2[1] = '[') and (t2[3] = ']') and (t2[2] in [' ', 'x', 'X']) and
                 ((Length(t2) = 3) or (t2[4] = ' ')) then
              begin
                if t2[2] = ' ' then
                  s := '<tt>[&nbsp;]</tt> '
                else
                  s := '<tt><b>[x]</b></tt> ';
                itemLines[0] := TrimLeft(Copy(t2, 4, MaxInt));
              end;
            end;
            // IPro runs <p> blocks together inside <li>, so items always render
            // "tight" and paragraphs inside them are split with line breaks
            Result := Result + '<li>' + s + RenderBlocks(itemLines, True) + '</li>' + LineEnding;
            if loose and (j < items.Count - 1) then
              Result := Result + '<br>';
          end;
          if ordered then
            Result := Result + '</ol>'
          else
            Result := Result + '</ul>';
          Result := Result + LineEnding;
        finally
          for j := 0 to items.Count - 1 do
            TStringList(items[j]).Free;
          items.Free;
        end;
        Continue;
      end;

      // paragraph (maybe a setext heading)
      para := '';
      isSetext := 0;
      while i < ALines.Count do
      begin
        line := ALines[i];
        t2 := Trim(line);
        if t2 = '' then
          Break;
        if para <> '' then
        begin
          // setext underline?
          if (LeadingSpaces(line) < 4) and (t2[1] in ['=', '-']) and
             (t2 = StringOfChar(t2[1], Length(t2))) then
          begin
            if t2[1] = '=' then isSetext := 1 else isSetext := 2;
            Inc(i);
            Break;
          end;
          if StartsBlock(line) then
            Break;
          if (Pos('|', t2) > 0) and (i + 1 < ALines.Count) and IsTableDelimiterRow(Trim(ALines[i + 1])) and
             (Pos('-', ALines[i + 1]) > 0) then
            Break;
          // join, keeping hard breaks
          if (Length(para) >= 2) and (Copy(para, Length(para) - 1, 2) = '  ') then
            para := TrimRight(para) + HardBreak
          else if (para <> '') and (para[Length(para)] = '\') then
            para := Copy(para, 1, Length(para) - 1) + HardBreak
          else
            para := TrimRight(para) + ' ';
        end;
        para := para + TrimLeft(line);
        Inc(i);
      end;
      para := TrimRight(para);
      if isSetext > 0 then
      begin
        Result := Result + '<a name="' + UniqueSlug(para) + '"></a><h' + IntToStr(isSetext) + '>' +
          RenderInline(para) + '</h' + IntToStr(isSetext) + '>' + LineEnding;
        Result := Result + '<hr size="1" color="#D8DEE4" noshade>' + LineEnding;
      end
      else if ATight then
      begin
        if Result <> '' then
          Result := Result + '<br><br>';
        Result := Result + RenderInline(para) + LineEnding;
      end
      else
        Result := Result + '<p>' + RenderInline(para) + '</p>' + LineEnding;
    end;
  finally
    sub.Free;
    cells.Free;
    aligns.Free;
  end;
end;

function TMdRenderer.Render(const ASource: string): string;
var
  lines: TStringList;
  i: Integer;
  src: string;
begin
  lines := TStringList.Create;
  try
    src := ASource;
    // strip UTF-8 BOM if the caller left one in
    if Copy(src, 1, 3) = #$EF#$BB#$BF then
      Delete(src, 1, 3);
    lines.Text := src;
    for i := 0 to lines.Count - 1 do
      lines[i] := ExpandTabs(lines[i]);
    // YAML front matter: drop it
    if (lines.Count > 0) and (Trim(lines[0]) = '---') then
    begin
      i := 1;
      while (i < lines.Count) and (Trim(lines[i]) <> '---') and (Trim(lines[i]) <> '...') do
        Inc(i);
      if (i < lines.Count) and (i < 60) then
        while i >= 0 do
        begin
          lines.Delete(0);
          Dec(i);
        end;
    end;
    CollectRefs(lines);
    Result := RenderBlocks(lines, False);
  finally
    lines.Free;
  end;
end;

function MarkdownToHtml(const ASource: string; AFontSize: Integer): string;
var
  r: TMdRenderer;
begin
  r := TMdRenderer.Create;
  try
    Result :=
      '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">' + LineEnding +
      '<style type="text/css">' + LineEnding +
      'body { color: #1F2328; }' + LineEnding +
      'h1, h2, h3, h4, h5, h6 { color: #1F2328; }' + LineEnding +
      'code { color: #9A3412; }' + LineEnding +
      'tt { font-size: ' + IntToStr(AFontSize) + 'pt; }' + LineEnding +
      'th { font-weight: bold; }' + LineEnding +
      '</style></head><body>' + LineEnding +
      r.Render(ASource) +
      '</body></html>';
  finally
    r.Free;
  end;
end;

end.
