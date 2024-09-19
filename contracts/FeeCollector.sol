// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "./interfaces/IFeeCollector.sol";
import "@gammaswap/v1-periphery/contracts/PositionManager.sol";
import "@gammaswap/v1-zapper/contracts/interfaces/ILPZapper.sol";
import "@gammaswap/v1-core/contracts/libraries/AddressCalculator.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";

/// @title FeeCollector Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Converts GammaSwap Protocol Fees into protocol revenue
contract FeeCollector is IFeeCollector {

    error NotContract();

    address public immutable PROTOCOL_REVENUE_TOKEN;
    address public immutable WETH;
    address public immutable lpZapper;
    address public immutable factory;

    constructor(address _protocolRevenueToken, address _lpZapper, address _factory, address _WETH) {
        PROTOCOL_REVENUE_TOKEN = _protocolRevenueToken;
        lpZapper = _lpZapper;
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev See {ITransfers-getGammaPoolAddress}.
    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal virtual view returns(address) {
        return AddressCalculator.calcAddress(factory, protocolId, AddressCalculator.getGammaPoolKey(cfmm, protocolId));
    }

    // withdraw liquidity, and convert to protocol revenue
    function collectGSProtocolFees(address cfmm, uint16 protocolId) external virtual {
        address lpToken = getGammaPoolAddress(cfmm, protocolId);
        if(!GammaSwapLibrary.isContract(lpToken)) revert NotContract(); // Not a smart contract (hence not a CFMM) or not instantiated yet

        //TODO: Check gammaPool exists
        // check tokens, do we need a path0 or path1?
        // if we need, check if path0 and/or path1 is provided
        //      -if path0/1 is provided make sure it outputs protocol revenue. If not error out
        //      -if not provided, check that we have a stored DeltaSwap path
        //      -if we don't have a stored DeltaSwap path, check that we can use own pool to trade
        //      -if one of the pool tokens is USDC and the other isn't, and we have no paths, convert to USDC and then convert to WETH.
        //      *Maybe don't do the USDC thing.
        // if path is not provided check if it's simple swap
        // check if it's a simple swap. If not, ask for a path.
        // maybe should have hardcoded paths available for certain pools
        address[] memory tokens = IGammaPool(lpToken).tokens();
        address sender = msg.sender;
        uint256 gslpBalance = IERC20(lpToken).balanceOf(sender);
        uint256 withdrawAmt = gslpBalance;// * percent / 100;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: protocolId,
            cfmm: address(0),
            amount: withdrawAmt,
            to: address(0),
            deadline: block.timestamp,
            amountsMin: new uint256[](2)
        });

        ILPZapper.LPSwapParams memory lpSwap0 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: protocolId,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.LPSwapParams memory lpSwap1 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: protocolId,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        lpSwap0.path = new address[](2);
        lpSwap0.path[0] = tokens[0];
        lpSwap0.path[1] = tokens[1];

        GammaSwapLibrary.safeApprove(lpToken, address(lpZapper), withdrawAmt);

        ILPZapper(lpZapper).zapOutToken(params, lpSwap0, lpSwap1);

    }


}
