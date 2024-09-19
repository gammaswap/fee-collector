// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "@gammaswap/univ3-rebalancer/contracts/libraries/Path.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/BytesLib.sol";
import "@gammaswap/v1-core/contracts/interfaces/IGammaPool.sol";
import "@gammaswap/v1-core/contracts/libraries/AddressCalculator.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";
import "@gammaswap/v1-periphery/contracts/interfaces/IPositionManager.sol";
import "@gammaswap/v1-zapper/contracts/interfaces/ILPZapper.sol";

import "./interfaces/IFeeCollector.sol";

/// @title FeeCollector Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Converts GammaSwap Protocol Fees into protocol revenue
contract FeeCollector is Initializable, UUPSUpgradeable, Ownable2Step, Transfers, IFeeCollector {

    using Path for bytes;
    using BytesLib for bytes;

    error NotContract();

    address public immutable lpZapper;
    address public immutable factory;
    address public feeReceiver;

    constructor(address _feeReceiver, address _lpZapper, address _factory, address _WETH) Transfers(WETH) {
        feeReceiver = _feeReceiver;
        lpZapper = _lpZapper;
        factory = _factory;
        WETH = _WETH;
    }

    /// @dev Initialize LPZapper when used as a proxy contract
    function initialize() public virtual initializer {
        require(owner() == address(0), "INITIALIZED");
        _transferOwnership(msg.sender);
    }

    function setFeeReceiver(address _feeReceiver) external virtual onlyOwner {
        require(_feeReceiver != address(0), "ZERO_ADDRESS");
        feeReceiver = _feeReceiver;
    }

    /// @dev See {ITransfers-getGammaPoolAddress}.
    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal virtual override view returns(address) {
        return AddressCalculator.calcAddress(factory, protocolId, AddressCalculator.getGammaPoolKey(cfmm, protocolId));
    }

    /// @dev Get last token from UniswapV3 path
    /// @param path - UniswapV3 swap path
    /// @return tokenOut - last token in path
    function _getTokenOut(bytes memory path) internal view returns(address tokenOut) {
        bytes memory _path = path.skipToken();
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.toAddress(0);
    }

    function checkUniV3Path(bytes memory path) internal virtual {
        require(path.length > 0 && _getTokenOut(path) == WETH, "INVALID_UNIV3_PATH");
    }

    function checkPath(address[] memory path) internal virtual {
        require(path.length > 1 && path[path.length - 1] == WETH, "INVALID_PATH");
    }

    function collectDSProtocolFees(address cfmm, uint16 protocolId, uint256 lpAmount, uint256[] memory amountsMin, uint256[] memory swapMin,
        address[] memory path0, address[] memory path1, bytes memory uniV3path0, bytes memory uniV3path1) external virtual onlyOwner {
        collectProtocolFees(cfmm, protocolId, lpAmount, amountsMin, swapMin, path0, path1, uniV3path0, uniV3path1, true);
    }

    function collectGSProtocolFees(address cfmm, uint16 protocolId, uint256 lpAmount, uint256[] memory amountsMin, uint256[] memory swapMin,
        address[] memory path0, address[] memory path1, bytes memory uniV3path0, bytes memory uniV3path1) external virtual onlyOwner {
        collectProtocolFees(cfmm, protocolId, lpAmount, amountsMin, swapMin, path0, path1, uniV3path0, uniV3path1, false);
    }

    // withdraw liquidity, and convert to protocol revenue
    function collectProtocolFees(address cfmm, uint16 protocolId, uint256 lpAmount, uint256[] memory amountsMin, uint256[] memory swapMin, address[] memory path0, address[] memory path1,
        bytes memory uniV3path0, bytes memory uniV3path1, bool isCFMMWithdrawal) internal virtual {
        require(cfmm != address(0), "ZERO_ADDRESS");
        require(protocolId > 0, "INVALID_PROTOCOL_ID");
        require(lpAmount > 0, "ZERO_LP_AMOUNT");

        address lpToken = isCFMMWithdrawal ? cfmm : getGammaPoolAddress(cfmm, protocolId);
        if(!GammaSwapLibrary.isContract(lpToken)) revert NotContract(); // Not a smart contract (hence not a CFMM) or not instantiated yet

        {
            uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
            require(lpBalance > 0, "ZERO_LP_BALANCE");

            lpAmount = lpAmount > lpBalance ? lpBalance : lpAmount;
        }

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: protocolId,
            cfmm: cfmm,
            amount: lpAmount,
            to: feeReceiver,
            deadline: block.timestamp,
            amountsMin: amountsMin
        });

        ILPZapper.LPSwapParams memory lpSwap0 = ILPZapper.LPSwapParams({
            amount: swapMin[0],
            protocolId: protocolId,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.LPSwapParams memory lpSwap1 = ILPZapper.LPSwapParams({
            amount: swapMin[1],
            protocolId: protocolId,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        address[] memory tokens = IGammaPool(lpToken).tokens();

        // isWETH Pool
        if(tokens[0] == WETH) {
            if(path1.length > 1) {
                checkPath(path1);
                lpSwap1.path = path1;
            } else if(uniV3path1.length > 0) {
                checkUniV3Path(uniV3path1);
                lpSwap1.uniV3Path = uniV3path1;
            } else {
                lpSwap1.path = new address[](2);
                lpSwap1.path[0] = tokens[1];
                lpSwap1.path[1] = tokens[0];
            }
        } else if(tokens[1] == WETH) {
            if(path0.length > 1) {
                checkPath(path0);
                lpSwap0.path = path0;
            } else if(uniV3path0.length > 0) {
                checkUniV3Path(uniV3path0);
                lpSwap0.uniV3Path = uniV3path0;
            } else {
                lpSwap0.path = new address[](2);
                lpSwap0.path[0] = tokens[0];
                lpSwap0.path[1] = tokens[1];
            }
        } else {
            bool isPathSet = false;
            if(path1.length > 1) {
                checkPath(path1);
                lpSwap1.path = path1;
                isPathSet = true;
            } else if(uniV3path1.length > 0) {
                checkUniV3Path(uniV3path1);
                lpSwap1.uniV3Path = uniV3path1;
                isPathSet = true;
            }
            if(path0.length > 1) {
                checkPath(path0);
                lpSwap0.path = path0;
                isPathSet = isPathSet && true;
            } else if(uniV3path0.length > 0) {
                checkUniV3Path(uniV3path0);
                lpSwap0.uniV3Path = uniV3path0;
                isPathSet = isPathSet && true;
            }
            require(isPathSet, "PATH_IS_NOT_SET");
        }

        GammaSwapLibrary.safeApprove(lpToken, address(lpZapper), lpAmount);

        if(isCFMMWithdrawal) {
            ILPZapper(lpZapper).dsZapOutToken(params, lpSwap0, lpSwap1);
        } else {
            ILPZapper(lpZapper).zapOutToken(params, lpSwap0, lpSwap1);
        }
    }

    /// @dev See {ITransfers-clearToken}
    function clearToken(address token, address to, uint256 minAmt) public virtual override onlyOwner {
        super.clearToken(token, to, minAmt);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
