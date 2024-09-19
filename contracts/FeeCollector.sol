// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "./interfaces/IFeeCollector.sol";
import "@gammaswap/v1-periphery/contracts/PositionManager.sol";
import "@gammaswap/v1-zapper/contracts/interfaces/ILPZapper.sol";
import "@gammaswap/v1-core/contracts/libraries/AddressCalculator.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";

/// @title FeeCollector Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Converts GammaSwap Protocol Fees into protocol revenue
contract FeeCollector is IFeeCollector, Transfers {

    error NotContract();

    address public immutable PROTOCOL_REVENUE_TOKEN;
    address public immutable WETH;
    address public immutable lpZapper;
    address public immutable factory;
    address public immutable feeReceiver;

    constructor(address _protocolRevenueToken, address _lpZapper, address _feeReceiver, address _factory, address _WETH) {
        PROTOCOL_REVENUE_TOKEN = _protocolRevenueToken;
        lpZapper = _lpZapper;
        feeReceiver = _feeReceiver;
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev See {ITransfers-getGammaPoolAddress}.
    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal virtual view returns(address) {
        return AddressCalculator.calcAddress(factory, protocolId, AddressCalculator.getGammaPoolKey(cfmm, protocolId));
    }

    // withdraw liquidity, and convert to protocol revenue
    function collectGSProtocolFees(address cfmm, uint16 protocolId, address[] memory path0, address[] memory path1,
        bytes memory uniV3path0, bytes memory uniV3path1) external virtual {
        require(cfmm != address(0), "ZERO_ADDRESS");
        require(protocolId > 0, "INVALID_PROTOCOL_ID");

        address lpToken = getGammaPoolAddress(cfmm, protocolId);
        if(!GammaSwapLibrary.isContract(lpToken)) revert NotContract(); // Not a smart contract (hence not a CFMM) or not instantiated yet

        /// TODO: Must take into account situation where we can't withdraw liquidity from GammaPool (it's borrowed)
        /// Should probably also do logic to only zapOut partially
        /// Must add logic to handle case when withdrawal is from DeltaSwap/SushiSwap/UniswapV2 for liquidations

        uint256 gslpBalance = IERC20(lpToken).balanceOf(address(this));
        uint256 withdrawAmt = gslpBalance;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: protocolId,
            cfmm: cfmm,
            amount: withdrawAmt,
            to: feeReceiver,
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

        address[] memory tokens = IGammaPool(lpToken).tokens();

        bool isZapOutETH = false;

        // isWETH Pool
        if(tokens[0] == WETH) {
            if(path1.length > 1) {
                lpSwap1.path = path1;
                isZapOutETH = true;
            } else if(uniV3path1.length > 0) {
                lpSwap1.uniV3Path = uniV3path1;
                isZapOutETH = true;
            } else {
                lpSwap1.path = new address[](2);
                lpSwap1.path[0] = tokens[1];
                lpSwap1.path[1] = tokens[0];
            }
        } else if(tokens[1] == WETH) {
            if(path0.length > 1) {
                lpSwap0.path = path0;
                isZapOutETH = true;
            } else if(uniV3path0.length > 0) {
                lpSwap0.uniV3Path = uniV3path0;
                isZapOutETH = true;
            } else {
                lpSwap0.path = new address[](2);
                lpSwap0.path[0] = tokens[0];
                lpSwap0.path[1] = tokens[1];
            }
        } else {
            isZapOutETH = true;
            bool isPathSet = false;
            if(path1.length > 1) {
                lpSwap1.path = path1;
                isPathSet = true;
            } else if(uniV3path1.length > 0) {
                lpSwap1.uniV3Path = uniV3path1;
                isPathSet = true;
            }
            if(path0.length > 1) {
                lpSwap0.path = path0;
                isPathSet = isPathSet && true;
            } else if(uniV3path0.length > 0) {
                lpSwap0.uniV3Path = uniV3path0;
                isPathSet = isPathSet && true;
            }
            require(isPathSet, "PATH_IS_NOT_SET");
        }

        GammaSwapLibrary.safeApprove(lpToken, address(lpZapper), withdrawAmt);

        if(isZapOutETH) {
            params.to = address(this);
            ILPZapper(lpZapper).zapOutETH(params, lpSwap0, lpSwap1);
            send(WETH, address(this), feeReceiver, address(this).balance);
        } else {
            ILPZapper(lpZapper).zapOutToken(params, lpSwap0, lpSwap1);
        }
    }

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
    // We could hold tokens in separate address and this just runs on that address. No, if it's a separate address then
    // it will always need approval for every new GammaPool

}
