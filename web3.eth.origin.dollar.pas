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

unit web3.eth.origin.dollar;

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
  TOrigin = class(TLendingProtocol)
  protected
    class procedure Approve(
      client  : IWeb3;
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt);
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
      _reserve: TReserve;
      amount  : BigInteger;
      callback: TAsyncReceiptEx); override;
  end;

type
  TOriginVault = class(TCustomContract)
  public
    constructor Create(aClient: IWeb3); reintroduce;
    class function DeployedAt: TAddress;
    procedure Mint(
      from    : TPrivateKey;
      reserve : TReserve;
      amount  : BigInteger;
      callback: TAsyncReceipt);
    procedure Redeem(
      from    : TPrivateKey;
      amount  : BigInteger;
      callback: TAsyncReceipt);
  end;

type
  TOriginDollar = class(TERC20)
  public
    constructor Create(aClient: IWeb3); reintroduce;
    procedure RebasingCreditsPerToken(const block: string; callback: TAsyncQuantity);
    procedure APY(period: TPeriod; callback: TAsyncFloat);
  end;

implementation

uses
  // web3
  web3.eth,
  web3.eth.etherscan,
  web3.utils;

{ TOrigin }

class procedure TOrigin.Approve(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
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
      underlying.ApproveEx(from, TOriginVault.DeployedAt, amount, procedure(rcpt: ITxReceipt; err: IError)
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

class function TOrigin.Name: string;
begin
  Result := 'Origin';
end;

class function TOrigin.Supports(chain: TChain; reserve: TReserve): Boolean;
begin
  Result := (chain = Ethereum) and (reserve = USDC);
end;

class procedure TOrigin.APY(
  client  : IWeb3;
  _reserve: TReserve;
  period  : TPeriod;
  callback: TAsyncFloat);
begin
  const ousd = TOriginDollar.Create(client);
  if Assigned(ousd) then
  begin
    ousd.APY(period, procedure(apy: Double; err: IError)
    begin
      try
        callback(apy, err);
      finally
        ousd.Free;
      end;
    end);
  end;
end;

class procedure TOrigin.Deposit(
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
    const vault = TOriginVault.Create(client);
    try
      vault.Mint(from, reserve, amount, callback);
    finally
      vault.Free;
    end;
  end);
end;

class procedure TOrigin.Balance(
  client  : IWeb3;
  owner   : TAddress;
  reserve : TReserve;
  callback: TAsyncQuantity);
begin
  const ousd = TOriginDollar.Create(client);
  try
    ousd.BalanceOf(owner, procedure(balance: BigInteger; err: IError)
    begin
      if Assigned(err) then
        callback(balance, err)
      else
        if reserve.Decimals = 1e18 then
          callback(balance, err)
        else
          callback(reserve.Scale(balance.AsDouble / 1e18), err);
    end);
  finally
    ousd.Free;
  end;
end;

class procedure TOrigin.Withdraw(
  client  : IWeb3;
  from    : TPrivateKey;
  reserve : TReserve;
  callback: TAsyncReceiptEx);
begin
  Self.Balance(client, from, reserve, procedure(balance: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(nil, 0, err)
    else
      Self.WithdrawEx(client, from, reserve, balance, callback);
  end)
end;

class procedure TOrigin.WithdrawEx(
  client  : IWeb3;
  from    : TPrivateKey;
  _reserve: TReserve;
  amount  : BigInteger;
  callback: TAsyncReceiptEx);
begin
  const vault = TOriginVault.Create(client);
  try
    vault.Redeem(from, amount, procedure(rcpt: ITxReceipt; err: IError)
    begin
      if Assigned(err) then
        callback(nil, 0, err)
      else
        callback(rcpt, amount, err);
    end);
  finally
    vault.Free;
  end;
end;

{ TOriginVault }

constructor TOriginVault.Create(aClient: IWeb3);
begin
  inherited Create(aClient, Self.DeployedAt);
end;

class function TOriginVault.DeployedAt: TAddress;
begin
  Result := '0xe75d77b1865ae93c7eaa3040b038d7aa7bc02f70';
end;

procedure TOriginVault.Mint(
  from    : TPrivateKey;
  reserve : TReserve;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  reserve.Address(Client.Chain, procedure(reserveAddr: TAddress; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      web3.eth.write(
        Client,
        from,
        Contract,
        'mint(address,uint256,uint256)',
        [
          reserveAddr,
          web3.utils.toHex(amount),
          0
        ],
        callback
      );
  end);
end;

procedure TOriginVault.Redeem(
  from    : TPrivateKey;
  amount  : BigInteger;
  callback: TAsyncReceipt);
begin
  web3.eth.write(
    Client,
    from,
    Contract,
    'redeem(uint256,uint256)',
    [
      web3.utils.toHex(amount),
      0
    ],
    callback
  );
end;

{ TOriginDollar }

constructor TOriginDollar.Create(aClient: IWeb3);
begin
  inherited Create(aClient, '0x2A8e1E676Ec238d8A992307B495b45B3fEAa5e86');
end;

procedure TOriginDollar.RebasingCreditsPerToken(const block: string; callback: TAsyncQuantity);
begin
  web3.eth.call(Client, Contract, 'rebasingCreditsPerToken()', block, [], callback);
end;

procedure TOriginDollar.APY(period: TPeriod; callback: TAsyncFloat);
begin
  Self.RebasingCreditsPerToken(BLOCK_LATEST, procedure(curr: BigInteger; err: IError)
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
      Self.RebasingCreditsPerToken(web3.utils.toHex(bn), procedure(past: BigInteger; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(0, err);
          EXIT;
        end;
        callback(period.ToYear((1 / curr.AsDouble) / (1 / past.AsDouble) - 1) * 100, nil);
      end);
    end);
  end);
end;

end.
