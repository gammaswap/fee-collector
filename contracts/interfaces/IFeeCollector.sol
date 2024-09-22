// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title Interface for FeeCollector contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Interface for contract that collects fees from GammaSwap protocol
interface IFeeCollector {
    /// @return Address that receives collected protocol fees
    function feeReceiver() external view returns(address);

    /// @return Address that is allowed to call functions to collect protocol fees
    function executor() external view returns(address);

    /// @dev Update feeReceiver address
    /// @param _feeReceiver - new address that will collect protocol fees
    function setFeeReceiver(address _feeReceiver) external;

    /// @dev Update executor address
    /// @param _executor - new address that will be allowed to call functions to collect protocol fees
    function setExecutor(address _executor) external;

    /// @notice Collect protocol fees from underlying CFMM (liquidations and swap fees)
    /// @dev Works by withdrawing liquidity and swapping one or both tokens for WETH and send WETH to `feeReceiver`
    /// @dev If you do not provide a path or uniV3path, then a path is constructed from underlying CFMM tokens if it's a WETH pool
    /// @param cfmm - cfmm of gammapool to collect protocol fees from
    /// @param protocolId - protocol id of gammapool to collect fees from
    /// @param lpAmount - amount of LP tokens to withdraw from CFMM (protocol fees are collected as LP tokens). Must be greater than zero
    /// @param amountsMin - amountsMin to check when withdrawing liquidity. If zero no check for slippage while withdrawing
    /// @param swapMin - minimum amounts to get when swapping one token for another. If zero no slippage check for swaps
    /// @param path0 - if provided swap path for token0 using underlying CFMM
    /// @param path1 - if provided swap path for token1 using underlying CFMM
    /// @param uniV3path0 - if provided swap path for token0 using UniV3
    /// @param uniV3path1 - if provided swap path for token1 using UniV3
    function collectDSProtocolFees(address cfmm, uint16 protocolId, uint256 lpAmount, uint256[] memory amountsMin, uint256[] memory swapMin,
        address[] memory path0, address[] memory path1, bytes memory uniV3path0, bytes memory uniV3path1) external;

    /// @notice Collect protocol fees from GammaPool (origination and borrow fees)
    /// @dev Works by withdrawing liquidity and swapping one or both tokens for WETH and send WETH to `feeReceiver`
    /// @dev If you do not provide a path or uniV3path, then a path is constructed from underlying CFMM tokens if it's a WETH pool
    /// @param cfmm - cfmm of gammapool to collect protocol fees from
    /// @param protocolId - protocol id of gammapool to collect fees from
    /// @param lpAmount - amount of LP tokens to withdraw from CFMM (protocol fees are collected as LP tokens). Must be greater than zero
    /// @param amountsMin - amountsMin to check when withdrawing liquidity. If zero no check for slippage while withdrawing
    /// @param swapMin - minimum amounts to get when swapping one token for another. If zero no slippage check for swaps
    /// @param path0 - if provided swap path for token0 using underlying CFMM
    /// @param path1 - if provided swap path for token1 using underlying CFMM
    /// @param uniV3path0 - if provided swap path for token0 using UniV3
    /// @param uniV3path1 - if provided swap path for token1 using UniV3
    function collectGSProtocolFees(address cfmm, uint16 protocolId, uint256 lpAmount, uint256[] memory amountsMin, uint256[] memory swapMin,
        address[] memory path0, address[] memory path1, bytes memory uniV3path0, bytes memory uniV3path1) external;
}
