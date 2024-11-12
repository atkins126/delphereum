{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2020 Stefan van As <svanas@runbox.com>              }
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
{        need tokens to test with?                                             }
{        1. make sure your wallet is set to the relevant testnet               }
{        2. go to https://app.compound.finance                                 }
{        3. click an asset, then withdraw, and there will be a faucet button   }
{                                                                              }
{******************************************************************************}

unit web3.eth.compound;

{$I web3.inc}

interface

uses
  // Delphi
  System.SysUtils,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth,
  web3.eth.defi,
  web3.eth.erc20,
  web3.eth.etherscan,
  web3.eth.logs,
  web3.eth.types,
  web3.utils;

type
  TCompound = class(TLendingProtocol)
  protected
    class procedure Approve(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, IError>);
  public
    class function Name: string; override;
    class function Supports(
      const chain  : TChain;
      const reserve: TReserve): Boolean; override;
    class procedure APY(
      const client   : IWeb3;
      const etherscan: IEtherscan;
      const reserve  : TReserve;
      const period   : TPeriod;
      const callback : TProc<Double, IError>); override;
    class procedure Deposit(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, IError>); override;
    class procedure Balance(
      const client  : IWeb3;
      const owner   : TAddress;
      const reserve : TReserve;
      const callback: TProc<BigInteger, IError>); override;
    class procedure Withdraw(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const callback: TProc<ITxReceipt, BigInteger, IError>); override;
    class procedure WithdrawEx(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, BigInteger, IError>); override;
  end;

  TOnMint = reference to procedure(
    Sender  : TObject;
    Minter  : TAddress;
    Amount  : BigInteger;
    Tokens  : BigInteger);
  TOnRedeem = reference to procedure(
    Sender  : TObject;
    Redeemer: TAddress;
    Amount  : BigInteger;
    Tokens  : BigInteger);

  IcToken = interface(IERC20)
    //------- read from contract -----------------------------------------------
    procedure APY(const callback: TProc<BigInteger, IError>);
    procedure BalanceOfUnderlying(const owner: TAddress; const callback: TProc<BigInteger, IError>);
    procedure ExchangeRateCurrent(const callback: TProc<BigInteger, IError>);
    procedure SupplyRatePerBlock(const callback: TProc<BigInteger, IError>);
    procedure Underlying(const callback: TProc<TAddress, IError>);
    //------- write to contract ------------------------------------------------
    procedure Mint(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    procedure Redeem(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    procedure RedeemUnderlying(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    //------- https://compound.finance/docs/ctokens#ctoken-events --------------
    function SetOnMint(const Value: TOnMint): IcToken;
    function SetOnRedeem(const Value: TOnRedeem): IcToken;
  end;

const
  NO_ERROR                       = 0;
  UNAUTHORIZED                   = 1;  // The sender is not authorized to perform this action.
  BAD_INPUT                      = 2;  // An invalid argument was supplied by the caller.
  COMPTROLLER_REJECTION          = 3;  // The action would violate the comptroller policy.
  COMPTROLLER_CALCULATION_ERROR  = 4;  // An internal calculation has failed in the comptroller.
  INTEREST_RATE_MODEL_ERROR      = 5;  // The interest rate model returned an invalid value.
  INVALID_ACCOUNT_PAIR           = 6;  // The specified combination of accounts is invalid.
  INVALID_CLOSE_AMOUNT_REQUESTED = 7;  // The amount to liquidate is invalid.
  INVALID_COLLATERAL_FACTOR      = 8;  // The collateral factor is invalid.
  MATH_ERROR                     = 9;  // A math calculation error occurred.
  MARKET_NOT_FRESH               = 10; // Interest has not been properly accrued.
  MARKET_NOT_LISTED              = 11; // The market is not currently listed by its comptroller.
  TOKEN_INSUFFICIENT_ALLOWANCE   = 12; // ERC-20 contract must *allow* Money Market contract to call `transferFrom`. The current allowance is either 0 or less than the requested supply, repayBorrow or liquidate amount.
  TOKEN_INSUFFICIENT_BALANCE     = 13; // Caller does not have sufficient balance in the ERC-20 contract to complete the desired action.
  TOKEN_INSUFFICIENT_CASH        = 14; // The market does not have a sufficient cash balance to complete the transaction. You may attempt this transaction again later.
  TOKEN_TRANSFER_IN_FAILED       = 15; // Failure in ERC-20 when transfering token into the market.
  TOKEN_TRANSFER_OUT_FAILED      = 16; // Failure in ERC-20 when transfering token out of the market.

implementation

{ TcToken }

type
  TcToken = class(TERC20, IcToken)
  strict private
    FOnMint  : TOnMint;
    FOnRedeem: TOnRedeem;
  protected
    function  ListenForLatestBlock: Boolean; override;
    procedure OnLatestBlockMined(log: PLog; err: IError); override;
  public
    //------- read from contract -----------------------------------------------
    procedure APY(const callback: TProc<BigInteger, IError>);
    procedure BalanceOfUnderlying(const owner: TAddress; const callback: TProc<BigInteger, IError>);
    procedure ExchangeRateCurrent(const callback: TProc<BigInteger, IError>);
    procedure SupplyRatePerBlock(const callback: TProc<BigInteger, IError>);
    procedure Underlying(const callback: TProc<TAddress, IError>);
    //------- write to contract ------------------------------------------------
    procedure Mint(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    procedure Redeem(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    procedure RedeemUnderlying(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
    //------- https://compound.finance/docs/ctokens#ctoken-events --------------
    function SetOnMint(const Value: TOnMint): IcToken;
    function SetOnRedeem(const Value: TOnRedeem): IcToken;
  end;

function cDAI(const aClient: IWeb3): IcToken;
begin
  // https://compound.finance/docs#networks
  Result := TcToken.Create(aClient, '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643');
end;

function cUSDC(const aClient: IWeb3): IcToken;
begin
  // https://compound.finance/docs#networks
  Result := TcToken.Create(aClient, '0x39aa39c021dfbae8fac545936693ac917d5e7563');
end;

function cUSDT(const aClient: IWeb3): IcToken;
begin
  // https://compound.finance/docs#networks
  Result := TcToken.Create(aClient, '0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9');
end;

function cTUSD(const aClient: IWeb3): IcToken;
begin
  // https://compound.finance/docs#networks
  Result := TcToken.Create(aClient, '0x12392f67bdf24fae0af363c24ac620a2f67dad86');
end;

function cToken(const aClient: IWeb3; const aReserve: TReserve): IResult<IcToken>;
begin
  case aReserve of
    DAI : Result := TResult<IcToken>.Ok(cDAI(aClient));
    USDC: Result := TResult<IcToken>.Ok(cUSDC(aClient));
    USDT: Result := TResult<IcToken>.Ok(cUSDT(aClient));
    TUSD: Result := TResult<IcToken>.Ok(cTUSD(aClient));
  else
    Result := TResult<IcToken>.Err(TError.Create('%s not supported', [aReserve.Symbol]));
  end;
end;

{ TCompound }

// Approve the cToken contract to move your underlying asset.
class procedure TCompound.Approve(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, IError>);
begin
  cToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(nil, err)
    end)
    .&else(procedure(cToken: IcToken)
    begin
      cToken.Underlying(procedure(address: TAddress; err: IError)
      begin
        if Assigned(err) then
          callback(nil, err)
        else
          web3.eth.erc20.approve(web3.eth.erc20.create(client, address), from, cToken.Contract, amount, callback);
      end);
    end);
end;

class function TCompound.Name: string;
begin
  Result := 'Compound v2';
end;

class function TCompound.Supports(const chain: TChain; const reserve: TReserve): Boolean;
begin
  Result := (reserve in [USDT, TUSD, DAI, USDC]) and (chain = Ethereum);
end;

// Returns the annual yield as a percentage with 4 decimals.
class procedure TCompound.APY(
  const client   : IWeb3;
  const etherscan: IEtherscan;
  const reserve  : TReserve;
  const period   : TPeriod;
  const callback : TProc<Double, IError>);
begin
  cToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(cToken: IcToken)
    begin
      cToken.APY(procedure(value: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          callback(BigInteger.Divide(value, BigInteger.Create(1e12)).AsInt64 / 1e4, nil);
      end);
    end);
end;

// Deposits an underlying asset into the lending pool.
class procedure TCompound.Deposit(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, IError>);
begin
  // Before supplying an asset, we must first approve the cToken.
  Approve(client, from, reserve, amount, procedure(rcpt: ITxReceipt; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      cToken(client, reserve)
        .ifErr(procedure(err: IError)
        begin
          callback(nil, err)
        end)
        .&else(procedure(cToken: IcToken)
        begin
          cToken.Mint(from, amount, callback)
        end);
  end);
end;

// Returns how much underlying assets you are entitled to.
class procedure TCompound.Balance(
  const client  : IWeb3;
  const owner   : TAddress;
  const reserve : TReserve;
  const callback: TProc<BigInteger, IError>);
begin
  cToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(cToken: IcToken)
    begin
      cToken.BalanceOfUnderlying(owner, callback)
    end);
end;

// Redeems your balance of cTokens for the underlying asset.
class procedure TCompound.Withdraw(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const callback: TProc<ITxReceipt, BigInteger, IError>);
begin
  from.GetAddress
    .ifErr(procedure(err: IError)
    begin
      callback(nil, 0, err)
    end)
    .&else(procedure(owner: TAddress)
    begin
      Balance(client, owner, reserve, procedure(underlyingAmount: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(nil, 0, err)
        else
          cToken(client, reserve)
            .ifErr(procedure(err: IError)
            begin
              callback(nil, 0, err)
            end)
            .&else(procedure(cToken: IcToken)
            begin
              cToken.BalanceOf(owner, procedure(cTokenAmount: BigInteger; err: IError)
              begin
                if Assigned(err) then
                  callback(nil, 0, err)
                else
                  cToken.Redeem(from, cTokenAmount, procedure(rcpt: ITxReceipt; err: IError)
                  begin
                    if Assigned(err) then
                      callback(nil, 0, err)
                    else
                      callback(rcpt, underlyingAmount, err);
                  end);
              end);
            end);
      end);
    end);
end;

class procedure TCompound.WithdrawEx(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, BigInteger, IError>);
begin
  cToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(nil, 0, err)
    end)
    .&else(procedure(cToken: IcToken)
    begin
      cToken.RedeemUnderlying(from, amount, procedure(rcpt: ITxReceipt; err: IError)
      begin
        if Assigned(err) then
          callback(nil, 0, err)
        else
          callback(rcpt, amount, err);
      end);
    end);
end;

{ TcToken }

function TcToken.ListenForLatestBlock: Boolean;
begin
  Result := inherited ListenForLatestBlock or Assigned(FOnMint) or Assigned(FOnRedeem);
end;

procedure TcToken.OnLatestBlockMined(log: PLog; err: IError);
begin
  inherited OnLatestBlockMined(log, err);

  if not Assigned(log) then
    EXIT;

  if Assigned(FOnMint) then
    if log^.isEvent('Mint(address,uint256,uint256)') then
      // emitted upon a successful Mint
      FOnMint(Self,
              log^.Topic[1].toAddress, // minter
              log^.Data[0].toUInt256,  // amount
              log^.Data[1].toUInt256); // tokens

  if Assigned(FOnRedeem) then
    if log^.isEvent('Redeem(address,uint256,uint256)') then
      // emitted upon a successful Redeem
      FOnRedeem(Self,
                log^.Topic[1].toAddress, // redeemer
                log^.Data[0].toUInt256,  // amount
                log^.Data[1].toUInt256); // tokens
end;

function TcToken.SetOnMint(const Value: TOnMint): IcToken;
begin
  Result := Self;
  FOnMint := Value;
  EventChanged;
end;

function TcToken.SetOnRedeem(const Value: TOnRedeem): IcToken;
begin
  Result := Self;
  FOnRedeem := Value;
  EventChanged;
end;

// returns the annual percentage yield for this cToken, scaled by 1e18
procedure TcToken.APY(const callback: TProc<BigInteger, IError>);
begin
  SupplyRatePerBlock(procedure(qty: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(BigInteger.Zero, err)
    else
      callback(
        BigInteger.Create(
          (((qty.AsInt64 / 1e18) * (BLOCKS_PER_DAY + 1)) * (365 - 1)) * 1e18
        ),
        nil
      );
  end);
end;

// returns how much underlying ERC20 tokens your cToken balance entitles you to.
procedure TcToken.BalanceOfUnderlying(const owner: TAddress; const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'balanceOfUnderlying(address)', [owner], callback);
end;

// returns the current exchange rate of cToken to underlying ERC20 token, scaled by 1e18
// please note that the exchange rate of underlying to cToken increases over time.
procedure TcToken.ExchangeRateCurrent(const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'exchangeRateCurrent()', [], procedure(qty: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(BigInteger.Zero, err)
    else
      callback(qty, nil);
  end);
end;

// supply ERC20 tokens to the protocol, and receive interest earning cTokens back.
// the cTokens are transferred to the wallet of the supplier.
// please note you needs to first call the approve function on the underlying token's contract.
// returns a receipt on success, otherwise https://compound.finance/docs/ctokens#ctoken-error-codes
procedure TcToken.Mint(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
begin
  web3.eth.write(Client, from, Contract, 'mint(uint256)', [web3.utils.toHex(amount)], callback);
end;

// redeems specified amount of cTokens in exchange for the underlying ERC20 tokens.
// the ERC20 tokens are transferred to the wallet of the supplier.
// returns a receipt on success, otherwise https://compound.finance/docs/ctokens#ctoken-error-codes
procedure TcToken.Redeem(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
begin
  web3.eth.write(Client, from, Contract, 'redeem(uint256)', [web3.utils.toHex(amount)], callback);
end;

// redeems cTokens in exchange for the specified amount of underlying ERC20 tokens.
// the ERC20 tokens are transferred to the wallet of the supplier.
// returns a receipt on success, otherwise https://compound.finance/docs/ctokens#ctoken-error-codes
procedure TcToken.RedeemUnderlying(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
begin
  web3.eth.write(Client, from, Contract, 'redeemUnderlying(uint256)', [web3.utils.toHex(amount)], callback);
end;

// returns the current per-block supply interest rate for this cToken, scaled by 1e18
procedure TcToken.SupplyRatePerBlock(const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'supplyRatePerBlock()', [], procedure(qty: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(BigInteger.Zero, err)
    else
      callback(qty, nil);
  end);
end;

// Returns the underlying asset contract address for this cToken.
procedure TcToken.Underlying(const callback: TProc<TAddress, IError>);
begin
  web3.eth.call(Client, Contract, 'underlying()', [], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(TAddress.Zero, err)
    else
      callback(TAddress.Create(hex), nil);
  end);
end;

end.
