# Vaultz

Anti-snipe presale/launch vault contracts for [Robinhood Chain](https://docs.robinhood.com/chain)
(Arbitrum Orbit L2 — mainnet chainId `4663`, testnet chainId `46630`). Anyone can permissionlessly
launch a token: a community raise (allowlist round + capped public round) automatically migrates
to a locked Uniswap v3 position on success, or auto-refunds on failure. No admin keys anywhere —
see [`src/`](src) and the trust properties below.

Frontends live in separate repos: [`vaultz-app`](https://github.com/PhronisInc/vaultz-app)
(app.vaultz.io, the actual product) and
[`vaultz-marketing`](https://github.com/PhronisInc/vaultz-marketing) (vaultz.io, the explainer site).

## Trust properties

- **No owner, anywhere.** `VaultFactory`'s platform terms (fee, minimum LP lock) are immutable,
  set once at deployment. Changing them means deploying a new factory, not flipping a switch.
- **Fixed token supply.** Minted once, entirely to the vault, at launch creation. No `mint()`
  exists afterward.
- **Real liquidity lock.** The Uniswap v3 position lands in a dedicated `LPLocker` with a
  platform-enforced minimum duration — nothing, including the creator, can withdraw it early.
- **Non-revocable vesting.** Team allocations vest linearly (with an optional cliff) in
  `TeamVesting`. There's no revoke function.
- **Anti-snipe window that actually expires.** Trading is blocked outright in the exact block
  liquidity goes live, then a per-wallet buy cap applies for a short, hardcoded window — both
  lift automatically, with no admin override to extend them.
- **Automatic refunds.** If a raise misses its softcap by the deadline, contributors pull their
  own ETH back directly; no liquidity is ever created from an under-funded raise.

## Setup

```shell
forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge build
forge test
```

`lib/` isn't committed (dependencies were installed with `--no-git`, as plain vendored copies —
there's no `.gitmodules` to auto-restore from, hence the explicit commands above).

## Deploy

See [`script/DeployFactory.s.sol`](script/DeployFactory.s.sol) and
[`script/DemoLaunch.s.sol`](script/DemoLaunch.s.sol), both env-var driven — copy `.env.example` to
`.env` and fill it in. **Independently re-verify the Uniswap v3 addresses in `.env.example` before
trusting them** (see the comments there for how they were originally verified) — a wrong address
here misdirects real funds.

```shell
forge script script/DeployFactory.s.sol --rpc-url $RH_TESTNET_RPC --broadcast
```

## Status

Unaudited. Contracts + full test suite (56 unit tests + a fork test against the real Uniswap v3
deployment on Robinhood Chain mainnet) are done; a professional security audit is the gate before
any mainnet deployment with real funds. See the repo's issues/roadmap for current status.
