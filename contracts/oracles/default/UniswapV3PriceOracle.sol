// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import { PriceOracle } from "../../compound/PriceOracle.sol";
import { BasePriceOracle } from "../BasePriceOracle.sol";
import { ICErc20 } from "../../external/compound/ICErc20.sol";
import { CTokenInterface } from "../../compound/CErc20.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

import "../../external/uniswap/TickMath.sol";
import "../../external/uniswap/FullMath.sol";
import "../../external/uniswap/IUniswapV3Pool.sol";
import "../../midas/SafeOwnableUpgradeable.sol";

// import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
/**
 * @title UniswapV3PriceOracle
 * @author Carlo Mazzaferro <carlo@midascapital.xyz> (https://github.com/carlomazzaferro)
 * @notice UniswapV3PriceOracle is a price oracle for Uniswap V3 pairs.
 * @dev Implements the `PriceOracle` interface used by Fuse pools (and Compound v2).
 */
contract UniswapV3PriceOracle is PriceOracle, SafeOwnableUpgradeable {
  /**
   * @notice Maps ERC20 token addresses to UniswapV3Pool addresses.
   */
  mapping(address => AssetConfig) public poolFeeds;

  /**
   * @dev Controls if `admin` can overwrite existing assignments of oracles to underlying tokens.
   */
  bool public canAdminOverwrite;

  struct AssetConfig {
    address poolAddress;
    uint256 twapWindow;
    FeedBaseCurrency baseCurrency;
  }

  /**
   * @notice Enum indicating the base currency of a Chainlink price feed.
   * @dev ETH is interchangeable with the nativeToken of the current chain.
   */

  enum FeedBaseCurrency {
    ETH,
    USD
  }

  address public wtoken;
  address public USD_TOKEN;

  function initialize(address _wtoken, address usdToken) public initializer {
    __SafeOwnable_init();
    wtoken = _wtoken;
    USD_TOKEN = usdToken;
  }

  /**
   * @dev Admin-only function to set price feeds.
   * @param underlyings Underlying token addresses for which to set price feeds.
   * @param assetConfig The asset configuration which includes pool address and twap window.
   */
  function setPoolFeeds(address[] memory underlyings, AssetConfig[] memory assetConfig) external onlyOwner {
    // Input validation
    require(
      underlyings.length > 0 && underlyings.length == assetConfig.length,
      "Lengths of both arrays must be equal and greater than 0."
    );

    // For each token/config
    for (uint256 i = 0; i < underlyings.length; i++) {
      require(
        assetConfig[i].baseCurrency == FeedBaseCurrency.ETH || assetConfig[i].baseCurrency == FeedBaseCurrency.USD,
        "Invalid base currency"
      );
      address underlying = underlyings[i];
      // Set asset config for underlying
      poolFeeds[underlying] = assetConfig[i];
    }
  }

  /**
   * @notice Get the token price price for an underlying token address.
   * @param underlying The underlying token address for which to get the price (set to zero address for WTOKEN)
   * @return Price denominated in WTOKEN (scaled by 1e18)
   */
  function price(address underlying) external view returns (uint256) {
    return _price(underlying);
  }

  /**
   * @notice Returns the price in WTOKEN of the token underlying `cToken`.
   * @dev Implements the `PriceOracle` interface for Fuse pools (and Compound v2).
   * @return Price in WTOKEN of the token underlying `cToken`, scaled by `10 ** (36 - underlyingDecimals)`.
   */
  function getUnderlyingPrice(CTokenInterface cToken) public view override returns (uint256) {
    address underlying = ICErc20(address(cToken)).underlying();
    // Comptroller needs prices to be scaled by 1e(36 - decimals)
    // Since `_price` returns prices scaled by 18 decimals, we must scale them by 1e(36 - 18 - decimals)
    return (_price(underlying) * 1e18) / (10**uint256(ERC20Upgradeable(underlying).decimals()));
  }

  /**
   * @dev Fetches the price for a token from Uniswap v3
   */
  function _price(address token) internal view virtual returns (uint256) {
    uint32[] memory secondsAgos = new uint32[](2);
    uint256 twapWindow = poolFeeds[token].twapWindow;
    FeedBaseCurrency baseCurrency = poolFeeds[token].baseCurrency;

    secondsAgos[0] = uint32(twapWindow);
    secondsAgos[1] = 0;

    IUniswapV3Pool pool = IUniswapV3Pool(poolFeeds[token].poolAddress);
    (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

    int24 tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int256(twapWindow)));
    uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

    uint256 tokenPrice = getPriceX96FromSqrtPriceX96(pool.token0(), token, sqrtPriceX96);

    if (baseCurrency == FeedBaseCurrency.ETH) {
      return tokenPrice;
    } else {
      uint256 usdNativePrice = BasePriceOracle(msg.sender).price(USD_TOKEN);
      // scale tokenPrice by 1e18
      uint256 baseTokenDecimals = uint256(ERC20Upgradeable(USD_TOKEN).decimals());
      uint256 tokenDecimals = uint256(ERC20Upgradeable(token).decimals());
      uint256 tokenPriceScaled;

      if (baseTokenDecimals > tokenDecimals) {
        tokenPriceScaled = tokenPrice / (10**(baseTokenDecimals - tokenDecimals));
      } else if (baseTokenDecimals < tokenDecimals) {
        tokenPriceScaled = tokenPrice * (10**(tokenDecimals - baseTokenDecimals));
      } else {
        tokenPriceScaled = tokenPrice;
      }

      return (tokenPriceScaled * usdNativePrice) / 1e18;
    }
  }

  function getPriceX96FromSqrtPriceX96(
    address token0,
    address priceToken,
    uint160 sqrtPriceX96
  ) public pure returns (uint256 price) {
    if (token0 == priceToken) {
      price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / 1e18);
    } else {
      price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / 1e18);
      price = 1e36 / price;
    }
  }
}
