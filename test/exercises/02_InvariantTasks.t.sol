// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex6 — invariant testing
/// @notice Every test so far set up a situation and then checked the result. Invariant
///         testing flips that around: let the machine call operations randomly and
///         repeatedly, then ask "no matter how it thrashes, does this property still
///         hold?"
contract VaultHandler is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address[3] public users;

    uint256 public ghost_deposits;
    uint256 public ghost_redeems;

    constructor(
        MockUSDC usdc_,
        SimpleStablecoin stable_,
        Vault vault_
    ) {
        usdc = usdc_;
        stable = stable_;
        vault = vault_;

        users[0] = makeAddr("user0");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");

        for (uint256 i; i < users.length; ++i) {
            usdc.faucet(users[i], 1_000_000e6);
        }
    }

    function deposit(
        uint256 userSeed,
        uint256 amount
    ) external {
        address user =
            users[bound(userSeed, 0, users.length - 1)];

        uint256 balance = usdc.balanceOf(user);

        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.startPrank(user);

        usdc.approve(address(vault), amount);
        vault.deposit(amount);

        vm.stopPrank();

        ghost_deposits++;
    }

    // ==================================================================
    // Ex6.1
    // ==================================================================

    function redeem(
        uint256 userSeed,
        uint256 amount
    ) external {
        address user =
            users[bound(userSeed, 0, users.length - 1)];

        uint256 balance = stable.balanceOf(user);

        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(user);
        vault.redeem(amount);

        ghost_redeems++;
    }
}

contract InvariantTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;
    VaultHandler internal handler;

    address internal admin = address(this);

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);

        stable.grantRole(
            stable.MINTER_ROLE(),
            address(vault)
        );

        handler =
            new VaultHandler(usdc, stable, vault);

        bytes4[] memory selectors =
            new bytes4[](2);

        selectors[0] =
            VaultHandler.deposit.selector;

        selectors[1] =
            VaultHandler.redeem.selector;

        targetSelector(
            FuzzSelector({
                addr: address(handler),
                selectors: selectors
            })
        );

        targetContract(address(handler));
    }

    // ==================================================================
    // Ex6.2
    // ==================================================================

    function invariant_CollateralBacksSupply()
        public
        view
    {
        assertGe(
            vault.totalCollateral(),
            stable.totalSupply(),
            "vault collateral must always back the full sUSD supply"
        );
    }

    // ==================================================================
    // Ex6.3
    // ==================================================================

    function invariant_VaultHoldsNoStablecoin()
        public
        view
    {
        assertEq(
            stable.balanceOf(address(vault)),
            0,
            "vault should never hold sUSD"
        );
    }
}