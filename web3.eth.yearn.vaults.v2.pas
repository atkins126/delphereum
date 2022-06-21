{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2021 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{             Distributed under GNU AGPL v3.0 with Commons Clause              }
{                                                                              }
{   This program is free software: you can redistribute it and/or modify       }
{   it under the terms of the GNU Affero General Public License as published   }
{   by the Free Software Foundation, either version 3 of the License, or       }
{   (at your option) any later version.                                        }
{                                                                              }
{   This program is distributed in the hope that it will be useful,            }
{   but WITHOUT ANY WARRANTY; without even the implied warranty of             }
{   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              }
{   GNU Affero General Public License for more details.                        }
{                                                                              }
{   You should have received a copy of the GNU Affero General Public License   }
{   along with this program.  If not, see <https://www.gnu.org/licenses/>      }
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
      client  : IWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt);
    class procedure LpTokenToUnderlyingAmount(
      client  : IWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
    class procedure UnderlyingToLpTokenAmount(
      client  : IWeb3;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncQuantity);
    class procedure UnderlyingToLpTokenAddress(
      client  : IWeb3;
      reserve : TReserve;
      callback: TAsyncAddress);
  public
    class function Name: string; override;
    class function Supports(
      chain  : TChain;
      reserve: TReserve): Boolean; override;
    class procedure APY(
      client  : IWeb3;
      reserve : TReserve;
      period  : TPeriod;
      callback: TAsyncFloat); override;
    class procedure Deposit(
      client  : IWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt); override;
    class procedure Balance(
      client  : IWeb3;
      owner   : TAddress;
      reserve : TReserve;
      callback: TAsyncQuantity); override;
    class procedure Withdraw(
      client  : IWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      callback: TAsyncReceiptEx); override;
    class procedure WithdrawEx(
      client  : IWeb3;
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
    class procedure Create(client: IWeb3; callback: TAsyncRegistry); reintroduce;
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
  web3.eth.yearn.finance.api,
  web3.utils;

{ TyVaultV2 }

class procedure TyVaultV2.Approve(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    reserve.Address(client.Chain, procedure(reserveAddr: TAddress; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(nil, err);
        EXIT;
      end;
      const underlying = TERC20.Create(client, reserveAddr);
      if Assigned(underlying) then
      begin
        underlying.ApproveEx(from, lpTokenAddr, amount, procedure(rcpt: ITxReceipt; err: IError)
        begin
          try
            callback(rcpt, err);
          finally
            underlying.Free;
          end;
        end);
      end;
    end);
  end);
end;

class procedure TyVaultV2.LpTokenToUnderlyingAmount(
  client  : IWeb3;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
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

class procedure TyVaultV2.UnderlyingToLpTokenAmount(
  client  : IWeb3;
  reserve : TReserve;
  amount  : BIgInteger;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
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

class procedure TyVaultV2.UnderlyingToLpTokenAddress(
  client  : IWeb3;
  reserve : TReserve;
  callback: TAsyncAddress);
begin
  reserve.Address(client.Chain, procedure(reserveAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(EMPTY_ADDRESS, err);
      EXIT;
    end;
    // step #1: use the yearn API
    web3.eth.yearn.finance.api.latest(client.Chain, reserveAddr, v2, procedure(const vault: IYearnVault; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(EMPTY_ADDRESS, err);
        EXIT;
      end;
      if Assigned(vault) then
      begin
        callback(vault.Address, err);
        EXIT;
      end;
      // step #2; if the yearn API didn't work, use the on-chain registry
      TyVaultRegistry.Create(client, procedure(reg: TyVaultRegistry; err: IError)
      begin
        if Assigned(reg) then
        try
          reg.LatestVault(reserveAddr, callback);
          EXIT;
        finally
          reg.Free;
        end;
        callback(EMPTY_ADDRESS, err);
      end);
    end);
  end);
end;

class function TyVaultV2.Name: string;
begin
  Result := 'yVault v2';
end;

class function TyVaultV2.Supports(chain: TChain; reserve: TReserve): Boolean;
begin
  Result :=
    (chain = Fantom) and (reserve in [DAI, USDC, USDT])
  or
    (chain = Ethereum) and (reserve in [DAI, USDC, USDT, TUSD]);
end;

class procedure TyVaultV2.APY(
  client  : IWeb3;
  reserve : TReserve;
  period  : TPeriod;
  callback: TAsyncFloat);
begin
  reserve.Address(client.Chain, procedure(reserveAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    // step #1: use the yearn API
    web3.eth.yearn.finance.api.latest(client.Chain, reserveAddr, v2, procedure(const vault: IYearnVault; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(0, err);
        EXIT;
      end;
      if Assigned(vault) then
      begin
        callback(vault.APY, err);
        EXIT;
      end;
      // step #2; if the yearn API didn't work, use the on-chain smart contract
      Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
        if Assigned(yVaultToken) then
        begin
          yVaultToken.APY(period, procedure(apy: Double; err: IError)
          begin
            try
              if Assigned(err)
              or (period = System.Low(TPeriod))
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
    end);
  end);
end;

class procedure TyVaultV2.Deposit(
  client  : IWeb3;
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
    Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(nil, err);
        EXIT;
      end;
      const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
      try
        yVaultToken.Deposit(from, amount, callback);
      finally
        yVaultToken.Free;
      end;
    end);
  end);
end;

class procedure TyVaultV2.Balance(
  client  : IWeb3;
  owner   : TAddress;
  reserve : TReserve;
  callback: TAsyncQuantity);
begin
  Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
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
        Self.LpTokenToUnderlyingAmount(client, reserve, balance, procedure(output: BigInteger; err: IError)
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
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  callback: TAsyncReceiptEx);
begin
  Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, 0, err);
      EXIT;
    end;
    const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
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
            Self.LpTokenToUnderlyingAmount(client, reserve, balance, procedure(output: BigInteger; err: IError)
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
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceiptEx);
begin
  // step #1: from Underlying-amount to yVaultToken-amount
  Self.UnderlyingToLpTokenAmount(client, reserve, amount, procedure(input: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, 0, err);
      EXIT;
    end;
    Self.UnderlyingToLpTokenAddress(client, reserve, procedure(lpTokenAddr: TAddress; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(nil, 0, err);
        EXIT;
      end;
      const yVaultToken = TyVaultToken.Create(client, lpTokenAddr);
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

class procedure TyVaultRegistry.Create(client: IWeb3; callback: TAsyncRegistry);
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
      callback(EMPTY_ADDRESS, err)
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
        callback(price.AsDouble / Power(10, decimals.AsInteger), nil);
    end);
  end);
end;

procedure TyVaultToken.TokenToUnderlying(amount: BigInteger; callback: TAsyncQuantity);
begin
  Self.PricePerShareEx(BLOCK_LATEST, procedure(price: Double; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(BigInteger.Create(amount.AsDouble * price), nil);
  end);
end;

procedure TyVaultToken.UnderlyingToToken(amount: BigInteger; callback: TAsyncQuantity);
begin
  Self.PricePerShareEx(BLOCK_LATEST, procedure(price: Double; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(BigInteger.Create(amount.AsDouble / price), nil);
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
        if IsNaN(currPrice.AsDouble) or IsNaN(pastPrice.AsDouble) then
          callback(NaN, nil)
        else
          callback(period.ToYear((currPrice.AsDouble / pastPrice.AsDouble - 1) * 100), nil);
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
