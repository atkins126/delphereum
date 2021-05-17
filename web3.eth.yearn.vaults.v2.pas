{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2021 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{   Distributed under Creative Commons NonCommercial (aka CC BY-NC) license.   }
{                                                                              }
{******************************************************************************}

unit web3.eth.yearn.vaults.v2;

{$I web3.inc}

interface

uses
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth.contract,
  web3.eth.defi,
  web3.eth.erc20,
  web3.eth.types;

type
  TyVaultV2 = class(TLendingProtocol)
  protected
    class procedure Approve(
      client  : TWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt);
    class procedure TokenToUnderlyingAmount(
      client  : TWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
    class procedure UnderlyingToTokenAmount(
      client  : TWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
    class procedure UnderlyingToTokenAddress(
      client  : TWeb3;
      reserve : TReserve;
      callback: TAsyncAddress);
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

type
  TyVaultRegistry = class;

  TAsyncRegistry = reference to procedure(reg: TyVaultRegistry; err: IError);

  TyVaultRegistry = class(TCustomContract)
  public
    class procedure Create(client: TWeb3; callback: TAsyncRegistry); reintroduce;
    procedure LatestVault(reserve: TAddress; callback: TAsyncAddress);
  end;

type
  TyVaultToken = class abstract(TERC20)
  public
    //------- read from contract -----------------------------------------------
    procedure PricePerShare(const block: string; callback: TAsyncQuantity);
    procedure PricePerShareEx(const block: string; callback: TAsyncFloat);
    //------- helpers ----------------------------------------------------------
    procedure TokenToUnderlying(amount: BigInteger; callback: TAsyncQuantity);
    procedure UnderlyingToToken(amount: BigInteger; callback: TAsyncQuantity);
    procedure APY(period: TPeriod; callback: TAsyncFloat);
    //------- write to contract ------------------------------------------------
    procedure Deposit(from: TPrivateKey; amount: BigInteger; callback: TAsyncReceipt);
    procedure Withdraw(from: TPrivateKey; amount: BigInteger; callback: TAsyncReceipt);
  end;

implementation

uses
  // Delphi
  System.Math,
  // web3
  web3.eth,
  web3.eth.etherscan,
  web3.utils;

{ TyVaultV2 }

class procedure TyVaultV2.Approve(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(token: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    var underlying := TERC20.Create(client, reserve.Address);
    if Assigned(underlying) then
    begin
      underlying.ApproveEx(from, token, amount, procedure(rcpt: ITxReceipt; err: IError)
      begin
        try
          callback(rcpt, err);
        finally
          underlying.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVaultV2.TokenToUnderlyingAmount(
  client  : TWeb3;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    var yVaultToken := TyVaultToken.Create(client, addr);
    begin
      yVaultToken.TokenToUnderlying(amount, procedure(result: BigInteger; err: IError)
      begin
        try
          callback(result, err);
        finally
          yVaultToken.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVaultV2.UnderlyingToTokenAmount(
  client  : TWeb3;
  reserve : TReserve;
  amount  : BIgInteger;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    var yVaultToken := TyVaultToken.Create(client, addr);
    begin
      yVaultToken.UnderlyingToToken(amount, procedure(result: BigInteger; err: IError)
      begin
        try
          callback(result, err);
        finally
          yVaultToken.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVaultV2.UnderlyingToTokenAddress(
  client  : TWeb3;
  reserve : TReserve;
  callback: TAsyncAddress);
begin
  TyVaultRegistry.Create(client, procedure(reg: TyVaultRegistry; err: IError)
  begin
    if Assigned(reg) then
    try
      reg.LatestVault(reserve.Address, callback);
      EXIT;
    finally
      reg.Free;
    end;
    callback(ADDRESS_ZERO, err);
  end);
end;

class function TyVaultV2.Name: string;
begin
  Result := 'yVault v2';
end;

class function TyVaultV2.Supports(chain: TChain; reserve: TReserve): Boolean;
begin
  Result := (chain = Mainnet) and (reserve in [DAI, USDC, USDT]);
end;

class procedure TyVaultV2.APY(
  client  : TWeb3;
  reserve : TReserve;
  period  : TPeriod;
  callback: TAsyncFloat);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    var yVaultToken := TyVaultToken.Create(client, addr);
    if Assigned(yVaultToken) then
    begin
      yVaultToken.APY(period, procedure(apy: Extended; err: IError)
      begin
        try
          if Assigned(err)
          or (period = Low(TPeriod))
          or (not(IsNaN(apy) or IsInfinite(apy))) then
          begin
            callback(apy, err);
            EXIT;
          end;
          Self.APY(client, reserve, Pred(period), callback);
        finally
          yVaultToken.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVaultV2.Deposit(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  Self.Approve(client, from, reserve, amount, procedure(rcpt: ITxReceipt; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(nil, err);
        EXIT;
      end;
      var yVaultToken := TyVaultToken.Create(client, addr);
      try
        yVaultToken.Deposit(from, amount, callback);
      finally
        yVaultToken.Free;
      end;
    end);
  end);
end;

class procedure TyVaultV2.Balance(
  client  : TWeb3;
  owner   : TAddress;
  reserve : TReserve;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    var yVaultToken := TyVaultToken.Create(client, addr);
    try
      // step #1: get the yVaultToken balance
      yVaultToken.BalanceOf(owner, procedure(balance: BigInteger; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        // step #2: multiply it by the current yVaultToken price
        Self.TokenToUnderlyingAmount(client, reserve, balance, procedure(output: BigInteger; err: IError)
        begin
          if Assigned(err) then
            callback(0, err)
          else
            callback(output, nil);
        end);
      end);
    finally
      yVaultToken.Free;
    end;
  end);
end;

class procedure TyVaultV2.Withdraw(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  callback: TAsyncReceiptEx);
begin
  Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, 0, err);
      EXIT;
    end;
    var yVaultToken := TyVaultToken.Create(client, addr);
    if Assigned(yVaultToken) then
    begin
      // step #1: get the yVaultToken balance
      yVaultToken.BalanceOf(from, procedure(balance: BigInteger; err: IError)
      begin
        try
          if Assigned(err) then
          begin
            callback(nil, 0, err);
            EXIT;
          end;
          // step #2: withdraw yVaultToken-amount in exchange for the underlying asset.
          yVaultToken.Withdraw(from, balance, procedure(rcpt: ITxReceipt; err: IError)
          begin
            if Assigned(err) then
            begin
              callback(nil, 0, err);
              EXIT;
            end;
            // step #3: from yVaultToken-balance to Underlying-balance
            Self.TokenToUnderlyingAmount(client, reserve, balance, procedure(output: BigInteger; err: IError)
            begin
              if Assigned(err) then
                callback(rcpt, 0, err)
              else
                callback(rcpt, output, nil);
            end);
          end);
        finally
          yVaultToken.Free;
        end;
      end);
    end;
  end);
end;

class procedure TyVaultV2.WithdrawEx(
  client  : TWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceiptEx);
begin
  // step #1: from Underlying-amount to yVaultToken-amount
  Self.UnderlyingToTokenAmount(client, reserve, amount, procedure(input: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, 0, err);
      EXIT;
    end;
    Self.UnderlyingToTokenAddress(client, reserve, procedure(addr: TAddress; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(nil, 0, err);
        EXIT;
      end;
      var yVaultToken := TyVaultToken.Create(client, addr);
      if Assigned(yVaultToken) then
      try
        // step #2: withdraw yVaultToken-amount in exchange for the underlying asset.
        yVaultToken.Withdraw(from, input, procedure(rcpt: ITxReceipt; err: IError)
        begin
          if Assigned(err) then
            callback(nil, 0, err)
          else
            callback(rcpt, amount, nil);
        end);
      finally
        yVaultToken.Free;
      end;
    end);
  end);
end;

{ TyVaultRegistry }

class procedure TyVaultRegistry.Create(client: TWeb3; callback: TAsyncRegistry);
begin
  TAddress.New(client, 'v2.registry.ychad.eth', procedure(addr: TAddress; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      callback(inherited Create(client, addr), nil);
  end);
end;

procedure TyVaultRegistry.LatestVault(reserve: TAddress; callback: TAsyncAddress);
begin
  web3.eth.call(Client, Contract, 'latestVault(address)', [reserve], procedure(const hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(ADDRESS_ZERO, err)
    else
      callback(TAddress.New(hex), nil);
  end);
end;

{ TyVaultToken }

procedure TyVaultToken.PricePerShare(const block: string; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'pricePerShare()', block, [], callback);
end;

procedure TyVaultToken.PricePerShareEx(const block: string; callback: TAsyncFloat);
begin
  Self.PricePerShare(block, procedure(price: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    Self.Decimals(procedure(decimals: BigInteger; err: IError)
    begin
      if Assigned(err) then
        callback(0, err)
      else
        callback(price.AsExtended / Power(10, decimals.AsInteger), nil);
    end);
  end);
end;

procedure TyVaultToken.TokenToUnderlying(amount: BigInteger; callback: TAsyncQuantity);
begin
  Self.PricePerShareEx(BLOCK_LATEST, procedure(price: Extended; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(BigInteger.Create(amount.AsExtended * price), nil);
  end);
end;

procedure TyVaultToken.UnderlyingToToken(amount: BIgInteger; callback: TAsyncQuantity);
begin
  Self.PricePerShareEx(BLOCK_LATEST, procedure(price: Extended; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(BigInteger.Create(amount.AsExtended / price), nil);
  end);
end;

procedure TyVaultToken.APY(period: TPeriod; callback: TAsyncFloat);
begin
  Self.PricePerShare(BLOCK_LATEST, procedure(currPrice: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    getBlockNumberByTimestamp(client, web3.Now - period.Seconds, procedure(bn: BigInteger; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(0, err);
        EXIT;
      end;
      Self.PricePerShare(web3.utils.toHex(bn), procedure(pastPrice: BigInteger; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        if IsNaN(currPrice.AsExtended) or IsNaN(pastPrice.AsExtended) then
          callback(NaN, nil)
        else
          callback(period.ToYear((currPrice.AsExtended / pastPrice.AsExtended - 1) * 100), nil);
      end);
    end);
  end);
end;

procedure TyVaultToken.Deposit(from: TPrivateKey; amount: BigInteger; callback: TAsyncReceipt);
begin
  web3.eth.write(Client, from, Contract, 'deposit(uint256)', [web3.utils.toHex(amount)], callback);
end;

procedure TyVaultToken.Withdraw(from: TPrivateKey; amount: BigInteger; callback: TAsyncReceipt);
begin
  web3.eth.write(Client, from, Contract, 'withdraw(uint256)', [web3.utils.toHex(amount)], callback);
end;

end.
