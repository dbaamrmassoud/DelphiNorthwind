program NorthwindDesktop;

uses
  Vcl.Forms,
  Northwind.MainForm in 'Northwind.MainForm.pas',
  Northwind.OrderService.Contract in '..\shared\Northwind.OrderService.Contract.pas';

begin
  Application.Initialize;
  Application.Title := 'Northwind Sales';
  Application.CreateForm(TNorthwindMainForm, NorthwindMainForm);
  Application.Run;
end.
