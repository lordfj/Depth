
**Depth** is a Clarity smart contract implementing a **market maker protocol** for decentralized asset exchange and liquidity provisioning.  
It enables participants to create markets, provide and redeem liquidity, and perform asset swaps with built-in price discovery and execution tracking.

---

## Features

- **Market Creation** — Deploy a new market between a base asset (STX) and a quote asset (SIP-010 token).
- **Liquidity Provisioning** — Add liquidity to the pool and receive market share tokens representing your ownership.
- **Liquidity Redemption** — Withdraw your proportional share of the market reserves.
- **Price Discovery** — Automated constant product market maker with a 0.3% trading fee.
- **Order Execution** — Buy or sell the base asset using the quote asset with slippage protection.
- **Execution Logs** — On-chain record of every market operation for transparency.
- **Participant Position Tracking** — Query individual holdings and market depth.

---

## Contract Architecture

- **Market State**
  - `base-asset-balance` — STX reserve.
  - `quote-asset-balance` — SIP-010 token reserve.
  - `market-share-tokens` — Total supply of liquidity shares.
  - `market-active` — Boolean indicating whether the market is live.
  - `quote-asset-contract` — Principal of the quote token contract.

- **Maps**
  - `participant-holdings` — Tracks liquidity share ownership.
  - `execution-log` — Records all market buy/sell operations.

- **Core Functions**
  - `create-market` — Initialize a market with initial deposits.
  - `provide-liquidity` — Deposit STX and tokens in proportion to pool reserves.
  - `redeem-liquidity` — Burn liquidity shares to withdraw STX and tokens.
  - `market-sell-base` — Sell STX for quote tokens.
  - `market-buy-base` — Sell quote tokens for STX.
  - `price-quote` / `reverse-price-quote` — Calculate swap outcomes.

---

## Price Formula

Depth uses a **constant product** AMM with fee adjustment:

```

output\_amount = (input\_amount \* 997 \* reserve\_out) / (reserve\_in \* 1000 + input\_amount \* 997)

```

Where:
- `997` = 1000 - 0.3% fee
- `reserve_in` and `reserve_out` are the pool reserves before the trade.

---

## Usage

1. **Deploy the Contract**
   - Set the `asset-interface` to the quote token's SIP-010 contract.
   - Fund with STX and quote tokens.

2. **Add Liquidity**
   - Provide both STX and tokens in proportion to existing reserves.
   - Receive shares representing your market position.

3. **Swap**
   - Use `market-sell-base` to sell STX for tokens.
   - Use `market-buy-base` to sell tokens for STX.
   - Protect against price impact with `min-quote-receive` or `min-base-receive`.

4. **Withdraw Liquidity**
   - Redeem your shares to receive your proportional reserves.

---

## Errors

- `u300` — Access denied.
- `u301` — Low reserves.
- `u302` — Invalid order.
- `u303` — Price impact too high.
- `u304` — Wrong asset type.
- `u305` — Execution failed.
- `u306` — Market already exists.
- `u307` — No active market.

