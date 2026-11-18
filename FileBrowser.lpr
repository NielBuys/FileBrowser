program FileBrowser;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, uMain, uMarkdown, uSynMarkdown;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'File Browser';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
