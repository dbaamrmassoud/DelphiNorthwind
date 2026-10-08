program NorthwindIdentity;

uses
  Vcl.Forms,
  Identity.MainForm in 'Identity.MainForm.pas';

begin
  Application.Initialize;
  Application.Title := 'Northwind Identity';
  Application.CreateForm(TIdentityMainForm, IdentityMainForm);
  Application.Run;
end.
