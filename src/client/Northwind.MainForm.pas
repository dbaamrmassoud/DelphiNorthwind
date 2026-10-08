unit Northwind.MainForm;

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  XData.Client,
  cxGrid,
  cxGridLevel,
  cxGridTableView,
  Sphinx.Login;

type
  TNorthwindMainForm = class(TForm)
  private
    FGrid: TcxGrid;
    FGridLevel: TcxGridLevel;
    FLoginButton: TButton;
    FLogin: TSphinxLogin;
    FLoginTimer: TTimer;
    FToolbar: TPanel;
    FView: TcxGridTableView;
    function AddToolbarButton(const Caption: string;
      Handler: TNotifyEvent): TButton;
    procedure ConfigureGrid(const Captions: array of string);
    function CreateApiClient: TXDataClient;
    procedure LoadCustomers(Sender: TObject);
    procedure LoadOrderDetails(Sender: TObject);
    procedure LoadOrders(Sender: TObject);
    procedure LoadProducts(Sender: TObject);
    procedure LoginClicked(Sender: TObject);
    procedure LoginTimerTick(Sender: TObject);
    procedure CreateOrder(Sender: TObject);
    procedure NewCustomer(Sender: TObject);
    procedure PrintProducts(Sender: TObject);
    procedure PopulateCustomers;
    procedure PopulateOrderDetails;
    procedure PopulateOrders;
    procedure PopulateProducts;
    procedure ShowFailure(E: Exception);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  NorthwindMainForm: TNorthwindMainForm;

implementation

uses
  Data.DB,
  Datasnap.DBClient,
  frxClass,
  frxDBSet,
  System.Generics.Collections,
  System.SysUtils,
  Aurelius.Types.Nullable,
  Northwind.Config,
  Northwind.Entities,
  Northwind.OrderService.Contract,
  Sparkle.HttpClient,
  VCL.TMSLogging,
  Vcl.Graphics;

constructor TNorthwindMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Northwind Sales';
  Width := 1100;
  Height := 720;
  Position := poScreenCenter;

  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.Height := 44;
  FToolbar.BevelOuter := bvNone;

  FLoginButton := AddToolbarButton('Sign in', LoginClicked);
  AddToolbarButton('New customer', NewCustomer);
  AddToolbarButton('Customers', LoadCustomers);
  AddToolbarButton('Products', LoadProducts);
  AddToolbarButton('Create order', CreateOrder);
  AddToolbarButton('Orders', LoadOrders);
  AddToolbarButton('Order lines', LoadOrderDetails);
  AddToolbarButton('Print products', PrintProducts);

  FGrid := TcxGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FView := TcxGridTableView.Create(FGrid);
  FGridLevel := FGrid.Levels.Add;
  FGridLevel.GridView := FView;

  ConfigureGrid(['Select a view', '', '', '']);

  FLogin := TSphinxLogin.Create(Self);
  FLogin.Authority := ReadSetting('Sphinx', 'Authority',
    'http://localhost:2003/tms/northwind/sphinx');
  FLogin.ClientId := ReadSetting('Sphinx', 'ClientId', 'northwind-desktop');
  FLogin.Scope := ReadSetting('Sphinx', 'Scope',
    'openid email northwind-api offline_access');

  FLoginTimer := TTimer.Create(Self);
  FLoginTimer.Enabled := False;
  FLoginTimer.Interval := 500;
  FLoginTimer.OnTimer := LoginTimerTick;
  TMSLogger.Info('Northwind desktop client started.');
end;

function TNorthwindMainForm.AddToolbarButton(const Caption: string;
  Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FToolbar;
  Result.Align := alLeft;
  Result.Caption := Caption;
  Result.Width := 120;
  Result.OnClick := Handler;
end;

procedure TNorthwindMainForm.ConfigureGrid(const Captions: array of string);
var
  Column: TcxGridColumn;
  I: Integer;
begin
  while FView.ColumnCount > 0 do
    FView.Columns[0].Free;
  for I := Low(Captions) to High(Captions) do
  begin
    Column := FView.CreateColumn;
    Column.Caption := Captions[I];
    Column.DataBinding.ValueType := 'String';
  end;
  FView.DataController.RecordCount := 0;
end;

function TNorthwindMainForm.CreateApiClient: TXDataClient;
var
  Client: TXDataClient;
  AccessToken: string;
begin
  if not FLogin.IsLoggedIn then
    raise Exception.Create('Sign in through Sphinx before loading data.');

  AccessToken := FLogin.AuthResult.AccessToken;
  Client := TXDataClient.Create;
  Client.Uri := ReadSetting('Api', 'BaseUrl',
    'http://localhost:2002/tms/northwind/xdata');
  Client.HttpClient.OnSendingRequest :=
    procedure(Request: THttpRequest)
    begin
      Request.Headers.SetValue('Authorization', 'Bearer ' + AccessToken);
    end;
  Result := Client;
end;

procedure TNorthwindMainForm.LoginClicked(Sender: TObject);
begin
  try
    FLogin.Login;
    FLoginTimer.Enabled := True;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

procedure TNorthwindMainForm.LoginTimerTick(Sender: TObject);
begin
  if FLogin.IsLoggedIn then
  begin
    FLoginTimer.Enabled := False;
    FLoginButton.Caption := 'Signed in';
    TMSLogger.Info('Sphinx sign-in completed.');
  end;
end;

procedure TNorthwindMainForm.ShowFailure(E: Exception);
begin
  TMSLogger.Error(E.Message);
  Application.ShowException(E);
end;

procedure TNorthwindMainForm.LoadCustomers(Sender: TObject);
begin
  try
    PopulateCustomers;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

procedure TNorthwindMainForm.NewCustomer(Sender: TObject);
var
  Client: TXDataClient;
  Customer: TCustomer;
  CustomerID: string;
  CompanyName: string;
begin
  if not InputQuery('New customer', 'Customer ID (5 characters):', CustomerID) then
    Exit;
  if not InputQuery('New customer', 'Company name:', CompanyName) then
    Exit;
  if Length(Trim(CustomerID)) <> 5 then
  begin
    ShowMessage('Northwind customer IDs must contain exactly five characters.');
    Exit;
  end;
  if Trim(CompanyName) = '' then
  begin
    ShowMessage('Company name is required.');
    Exit;
  end;

  Client := nil;
  Customer := TCustomer.Create;
  try
    try
      Client := CreateApiClient;
      Customer.CustomerID := UpperCase(Trim(CustomerID));
      Customer.CompanyName := Trim(CompanyName);
      Client.Post(Customer);
    except
      on E: Exception do
      begin
        ShowFailure(E);
        Exit;
      end;
    end;
  finally
    Customer.Free;
    Client.Free;
  end;
  LoadCustomers(nil);
end;

procedure TNorthwindMainForm.PopulateCustomers;
var
  Client: TXDataClient;
  Customers: TList<TCustomer>;
  I: Integer;
begin
  Client := CreateApiClient;
  try
    Customers := Client.List<TCustomer>('$orderby=CompanyName');
    try
      ConfigureGrid(['Customer ID', 'Company', 'Contact', 'Country']);
      FView.DataController.RecordCount := Customers.Count;
      for I := 0 to Customers.Count - 1 do
      begin
        FView.DataController.Values[I, 0] := Customers[I].CustomerID;
        FView.DataController.Values[I, 1] := Customers[I].CompanyName;
        FView.DataController.Values[I, 2] := Customers[I].ContactName;
        FView.DataController.Values[I, 3] := Customers[I].Country;
      end;
    finally
      Customers.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TNorthwindMainForm.LoadProducts(Sender: TObject);
begin
  try
    PopulateProducts;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

procedure TNorthwindMainForm.PopulateProducts;
var
  Client: TXDataClient;
  Products: TList<TProduct>;
  I: Integer;
begin
  Client := CreateApiClient;
  try
    Products := Client.List<TProduct>('$orderby=ProductName');
    try
      ConfigureGrid(['Product ID', 'Product', 'Unit price', 'In stock']);
      FView.DataController.RecordCount := Products.Count;
      for I := 0 to Products.Count - 1 do
      begin
        FView.DataController.Values[I, 0] := Products[I].ProductID;
        FView.DataController.Values[I, 1] := Products[I].ProductName;
        if Products[I].UnitPrice.HasValue then
          FView.DataController.Values[I, 2] :=
            FormatCurr('0.00', Products[I].UnitPrice.Value)
        else
          FView.DataController.Values[I, 2] := '';
        if Products[I].UnitsInStock.HasValue then
          FView.DataController.Values[I, 3] := Products[I].UnitsInStock.Value
        else
          FView.DataController.Values[I, 3] := '';
      end;
    finally
      Products.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TNorthwindMainForm.LoadOrders(Sender: TObject);
begin
  try
    PopulateOrders;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

procedure TNorthwindMainForm.PopulateOrders;
var
  Client: TXDataClient;
  Orders: TList<TOrder>;
  I: Integer;
begin
  Client := CreateApiClient;
  try
    Orders := Client.List<TOrder>('$orderby=OrderID desc&$top=100');
    try
      ConfigureGrid(['Order ID', 'Customer ID', 'Order date', 'Ship country']);
      FView.DataController.RecordCount := Orders.Count;
      for I := 0 to Orders.Count - 1 do
      begin
        FView.DataController.Values[I, 0] := Orders[I].OrderID;
        FView.DataController.Values[I, 1] := Orders[I].CustomerID;
        if Orders[I].OrderDate.HasValue then
          FView.DataController.Values[I, 2] :=
            DateToStr(Orders[I].OrderDate.Value)
        else
          FView.DataController.Values[I, 2] := '';
        FView.DataController.Values[I, 3] := Orders[I].ShipCountry;
      end;
    finally
      Orders.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TNorthwindMainForm.CreateOrder(Sender: TObject);
var
  Client: TXDataClient;
  CustomerID: string;
  OrderID: Integer;
  ProductID: Integer;
  ProductIDText: string;
  Quantity: Integer;
  QuantityText: string;
begin
  if not InputQuery('Create order', 'Customer ID (5 characters):', CustomerID) then
    Exit;
  if not InputQuery('Create order', 'Product ID:', ProductIDText) then
    Exit;
  if not InputQuery('Create order', 'Quantity:', QuantityText) then
    Exit;

  CustomerID := UpperCase(Trim(CustomerID));
  if Length(CustomerID) <> 5 then
  begin
    ShowMessage('Northwind customer IDs must contain exactly five characters.');
    Exit;
  end;
  if not TryStrToInt(ProductIDText, ProductID) or (ProductID <= 0) then
  begin
    ShowMessage('Product ID must be a positive integer.');
    Exit;
  end;
  if not TryStrToInt(QuantityText, Quantity) or
     (Quantity <= 0) or (Quantity > High(SmallInt)) then
  begin
    ShowMessage('Quantity must be between 1 and 32767.');
    Exit;
  end;

  Client := nil;
  try
    try
      Client := CreateApiClient;
      OrderID := Client.Service<IOrderEntryService>.CreateOrder(
        CustomerID, ProductID, SmallInt(Quantity));
      ShowMessage(Format('Order %d was created.', [OrderID]));
      LoadOrders(nil);
    except
      on E: Exception do
        ShowFailure(E);
    end;
  finally
    Client.Free;
  end;
end;

procedure TNorthwindMainForm.LoadOrderDetails(Sender: TObject);
begin
  try
    PopulateOrderDetails;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

procedure TNorthwindMainForm.PopulateOrderDetails;
var
  Client: TXDataClient;
  OrderDetails: TList<TOrderDetail>;
  I: Integer;
begin
  Client := CreateApiClient;
  try
    OrderDetails := Client.List<TOrderDetail>(
      '$orderby=OrderID desc&$top=100');
    try
      ConfigureGrid(['Order ID', 'Product ID', 'Unit price', 'Quantity']);
      FView.DataController.RecordCount := OrderDetails.Count;
      for I := 0 to OrderDetails.Count - 1 do
      begin
        FView.DataController.Values[I, 0] := OrderDetails[I].OrderID;
        FView.DataController.Values[I, 1] := OrderDetails[I].ProductID;
        FView.DataController.Values[I, 2] :=
          FormatCurr('0.00', OrderDetails[I].UnitPrice);
        FView.DataController.Values[I, 3] := OrderDetails[I].Quantity;
      end;
    finally
      OrderDetails.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TNorthwindMainForm.PrintProducts(Sender: TObject);
var
  Client: TXDataClient;
  DataSet: TClientDataSet;
  Products: TList<TProduct>;
  Report: TfrxReport;
  ReportData: TfrxDBDataset;
  Page: TfrxReportPage;
  MasterData: TfrxMasterData;
  Memo: TfrxMemoView;
  I: Integer;
begin
  try
    Client := CreateApiClient;
    try
      Products := Client.List<TProduct>('$orderby=ProductName');
      try
        DataSet := nil;
        Report := nil;
        try
          DataSet := TClientDataSet.Create(nil);
          Report := TfrxReport.Create(nil);
          DataSet.FieldDefs.Add('ProductName', ftWideString, 40);
          DataSet.FieldDefs.Add('UnitPrice', ftCurrency);
          DataSet.FieldDefs.Add('UnitsInStock', ftSmallint);
          DataSet.CreateDataSet;
          for I := 0 to Products.Count - 1 do
          begin
            DataSet.Append;
            DataSet.FieldByName('ProductName').AsString := Products[I].ProductName;
            if Products[I].UnitPrice.HasValue then
              DataSet.FieldByName('UnitPrice').AsCurrency :=
                Products[I].UnitPrice.Value
            else
              DataSet.FieldByName('UnitPrice').Clear;
            if Products[I].UnitsInStock.HasValue then
              DataSet.FieldByName('UnitsInStock').AsInteger :=
                Products[I].UnitsInStock.Value
            else
              DataSet.FieldByName('UnitsInStock').Clear;
            DataSet.Post;
          end;

          ReportData := TfrxDBDataset.Create(Report);
          ReportData.UserName := 'Products';
          ReportData.DataSet := DataSet;
          Report.DataSets.Add(ReportData);

          Page := TfrxReportPage.Create(Report);
          Page.CreateUniqueName;
          Page.SetDefaults;

          Memo := TfrxMemoView.Create(Page);
          Memo.Left := 10;
          Memo.Top := 10;
          Memo.Width := 520;
          Memo.Height := 24;
          Memo.Text := 'Northwind Product Catalog';
          Memo.Font.Size := 16;
          Memo.Font.Style := [fsBold];

          Memo := TfrxMemoView.Create(Page);
          Memo.Left := 10;
          Memo.Top := 36;
          Memo.Width := 520;
          Memo.Height := 16;
          Memo.Text := 'Product                                      Unit price      Units in stock';
          Memo.Font.Style := [fsBold];

          MasterData := TfrxMasterData.Create(Page);
          MasterData.DataSet := ReportData;
          MasterData.DataSetName := ReportData.UserName;
          MasterData.Top := 48;
          MasterData.Height := 22;

          Memo := TfrxMemoView.Create(MasterData);
          Memo.Left := 0;
          Memo.Top := 0;
          Memo.Width := 300;
          Memo.Height := 22;
          Memo.Text := '[Products."ProductName"]';
          Memo := TfrxMemoView.Create(MasterData);
          Memo.Left := 300;
          Memo.Top := 0;
          Memo.Width := 100;
          Memo.Height := 22;
          Memo.Text := '[Products."UnitPrice"]';
          Memo := TfrxMemoView.Create(MasterData);
          Memo.Left := 400;
          Memo.Top := 0;
          Memo.Width := 100;
          Memo.Height := 22;
          Memo.Text := '[Products."UnitsInStock"]';

          Report.ShowReport;
        finally
          Report.Free;
          DataSet.Free;
        end;
      finally
        Products.Free;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do
      ShowFailure(E);
  end;
end;

end.
