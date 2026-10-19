# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:

The main risk is that the Vault has more power than it needs. It needs permission to issue sUSD when users deposit collateral, but the current `MINTER_ROLE` also allows it to burn tokens directly from any user's wallet. Normally, users should decide when to redeem their own tokens. If the Vault contract has a bug, or if someone finds a way to misuse its privileged functions, users could lose sUSD without approving the action. The role check may work exactly as written, but the permission itself is still too broad.

I would separate minting and burning permissions in `SimpleStablecoin`. The Vault would receive a `MINTER_ROLE` that only permits minting, while arbitrary burning from other accounts would no longer be available through that role. For redemption, I would use a user-authorized flow: the user approves the Vault to spend a specified amount of sUSD, the Vault transfers that amount from the user, and the transferred tokens are burned from the Vault's own balance. Another option is a `burnFrom` function that checks the user's allowance before burning. The Vault must release collateral only after the authorized burn succeeds. This design limits the damage a compromised Vault can cause and makes ownership and consent clearer.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:

Giving all three roles to one address creates a single point of failure. If that private key is stolen, the attacker can manage permissions, create new sUSD, and pause the system. Even if the owner is trustworthy, one lost key or one operational mistake could affect the entire stablecoin. For a production system, I would apply the principle of least privilege and assign each responsibility separately.

The `DEFAULT_ADMIN_ROLE` should be controlled by a multisignature wallet owned by several trusted team members. Important changes, such as granting a minting role, would require multiple approvals. A timelock could also be added for non-emergency administrative changes, giving users time to see upcoming actions. The `MINTER_ROLE` should be held only by the Vault contract so that minting happens through its collateral checks, not through an ordinary employee wallet. The `PAUSER_ROLE` could belong to a separate security multisig or a limited emergency responder, allowing a fast reaction without granting minting or administrative powers.

I would also monitor all role changes and privileged transactions, regularly review access, and prepare a process for replacing compromised keys. Separating the roles does not remove every risk, but it prevents one compromised account from automatically controlling every critical function.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:

At the moment, the pause check is applied inside `_update`, which is used for ordinary transfers, minting and burning. This is simple to implement, but it also means users cannot redeem their stablecoins when the token is paused. That could be a serious problem during an emergency because users may want to exit the system and recover their collateral.

I would change the logic so it distinguishes between different balance updates. In ERC-20, an ordinary transfer has both a nonzero sender and a nonzero receiver, minting has a zero sender, and burning has a zero receiver. When paused, ordinary transfers would be rejected. I would also block new minting because increasing the supply during an incident could make the situation worse. Burning would remain possible, but I would not allow unrestricted privileged burning as a shortcut. It should happen only through a properly authorized redemption path, with an allowance or another clear proof of user consent.

The Vault would also need a redemption function that remains accessible during the pause. I would test that transfers and deposits cannot proceed, while authorized redemptions still burn sUSD and return collateral. Finally, I would keep a separate emergency control for cases where redemption itself is unsafe, such as a discovered collateral-withdrawal exploit.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:

These two cases show that redemption rules can strongly affect confidence. In the 2008 money-market fund case, a redemption freeze was intended to prevent a rush of withdrawals while assets were under stress. It may protect the remaining pool from an immediate fire sale, but it also means holders cannot get their money when they need it. If people believe that their funds can be locked during a crisis, they may sell their claims at a discount before another freeze happens.

USDC faced a different problem in 2023 when some reserves were held at a failed bank. The market price temporarily dropped well below one dollar. Keeping the redemption mechanism available under its operating arrangements supported the expectation that eligible holders could eventually exchange USDC for dollars at par, although banking hours and settlement arrangements still mattered. That expectation can encourage arbitrage: traders may buy discounted tokens if they believe redemption at one dollar will work.

For our stablecoin, shutting redemption could reduce immediate pressure on collateral, but it would also remove the main mechanism supporting the peg. Leaving redemption open helps confidence only if the system genuinely has enough liquid collateral. If reserves are missing, unlimited redemption simply rewards the first people to exit. The decision therefore depends on both solvency and liquidity.

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:

The coin can lose its intended one-dollar value when holders no longer believe that one sUSD can be exchanged for enough valuable collateral. One class of cause is a solvency problem. For example, if someone obtains `MINTER_ROLE` and creates sUSD without depositing collateral, total supply increases while collateral stays unchanged. Eventually `totalCollateral() >= totalSupply()` may become false. A fall in the real market value of the collateral can also make the system insolvent, even when its recorded token balance has not changed. The invariant only catches this value loss if collateral is measured using an accurate valuation in comparable units.

A second class is a liquidity or redemption problem. The Vault might have enough collateral on paper but be unable to return it quickly, perhaps because funds are frozen, withdrawals are paused, or external settlement is delayed. In that case the on-chain invariant might still pass, but buyers could discount sUSD because they cannot redeem it reliably. Market panic and low trading liquidity can also cause a temporary price deviation even if all reserves are intact.

Therefore, this invariant is a useful basic accounting check, not a complete guarantee of a one-dollar market price. A production design would also need collateral valuation, redemption-availability checks, liquidity monitoring, and operational risk controls.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:

The attack starts when someone who controls role assignments grants the attacker `MINTER_ROLE`, or when an existing holder of that role is compromised. The attacker then calls the stablecoin's privileged mint function to create 1,000,000 sUSD in their own wallet without making a matching MockUSDC deposit. The total sUSD supply rises, but the Vault's collateral does not. This breaks the economic link between issued tokens and reserves.

Next, the attacker tries to redeem the newly created sUSD through the Vault. If the redemption function accepts these tokens and sufficient MockUSDC is available, the Vault burns the submitted sUSD and sends its existing collateral to the attacker. That collateral originally backed honest users' tokens, so the attacker is effectively draining shared reserves. If there is less collateral than the requested redemption, the entire amount cannot be paid out under a correctly checked redemption function. The attacker might still withdraw whatever the redemption rules and available liquidity permit.

The most important prevention point is before unauthorized minting: `MINTER_ROLE` should only belong to the collateral-checking Vault, and role grants should require secure multisignature approval. Monitoring the collateral-to-supply invariant could detect the resulting imbalance, but detection after the mint is not as strong as preventing the privilege abuse in the first place.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:

No, not in exactly the same way. MockUSDC is an on-chain ERC-20 token, so the Vault can check its balance directly. US Treasury securities are legal financial assets that usually exist through custodians, brokers and securities settlement systems. A Solidity contract cannot directly verify how many Treasury bills a custodian actually owns. Even if we issue an on-chain token representing those securities, its token balance would prove only the number of representations, not that the underlying bonds really exist.

We would need a regulated custodian to hold the assets, an issuer or trustee responsible for the tokenized claims, and independent reporting or attestations connecting the off-chain holdings to the on-chain supply. An oracle could publish the latest verified asset value, but that introduces trust, reporting delays and possible manipulation. Treasury prices also change with interest rates, so simply comparing the face amount of securities against the number of sUSD tokens may overstate reserves.

Another challenge is liquidity. Selling Treasuries, moving cash through banks and settling trades take time, while token holders may expect immediate redemption. The invariant would therefore need a reliable valuation method, haircuts, and rules for stale data, not just `balanceOf`. Legal ownership, custody failures and redemption rights would also become part of the system's security model.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:

A building cannot be transferred into a smart contract like an ERC-20 token. I would first place the property under a legal entity, such as a special purpose vehicle (SPV), which would be the registered owner of the building. The SPV could issue legally defined shares or claims represented by on-chain tokens. The Vault could then hold those tokens as collateral, but the legal documents must clearly state what rights token holders actually receive. A token alone does not automatically give ownership of real estate.

Several off-chain parties would be required. Lawyers would set up the SPV, property ownership records and investor rights. A licensed administrator or trustee would oversee the structure. Independent valuers would assess the property, while a property manager would handle tenants, maintenance, rent and insurance. Banks would process rental income and eventual sale proceeds. Oracles or signed reports could provide updated valuations to the Vault.

The main difficulty is that buildings are illiquid. If many people redeem sUSD at once, the system cannot sell part of a building instantly at its estimated price. I would therefore require conservative collateral ratios, a cash liquidity reserve, regular valuations and clearly disclosed redemption limits. The system would also need rules for mortgages, taxes, ownership disputes and bankruptcy, because smart contracts cannot settle those legal problems by themselves.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:

I think the most likely target is the privileged minting permission. An attacker does not need to defeat the collateral calculations if they can obtain a key that already has permission to mint sUSD directly. This might happen through a compromised administrator, a phishing attack, or a mistaken role grant. I would add a test where an unauthorized account attempts minting and another test where a role is wrongly assigned, causing supply to increase without collateral. The first should revert; the second demonstrates why correct access checks are not enough if the administrator gives the permission to the wrong party. This scenario is important because one successful unauthorized mint could damage the backing of every existing token.
