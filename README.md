# Stabilis

Stabilis is a decentralized protocol that allows AR holders to obtain maximum liquidity against their collateral without paying interest. After locking up AR as collateral in a process (smart contract) and creating an individual position called a "vault", the user can get instant liquidity by minting USDar, a USD-pegged stablecoin. Each vault is required to be collateralized at a minimum of 110%. Any owner of USDar can redeem their stablecoins for the underlying collateral at any time. The redemption mechanism along with algorithmically adjusted fees guarantee a minimum stablecoin value of USD 1.

An unprecedented liquidation mechanism based on incentivized stability deposits and a redistribution cycle from riskier to safer vaults provides stability at a much lower collateral ratio than current systems. Stability is maintained via economically-driven user interactions and arbitrage, rather than by active governance or monetary interventions.

The protocol has built-in incentives that encourage both early adoption and the operation of multiple front ends, enhancing decentralization.

## Overview

Stabilis is a collateralized debt platform. Users can lock up Arweave, and issue stablecoin tokens (USDar) to their own Arweave address, and subsequently transfer those tokens to any other Arweave address. The individual collateralized debt positions are called Vaults.

The stablecoin tokens are economically geared towards maintaining value of 1 USDar = $1 USD, due to the following properties:

1. The system is designed to always be over-collateralized - the dollar value of the locked Arweave exceeds the dollar value of the issued stablecoins

2. The stablecoins are fully redeemable - users can always swap $x worth of USDar for $x worth of AR (minus fees), directly with the system.

3. The system algorithmically controls the generation of USDar through a variable issuance fee.

After opening a Vault with some Arweave, users may issue ("borrow") tokens such that the collateralization ratio of their Vault remains above 110%. A user with $1000 worth of AR in a Vault can issue up to 909.09 USDar.

The tokens are freely exchangeable - anyone with an Arweave address can send or receive USDar tokens, whether they have an open Vault or not. The tokens are burned upon repayment of a Vault's debt.

The Stabilis system regularly updates the AR:USD price via http outcalls to CMC and CG. When a Vault falls below a minimum collateralization ratio (MCR) of 110%, it is considered under-collateralized, and is automatically liquidated.

## Deploy it

In order to deploy this project, open 3 different `aos` processes on 3 different terminals.

First deploy the collateral token process and the stablecoin token process.

Then edit the `protocol.lua` files first lines to use the processes you deployed. After that you can eploy the protocol process.

Edit the process ids on the `index.html` and then create a live server the for it.
