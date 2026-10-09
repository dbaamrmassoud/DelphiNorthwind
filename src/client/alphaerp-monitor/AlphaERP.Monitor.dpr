program AlphaERPServiceMonitor;

uses
  Vcl.Forms,
  AlphaERP.Config in '..\..\shared\AlphaERP.Config.pas',
  AlphaERP.ServiceControl in '..\..\shared\AlphaERP.ServiceControl.pas',
  AlphaERP.Health.Contract in '..\..\shared\AlphaERP.Health.Contract.pas',
  AlphaERP.MonitorForm in 'AlphaERP.MonitorForm.pas';

begin
  Application.Initialize;
  Application.Title := 'AlphaERP Service Monitor';
  Application.CreateForm(TAlphaERPMonitorForm, AlphaERPMonitorForm);
  Application.Run;
end.
