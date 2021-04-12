{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2019 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{   Distributed under Creative Commons NonCommercial (aka CC BY-NC) license.   }
{                                                                              }
{******************************************************************************}

unit web3.eth.erc20;

{$I web3.inc}

interface

uses
  // Delphi
  System.Math,
  System.Threading,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth,
  web3.eth.contract,
  web3.eth.logs,
  web3.eth.types,
  web3.utils;

type
  TOnTransfer = reference to procedure(
    Sender: TObject;
    From  : TAddress;
    &To   : TAddress;
    Value : BigInteger);
  TOnApproval = reference to procedure(
    Sender : TObject;
    Owner  : TAddress;
    Spender: TAddress;
    Value  : BigInteger);

  IERC20 = interface(ICustomContract)
    //------- read from contract -----------------------------------------------
    procedure Name       (callback: TAsyncString);
    procedure Symbol     (callback: TAsyncString);
    procedure Decimals   (callback: TAsyncQuantity);
    procedure TotalSupply(callback: TAsyncQuantity);
    procedure BalanceOf  (owner: TAddress; callback: TAsyncQuantity);
    procedure Allowance  (owner, spender: TAddress; callback: TAsyncQuantity);
    //------- write to contract ------------------------------------------------
    procedure Transfer(
      from    : TPrivateKey;
      &to     : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);
    procedure Approve(
      owner   : TPrivateKey;
      spender : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);
    procedure ApproveEx(
      owner   : TPrivateKey;
      spender : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);
  end;

  TERC20 = class(TCustomContract, IERC20)
  strict private
    FTask      : ITask;
    FOnTransfer: TOnTransfer;
    FOnApproval: TOnApproval;
    procedure SetOnTransfer(Value: TOnTransfer);
    procedure SetOnApproval(Value: TOnApproval);
  protected
    procedure EventChanged;
    function  ListenForLatestBlock: Boolean; virtual;
    procedure OnLatestBlockMined(log: TLog); virtual;
  public
    constructor Create(aClient: TWeb3; aContract: TAddress); override;
    destructor  Destroy; override;

    //------- read from contract -----------------------------------------------
    procedure Name       (callback: TAsyncString);
    procedure Symbol     (callback: TAsyncString);
    procedure Decimals   (callback: TAsyncQuantity);
    procedure TotalSupply(callback: TAsyncQuantity); overload;
    procedure TotalSupply(const block: string; callback: TAsyncQuantity); overload;
    procedure BalanceOf  (owner: TAddress; callback: TAsyncQuantity);
    procedure Allowance  (owner, spender: TAddress; callback: TAsyncQuantity);

    //------- helpers ----------------------------------------------------------
    procedure Scale  (amount: Extended; callback: TAsyncQuantity);
    procedure Unscale(amount: BigInteger; callback: TAsyncFloat);

    //------- write to contract ------------------------------------------------
    procedure Transfer(
      from    : TPrivateKey;
      &to     : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);
    procedure Approve(
      owner   : TPrivateKey;
      spender : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);
    procedure ApproveEx(
      owner   : TPrivateKey;
      spender : TAddress;
      value   : BigInteger;
      callback: TAsyncReceipt);

    //------- events -----------------------------------------------------------
    property OnTransfer: TOnTransfer read FOnTransfer write SetOnTransfer;
    property OnApproval: TOnApproval read FOnApproval write SetOnApproval;
  end;

implementation

{ TERC20 }

constructor TERC20.Create(aClient: TWeb3; aContract: TAddress);
begin
  inherited Create(aClient, aContract);
  FTask := web3.eth.logs.get(aClient, aContract, OnLatestBlockMined);
end;

destructor TERC20.Destroy;
begin
  if FTask.Status = TTaskStatus.Running then
    FTask.Cancel;
  inherited Destroy;
end;

procedure TERC20.EventChanged;
begin
  if ListenForLatestBlock then
  begin
    if not(FTask.Status in [TTaskStatus.WaitingToRun, TTaskStatus.Running]) then
      FTask.Start;
    EXIT;
  end;
  if FTask.Status = TTaskStatus.Running then
    FTask.Cancel;
end;

function TERC20.ListenForLatestBlock: Boolean;
begin
  Result := Assigned(FOnTransfer)
         or Assigned(FOnApproval);
end;

procedure TERC20.OnLatestBlockMined(log: TLog);
begin
  if Assigned(FOnTransfer) then
    if log.isEvent('Transfer(address,address,uint256)') then
      FOnTransfer(Self,
                  log.Topic[1].toAddress, // from
                  log.Topic[2].toAddress, // to
                  log.Data[0].toBigInt);  // value
  if Assigned(FOnApproval) then
    if log.isEvent('Approval(address,address,uint256)') then
      FOnApproval(Self,
                  log.Topic[1].toAddress, // owner
                  log.Topic[2].toAddress, // spender
                  log.Data[0].toBigInt);  // value
end;

procedure TERC20.SetOnTransfer(Value: TOnTransfer);
begin
  FOnTransfer := Value;
  EventChanged;
end;

procedure TERC20.SetOnApproval(Value: TOnApproval);
begin
  FOnApproval := Value;
  EventChanged;
end;

procedure TERC20.Name(callback: TAsyncString);
begin
  web3.eth.call(Client, Contract, 'name()', [], procedure(tup: TTuple; err: IError)
  begin
    if Assigned(err) then
      callback('', err)
    else
      callback(tup.ToString, nil);
  end);
end;

procedure TERC20.Symbol(callback: TAsyncString);
begin
  web3.eth.call(Client, Contract, 'symbol()', [], procedure(tup: TTuple; err: IError)
  begin
    if Assigned(err) then
      callback('', err)
    else
      callback(tup.ToString, nil);
  end);
end;

procedure TERC20.Decimals(callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'decimals()', [], callback);
end;

procedure TERC20.TotalSupply(callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'totalSupply()', [], callback);
end;

procedure TERC20.TotalSupply(const block: string; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'totalSupply()', block, [], callback);
end;

procedure TERC20.BalanceOf(owner: TAddress; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'balanceOf(address)', [owner], callback);
end;

procedure TERC20.Allowance(owner, spender: TAddress; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'allowance(address,address)', [owner, spender], callback);
end;

procedure TERC20.Scale(amount: Extended; callback: TAsyncQuantity);
begin
  Self.Decimals(procedure(dec: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      if dec.IsZero then
        callback(BigInteger.Create(amount), nil)
      else
        callback(BigInteger.Create(amount * Power(10, dec.AsExtended)), nil);
  end);
end;

procedure TERC20.Unscale(amount: BigInteger; callback: TAsyncFloat);
begin
  Self.Decimals(procedure(dec: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      if dec.IsZero then
        callback(amount.AsExtended, nil)
      else
        callback(amount.AsExtended / Power(10, dec.AsExtended), nil);
  end);
end;

procedure TERC20.Transfer(
  from    : TPrivateKey;
  &to     : TAddress;
  value   : BigInteger;
  callback: TAsyncReceipt);
begin
  web3.eth.write(Client, from, Contract, 'transfer(address,uint256)', [&to, web3.utils.toHex(value)], callback);
end;

procedure TERC20.Approve(
  owner   : TPrivateKey;
  spender : TAddress;
  value   : BigInteger;
  callback: TAsyncReceipt);
begin
  web3.eth.write(Client, owner, Contract, 'approve(address,uint256)', [spender, web3.utils.toHex(value)], callback);
end;

procedure TERC20.ApproveEx(
  owner   : TPrivateKey;
  spender : TAddress;
  value   : BigInteger;
  callback: TAsyncReceipt);
begin
  owner.Address(procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      Allowance(addr, spender, procedure(approved: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(nil, err)
        else
          if ((value = 0) and (approved = 0))
          or ((value > 0) and (approved >= value)) then
            callback(nil, nil)
          else
            Approve(owner, spender, value, callback);
      end);
  end);
end;

end.
