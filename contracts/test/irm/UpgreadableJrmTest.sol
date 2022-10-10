// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../config/BaseTest.t.sol";

import { UpgreadableJumpRateModel, InterestRateModelParams } from "../../midas/irms/UpgreadableJumpRateModel.sol";

contract InterestRateModelTest is BaseTest {
  UpgreadableJumpRateModel upgreadableJumpRateModel;
  InterestRateModelParams params;
  InterestRateModelParams newParams;

  function setUp() public shouldRun(forChains(BSC_MAINNET, POLYGON_MAINNET)) {
    params = InterestRateModelParams({
      blocksPerYear: 10512000,
      baseRatePerYear: 0.5e16,
      multiplierPerYear: 0.18e18,
      jumpMultiplierPerYear: 4e18,
      kink: 0.8e18
    });
    upgreadableJumpRateModel = new UpgreadableJumpRateModel(params);
  }

  function testUpdateJrmParams() public {
    assertEq(upgreadableJumpRateModel.blocksPerYear(), params.blocksPerYear);
    assertEq(upgreadableJumpRateModel.baseRatePerBlock(), params.baseRatePerYear / params.blocksPerYear);

    newParams = InterestRateModelParams({
      blocksPerYear: 512000,
      baseRatePerYear: 0.7e16,
      multiplierPerYear: 0.18e18,
      jumpMultiplierPerYear: 4e18,
      kink: 0.8e18
    });

    upgreadableJumpRateModel._setIrmParameters(newParams);
    vm.roll(1);

    assertEq(upgreadableJumpRateModel.blocksPerYear(), newParams.blocksPerYear);
    assertEq(upgreadableJumpRateModel.baseRatePerBlock(), newParams.baseRatePerYear / newParams.blocksPerYear);
  }
}
