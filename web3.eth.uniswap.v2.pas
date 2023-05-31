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
{******************************************************************************}

unit web3.eth.uniswap.v2;

{$I web3.inc}

interface

uses
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // Delphi
  System.DateUtils,
  System.JSON,
  System.SysUtils,
  // web3
  web3,
  web3.eth,
  web3.eth.abi,
  web3.eth.contract,
  web3.eth.erc20,
  web3.eth.gas,
  web3.eth.types,
  web3.eth.utils,
  web3.graph,
  web3.json,
  web3.utils;

type
  TFactory = class(TCustomContract)
  public
    constructor Create(const aClient: IWeb3); reintroduce;
    procedure GetPair(const tokenA, tokenB: TAddress; const callback: TProc<TAddress, IError>);
  end;

  TRouter02 = class(TCustomContract)
  private
    procedure SwapExactTokensForETH(
      const from        : TPrivateKey;   // Sender of the token.
      const amountIn    : BigInteger;    // The amount of input tokens to send.
      const amountOutMin: BigInteger;    // The minimum amount of output tokens that must be received for the transaction not to revert.
      const token0      : TAddress;      // The address of the pair token with the lower sort order.
      const token1      : TAddress;      // The address of the pair token with the higher sort order.
      const &to         : TAddress;      // Recipient of the ETH.
      const deadline    : TUnixDateTime; // Unix timestamp after which the transaction will revert.
      const callback    : TProc<ITxReceipt, IError>); overload;
    procedure SwapExactETHForTokens(
      const from        : TPrivateKey;   // Sender of ETH.
      const amountIn    : BigInteger;    // The amount of ETH to send.
      const amountOutMin: BigInteger;    // The minimum amount of output tokens that must be received for the transaction not to revert.
      const token       : TAddress;      // The token address.
      const &to         : TAddress;      // Recipient of the output tokens.
      const deadline    : TUnixDateTime; // Unix timestamp after which the transaction will revert.
      const callback    : TProc<ITxReceipt, IError>); overload;
  public
    constructor Create(const aClient: IWeb3); reintroduce;
    procedure WETH(const callback: TProc<TAddress, IError>);
    procedure SwapExactTokensForETH(
      const owner       : TPrivateKey; // Sender of the token, and recipient of the ETH.
      const amountIn    : BigInteger;  // The amount of input tokens to send.
      const amountOutMin: BigInteger;  // The minimum amount of output tokens that must be received for the transaction not to revert.
      const token       : TAddress;    // The address of the token you wish to swap.
      const minutes     : Int64;       // Your transaction will revert if it is pending for more than this long.
      const callback    : TProc<ITxReceipt, IError>); overload;
    procedure SwapExactETHForTokens(
      const owner       : TPrivateKey; // Sender of ETH.
      const amountIn    : BigInteger;  // The amount of ETH to send.
      const amountOutMin: BigInteger;  // The minimum amount of output tokens that must be received for the transaction not to revert.
      const token       : TAddress;    // The token address.
      const minutes     : Int64;       // Your transaction will revert if it is pending for more than this long.
      const callback    : TProc<ITxReceipt, IError>); overload;
  end;

  TPair = class(TERC20)
  protected
    function  Query  (const field: string): string;
    procedure Execute(const field: string; const callback: TProc<Double, IError>);
  public
    procedure Token0(const callback: TProc<TAddress, IError>);
    procedure Token1(const callback: TProc<TAddress, IError>);
    procedure Token0Price(const callback: TProc<Double, IError>);
    procedure Token1Price(const callback: TProc<Double, IError>);
  end;

implementation

{ TFactory }

constructor TFactory.Create(const aClient: IWeb3);
begin
  inherited Create(aClient, '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f');
end;

// Returns the address of the pair for tokenA and tokenB, if it has been created, else 0x0
procedure TFactory.GetPair(const tokenA, tokenB: TAddress; const callback: TProc<TAddress, IError>);
begin
  call(Client, Contract, 'getPair(address,address)', [tokenA, tokenB], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(TAddress.Zero, err);
      EXIT;
    end;
    const pair = TAddress.Create(hex);
    if pair.IsZero then
    begin
      callback(TAddress.Zero, TError.Create('%s does not exist', [tokenA]));
      EXIT;
    end;
    callback(pair, nil)
  end);
end;

{ TRouter02 }

constructor TRouter02.Create(const aClient: IWeb3);
begin
  inherited Create(aClient, '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D');
end;

// Returns the canonical WETH address; see https://blog.0xproject.com/canonical-weth-a9aa7d0279dd
procedure TRouter02.WETH(const callback: TProc<TAddress, IError>);
begin
  call(Client, Contract, 'WETH()', [], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(TAddress.Zero, err)
    else
      callback(TAddress.Create(hex), nil);
  end);
end;

// Swaps an exact amount of tokens for as much ETH as possible.
procedure TRouter02.SwapExactTokensForETH(
  const from        : TPrivateKey;   // Sender of the token.
  const amountIn    : BigInteger;    // The amount of input tokens to send.
  const amountOutMin: BigInteger;    // The minimum amount of output tokens that must be received for the transaction not to revert.
  const token0      : TAddress;      // The address of the pair token with the lower sort order.
  const token1      : TAddress;      // The address of the pair token with the higher sort order.
  const &to         : TAddress;      // Recipient of the ETH.
  const deadline    : TUnixDateTime; // Unix timestamp after which the transaction will revert.
  const callback    : TProc<ITxReceipt, IError>);
begin
  web3.eth.erc20.approve(web3.eth.erc20.create(Self.Client, token0), from, Self.Contract, amountIn, procedure(rcpt: ITxReceipt; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      web3.eth.write(Client, from, Contract,
        'swapExactTokensForETH(uint256,uint256,address[],address,uint256)',
        [
          web3.utils.toHex(amountIn),
          web3.utils.toHex(amountOutMin),
          &array([token0, token1]),
          &to,
          deadline
        ], callback);
  end);
end;

procedure TRouter02.SwapExactETHForTokens(
  const from        : TPrivateKey;   // Sender of ETH.
  const amountIn    : BigInteger;    // The amount of ETH to send.
  const amountOutMin: BigInteger;    // The minimum amount of output tokens that must be received for the transaction not to revert.
  const token       : TAddress;      // The token address.
  const &to         : TAddress;      // Recipient of the output tokens.
  const deadline    : TUnixDateTime; // Unix timestamp after which the transaction will revert.
  const callback    : TProc<ITxReceipt, IError>);
begin
  Self.WETH(procedure(WETH: TAddress; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      web3.eth.write(Client, from, Contract, amountIn,
        'swapExactETHForTokens(uint256,address[],address,uint256)',
        [
          web3.utils.toHex(amountOutMin),
          &array([WETH, token]),
          &to,
          deadline
        ], callback);
  end);
end;

// Swaps an exact amount of tokens for as much ETH as possible.
procedure TRouter02.SwapExactTokensForETH(
  const owner       : TPrivateKey; // Sender of the token, and recipient of the ETH.
  const amountIn    : BigInteger;  // The amount of input tokens to send.
  const amountOutMin: BigInteger;  // The minimum amount of output tokens that must be received for the transaction not to revert.
  const token       : TAddress;    // The address of the token you wish to swap.
  const minutes     : Int64;       // Your transaction will revert if it is pending for more than this long.
  const callback    : TProc<ITxReceipt, IError>);
begin
  owner.GetAddress
    .ifErr(procedure(err: IError)
    begin
      callback(nil, err)
    end)
    .&else(procedure(receiver: TAddress)
    begin
      Self.WETH(procedure(WETH: TAddress; err: IError)
      begin
        if Assigned(err) then
          callback(nil, err)
        else
          Self.SwapExactTokensForETH(
            owner,
            amountIn,
            amountOutMin,
            token,
            WETH,
            receiver,
            DateTimeToUnix(IncMinute(System.SysUtils.Now, minutes), False),
            callback
          )
      end);
    end);
end;

procedure TRouter02.SwapExactETHForTokens(
  const owner       : TPrivateKey; // Sender of ETH.
  const amountIn    : BigInteger;  // The amount of ETH to send.
  const amountOutMin: BigInteger;  // The minimum amount of output tokens that must be received for the transaction not to revert.
  const token       : TAddress;    // The token address.
  const minutes     : Int64;       // Your transaction will revert if it is pending for more than this long.
  const callback    : TProc<ITxReceipt, IError>);
begin
  owner.GetAddress
    .ifErr(procedure(err: IError)
    begin
      callback(nil, err)
    end)
    .&else(procedure(receiver: TAddress)
    begin
      Self.SwapExactETHForTokens(
        owner,
        amountIn,
        amountOutMin,
        token,
        receiver,
        DateTimeToUnix(IncMinute(System.SysUtils.Now, minutes), False),
        callback
      )
    end);
end;

{ TPair }

// Returns the address of the pair token with the lower sort order.
procedure TPair.Token0(const callback: TProc<TAddress, IError>);
begin
  call(Client, Contract, 'token0()', [], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(TAddress.Zero, err)
    else
      callback(TAddress.Create(hex), nil);
  end);
end;

// Returns the address of the pair token with the higher sort order.
procedure TPair.Token1(const callback: TProc<TAddress, IError>);
begin
  call(Client, Contract, 'token1()', [], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(TAddress.Zero, err)
    else
      callback(TAddress.Create(hex), nil);
  end);
end;

// Returns a GraphQL query; see https://uniswap.org/docs/v2/API/entities/#pair
function TPair.Query(const field: string): string;
begin
  Result := Format('{"query":"{pair(id:\"%s\"){%s}}"}', [string(Contract).ToLower, field]);
end;

// Execute a GraphQL query, return the result as a float (if any)
procedure TPair.Execute(const field: string; const callback: TProc<Double, IError>);
begin
  web3.graph.execute('https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v2', Query(field), procedure(response: TJsonObject; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(0, err);
      EXIT;
    end;
    const data = web3.json.getPropAsObj(response, 'data');
    if Assigned(data) then
    begin
      const pair = web3.json.getPropAsObj(data, 'pair');
      if Assigned(pair) then
      begin
        callback(DotToFloat(web3.json.getPropAsStr(pair, field)), nil);
        EXIT;
      end;
    end;
    callback(0, TGraphError.Create('an unknown error occurred'));
  end);
end;

// Token0 per Token1
procedure TPair.Token0Price(const callback: TProc<Double, IError>);
begin
  Execute('token0Price', callback);
end;

// Token1 per Token0
procedure TPair.Token1Price(const callback: TProc<Double, IError>);
begin
  Execute('token1Price', callback);
end;

end.
