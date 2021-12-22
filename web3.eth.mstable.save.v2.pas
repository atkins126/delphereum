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

unit web3.eth.mstable.save.v2;

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
  TmStable = class(TLendingProtocol)
  public
    class function Name: string; override;
    class function Supports(
      chain  : TChain;
      reserve: TReserve): Boolean; override;
    class procedure APY(
      client  : IWeb3;
      _reserve: TReserve;
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
      _reserve: TReserve;
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
  TimUSD = class(TERC20)
  public
    constructor Create(aClient: IWeb3); reintroduce;
    procedure APY(period: TPeriod; callback: TAsyncFloat);
    procedure BalanceOfUnderlying(owner: TAddress; callback: TAsyncQuantity);
    procedure ExchangeRate(const block: string; callback: TAsyncQuantity);
    procedure CreditsToUnderlying(credits: BigInteger; callback: TAsyncQuantity);
  end;

type
  TimVaultUSD = class(TCustomContract)
  public
    constructor Create(aClient: IWeb3); reintroduce;
    procedure BalanceOf(owner: TAddress; callback: TAsyncQuantity);
  end;

implementation

uses
  // web3
  web3.eth,
  web3.eth.etherscan,
  web3.utils;

{ TmStable }

class function TmStable.Name: string;
begin
  Result := 'mStable';
end;

class function TmStable.Supports(chain: TChain; reserve: TReserve): Boolean;
begin
  Result := (chain = Mainnet) and (reserve = MUSD);
end;

class procedure TmStable.APY(
  client  : IWeb3;
  _reserve: TReserve;
  period  : TPeriod;
  callback: TAsyncFloat);
begin
  var imUSD := TimUSD.Create(client);
  if Assigned(imUSD) then
  begin
    imUSD.APY(period, procedure(apy: Double; err: IError)
    begin
      try
        callback(apy, err);
      finally
        imUSD.Free;
      end;
    end);
  end;
end;

class procedure TmStable.Deposit(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  callback(nil, TNotImplemented.Create);
end;

class procedure TmStable.Balance(
  client  : IWeb3;
  owner   : TAddress;
  _reserve: TReserve;
  callback: TAsyncQuantity);
begin
  var imUSD := TimUSD.Create(client);
  imUSD.BalanceOfUnderlying(owner, procedure(balance1: BigInteger; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    var vault := TImVaultUSD.Create(client);
    vault.BalanceOf(owner, procedure(qty: BigInteger; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(0, err);
        EXIT;
      end;
      imUSD.CreditsToUnderlying(qty, procedure(balance2: BigInteger; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        callback(balance1 + balance2, nil);
      end);
    end);
  end);
end;

class procedure TmStable.Withdraw(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  callback: TAsyncReceiptEx);
begin
  callback(nil, 0, TNotImplemented.Create);
end;

class procedure TmStable.WithdrawEx(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceiptEx);
begin
  callback(nil, 0, TNotImplemented.Create);
end;

{ TimUSD }

constructor TimUSD.Create(aClient: IWeb3);
begin
  inherited Create(aClient, '0x30647a72dc82d7fbb1123ea74716ab8a317eac19');
end;

procedure TimUSD.APY(period: TPeriod; callback: TAsyncFloat);
begin
  Self.ExchangeRate(BLOCK_LATEST, procedure(curr: BigInteger; err: IError)
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
      Self.ExchangeRate(web3.utils.toHex(bn), procedure(past: BigInteger; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        callback(period.ToYear(curr.AsDouble / past.AsDouble - 1) * 100, nil);
      end);
    end);
  end);
end;

procedure TimUSD.BalanceOfUnderlying(owner: TAddress; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'balanceOfUnderlying(address)', [owner], callback);
end;

procedure TimUSD.ExchangeRate(const block: string; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'exchangeRate()', block, [], callback);
end;

procedure TimUSD.CreditsToUnderlying(credits: BigInteger; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'creditsToUnderlying(uint256)', [web3.utils.toHex(credits)], callback);
end;

{ TimVaultUSD }

constructor TimVaultUSD.Create(aClient: IWeb3);
begin
  inherited Create(aClient, '0x78BefCa7de27d07DC6e71da295Cc2946681A6c7B');
end;

procedure TimVaultUSD.BalanceOf(owner: TAddress; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'balanceOf(address)', [owner], callback);
end;

end.
