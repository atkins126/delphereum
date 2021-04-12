{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2020 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{   Distributed under Creative Commons NonCommercial (aka CC BY-NC) license.   }
{                                                                              }
{******************************************************************************}

unit web3.eth.yearn.vaults;

{$I web3.inc}

interface

uses
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth.defi,
  web3.eth.types;

type
  TyVault = class(TLendingProtocol)
  protected
    class procedure Approve(
      client  : TWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt);
    class procedure TokenToUnderlying(
      client  : TWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
    class procedure UnderlyingToToken(
      client  : TWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
  public
    class function Name: string; override;
    class function Supports(
      chain  : TChain;
      reserve: TReserve): Boolean; override;
    class procedure APY(
      client  : TWeb3;
      reserve : TReserve;
      period  : TPeriod;
      callback: TAsyncFloat); override;
    class procedure Deposit(
      client  : TWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt); override;
    class procedure Balance(
      client  : TWeb3;
      owner   : TAddress;
      reserve : TReserve;
      callback: TAsyncQuantity); override;
    class procedure Withdraw(
      client  : TWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      callback: TAsyncReceiptEx); override;
    class procedure WithdrawEx(
      client  : TWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceiptEx); override;
  end;

implementation

uses
  // Delphi
  System.Types,
  // web3
  web3.eth.yearn.finance,
  web3.eth.yearn.tools;

type
  TyDAI = class(TyToken)
  public
    class function DeployedAt: TAddress; override;
  end;

  TyUSDC = class(TyToken)
  public
    class function DeployedAt: TAddress; override;
  end;

  TyUSDT = class(TyToken)
  public
    class function DeployedAt: TAddress; override;
  end;

type
  TyTokenClass = class of TyToken;

const
  yTokenClass: array[TReserve] of TyTokenClass = (
    TyDAI,
    TyUSDC,
    TyUSDT
  );

{ TyVault }

class procedure TyVault.Approve(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
var
  yToken: TyToken;
begin
  yToken := yTokenClass[reserve].Create(client);
  if Assigned(yToken) then
  begin
    yToken.ApproveUnderlying(from, amount, procedure(rcpt: ITxReceipt; err: IError)
    begin
      try
        callback(rcpt, err);
      finally
        yToken.Free;
      end;
    end);
  end;
end;

class procedure TyVault.TokenToUnderlying(
  client  : TWeb3;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncQuantity);
var
  yToken: TyToken;
begin
  yToken := yTokenClass[reserve].Create(client);
  if Assigned(yToken) then
  try
    yToken.TokenToUnderlying(amount, callback);
  finally
    yToken.Free;
  end;
end;

class procedure TyVault.UnderlyingToToken(
  client  : TWeb3;
  reserve : TReserve;
  amount  : BIgInteger;
  callback: TAsyncQuantity);
var
  yToken: TyToken;
begin
  yToken := yTokenClass[reserve].Create(client);
  if Assigned(yToken) then
  try
    yToken.UnderlyingToToken(amount, callback);
  finally
    yToken.Free;
  end;
end;

class function TyVault.Name: string;
begin
  Result := 'yVault';
end;

class function TyVault.Supports(chain: TChain; reserve: TReserve): Boolean;
begin
  Result := chain = Mainnet;
end;

class procedure TyVault.APY(
  client  : TWeb3;
  reserve : TReserve;
  period  : TPeriod;
  callback: TAsyncFloat);

  function getAPY(addr: TAddress; period: TPeriod; callback: TAsyncFloat): IAsyncResult;
  begin
    Result := web3.eth.yearn.tools.vault(addr, procedure(vault: IYearnVault; err: IError)
    begin
      if Assigned(err) then
        callback(0, err)
      else
        callback(vault.APY(period), nil);
    end);
  end;

var
  yToken: TyToken;
begin
  getAPY(yTokenClass[reserve].DeployedAt, period, procedure(apy: Extended; err: IError)
  begin
    if (apy > 0) and not Assigned(err) then
    begin
      callback(apy, err);
      EXIT;
    end;
    yToken := yTokenClass[reserve].Create(client);
    if Assigned(yToken) then
    begin
      yToken.APY(period, procedure(apy: Extended; err: IError)
      begin
        try
          callback(apy, err);
        finally
          yToken.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVault.Deposit(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
var
  yToken: TyToken;
begin
  Approve(client, from, reserve, amount, procedure(rcpt: ITxReceipt; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
    begin
      yToken := yTokenClass[reserve].Create(client);
      try
        yToken.Deposit(from, amount, callback);
      finally
        yToken.Free;
      end;
    end;
  end);
end;

class procedure TyVault.Balance(
  client  : TWeb3;
  owner   : TAddress;
  reserve : TReserve;
  callback: TAsyncQuantity);
var
  yToken: TyToken;
begin
  yToken := yTokenClass[reserve].Create(client);
  if Assigned(yToken) then
  try
    // step #1: get the yToken balance
    yToken.BalanceOf(owner, procedure(balance: BigInteger; err: IError)
    begin
      if Assigned(err) then
        callback(0, err)
      else
        // step #2: multiply it by the current yToken price
        TokenToUnderlying(client, reserve, balance, procedure(output: BigInteger; err: IError)
        begin
          if Assigned(err) then
            callback(0, err)
          else
            callback(output, nil);
        end);
    end);
  finally
    yToken.Free;
  end;
end;

class procedure TyVault.Withdraw(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  callback: TAsyncReceiptEx);
var
  yToken: TyToken;
begin
  yToken := yTokenClass[reserve].Create(client);
  if Assigned(yToken) then
  begin
    // step #1: get the yToken balance
    yToken.BalanceOf(from, procedure(balance: BigInteger; err: IError)
    begin
      try
        if Assigned(err) then
          callback(nil, 0, err)
        else
          // step #2: withdraw yToken-amount in exchange for the underlying asset.
          yToken.Withdraw(from, balance, procedure(rcpt: ITxReceipt; err: IError)
          begin
            if Assigned(err) then
              callback(nil, 0, err)
            else
              // step #3: from yToken-balance to Underlying-balance
              TokenToUnderlying(client, reserve, balance, procedure(output: BigInteger; err: IError)
              begin
                if Assigned(err) then
                  callback(rcpt, 0, err)
                else
                  callback(rcpt, output, nil);
              end);
          end);
      finally
        yToken.Free;
      end;
    end);
  end;
end;

class procedure TyVault.WithdrawEx(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceiptEx);
var
  yToken: TyToken;
begin
  // step #1: from Underlying-amount to yToken-amount
  UnderlyingToToken(client, reserve, amount, procedure(input: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, 0, err);
      EXIT;
    end;
    yToken := yTokenClass[reserve].Create(client);
    if Assigned(yToken) then
    try
      // step #2: withdraw yToken-amount in exchange for the underlying asset.
      yToken.Withdraw(from, input, procedure(rcpt: ITxReceipt; err: IError)
      begin
        if Assigned(err) then
          callback(nil, 0, err)
        else
          callback(rcpt, amount, nil);
      end);
    finally
      yToken.Free;
    end;
  end);
end;

{ TyDAI }

class function TyDAI.DeployedAt: TAddress;
begin
  Result := TAddress('0xACd43E627e64355f1861cEC6d3a6688B31a6F952');
end;

{ TyUSDC }

class function TyUSDC.DeployedAt: TAddress;
begin
  Result := TAddress('0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e');
end;

{ TyUSDT }

class function TyUSDT.DeployedAt: TAddress;
begin
  Result := TAddress('0x2f08119C6f07c006695E079AAFc638b8789FAf18');
end;

end.
