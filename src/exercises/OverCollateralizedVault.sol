// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SimpleStablecoin} from "../SimpleStablecoin.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

/// @title Over-collateralized vault (Ex5) — four TODOs are waiting for you
/// @notice Unlike the 1:1 loop in Vault.sol, $1 of collateral deposited here mints at most
///         0.667 sUSD (a 150% collateral ratio). Once the collateral ratio falls below
///         120%, anyone can take that collateral at a discount by paying sUSD — that is
///         liquidation, the core mechanism behind MakerDAO.
///
///         Three decimal scales must be told apart:
///           collateral  18 decimals (like WETH)
///           stable       6 decimals (like USDC)
///           priceFeed    8 decimals (like Chainlink ETH/USD)
contract OverCollateralizedVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    SimpleStablecoin public immutable stable;
    IPriceFeed public immutable priceFeed;

    uint256 public constant RATIO_PRECISION = 100;
    uint256 public constant MIN_COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_RATIO = 120;
    uint256 public constant LIQUIDATION_BONUS = 10;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed user, uint256 amount);
    event StableMinted(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    error ZeroAddress();
    error ZeroAmount();
    error Undercollateralized();
    error NotLiquidatable();
    error InsufficientCollateral();

    constructor(IERC20 collateral_, SimpleStablecoin stable_, IPriceFeed priceFeed_) {
        if (
            address(collateral_) == address(0) || address(stable_) == address(0)
                || address(priceFeed_) == address(0)
        ) {
            revert ZeroAddress();
        }
        collateral = collateral_;
        stable = stable_;
        priceFeed = priceFeed_;
    }

    function collateralPrice() public view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        if (answer <= 0) revert ZeroAmount();
        return uint256(answer);
    }

    function collateralValueOf(address user) public view returns (uint256) {
        return collateralValue(collateralOf[user]);
    }

    function collateralRatio(address user) public view returns (uint256) {
        if (debtOf[user] == 0) return type(uint256).max;
        return collateralValueOf(user) * RATIO_PRECISION / debtOf[user];
    }

    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > debtOf[msg.sender]) revert InsufficientCollateral();
        stable.burn(msg.sender, amount);
        debtOf[msg.sender] -= amount;
    }

    // ==================================================================
    // Ex5.1
    // ==================================================================

    function collateralValue(uint256 amount) public view returns (uint256) {
        return amount * collateralPrice() / 1e20;
    }

    // ==================================================================
    // Ex5.2
    // ==================================================================

    function mintStable(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        debtOf[msg.sender] += amount;

        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) {
            revert Undercollateralized();
        }

        stable.mint(msg.sender, amount);
        emit StableMinted(msg.sender, amount);
    }

    // ==================================================================
    // Ex5.3
    // ==================================================================

    function redeemCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > collateralOf[msg.sender]) revert InsufficientCollateral();

        collateralOf[msg.sender] -= amount;

        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) {
            revert Undercollateralized();
        }

        collateral.safeTransfer(msg.sender, amount);
        emit CollateralRedeemed(msg.sender, amount);
    }

    // ==================================================================
    // Ex5.4
    // ==================================================================

    function liquidate(address user) external {
        if (user == address(0)) revert ZeroAddress();

        if (collateralRatio(user) >= LIQUIDATION_RATIO) {
            revert NotLiquidatable();
        }

        uint256 debt = debtOf[user];

        uint256 collateralToSeize =
            debt * (RATIO_PRECISION + LIQUIDATION_BONUS) * 1e20
                / RATIO_PRECISION / collateralPrice();

        uint256 availableCollateral = collateralOf[user];

        if (collateralToSeize > availableCollateral) {
            collateralToSeize = availableCollateral;
        }

        stable.burn(msg.sender, debt);

        debtOf[user] = 0;
        collateralOf[user] = availableCollateral - collateralToSeize;

        collateral.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(
            user,
            msg.sender,
            debt,
            collateralToSeize
        );
    }
}