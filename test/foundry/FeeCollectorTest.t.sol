// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
import "@gammaswap/v1-zapper/contracts/LPZapper.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";
import "../../contracts/FeeCollector.sol";

contract FeeCollectorTest is CPMMGammaSwapSetup {

    struct TestParams {
        address lpToken;
        address token0;
        address token1;
        uint256 balWETH;
        uint256 balUSDC;
        uint256 balWETH6;
        uint256 balUSDC6;
        uint256 balETH;
    }

    IFeeCollector feeCollector;
    ILPZapper lpZapper;
    address user;
    address executor;
    address feeReceiver;

    function setUp() public {
        super.initCPMMGammaSwap(true);
        user = vm.addr(3);
        executor = vm.addr(4);
        feeReceiver = vm.addr(5);

        GammaSwapLibrary.safeTransferETH(address(weth9), 1000_000*1e18);

        lpZapper = new LPZapper(address(weth9), address(factory), address(cfmmFactory), address(posMgr), address(mathLib), address(uniRouter), address(0), address(uniRouter), address(0));
        feeCollector = new FeeCollector(feeReceiver, executor, address(lpZapper), address(factory), address(weth9));
        deal(address(weth9), user, 1000*1e18);
        deal(address(weth), user, 1000_000*1e18);
        deal(address(usdc), user, 1000_000*1e18);

        depositLiquidityInCFMM(addr2, 100e18, 100e18);
        depositLiquidityInPool(addr2);
        depositLiquidityInCFMM(addr1, 100e18, 100e18);

        // 18x18 = usdc/weth9
        depositLiquidityInCFMMByToken(address(usdc), address(weth9), 100*1e18, 100*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth9), 100*1e18, 100*1e18, addr2);
        depositLiquidityInPoolFromCFMM(poolW9, cfmmW9, addr2);
        depositLiquidityInCFMMByToken(address(usdc), address(weth9), 100*1e18, 100*1e18, addr1);

        // 18x6 = usdc/weth6
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), 100*1e18, 100*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), 100*1e18, 100*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), 100*1e18, 100*1e6, addr1);

        // 6x6 = weth6/usdc6
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), 100*1e6, 100*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), 100*1e6, 100*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), 100*1e6, 100*1e6, addr1);

        // 6x18 = usdc6/weth
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), 100*1e6, 100*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), 100*1e6, 100*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool6x18, cfmm6x18, addr2);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), 100*1e6, 100*1e18, addr1);

        // 18x8 = usdc/weth8
        depositLiquidityInCFMMByToken(address(usdc), address(weth8), 100*1e18, 100*1e8, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth8), 100*1e18, 100*1e8, addr2);
        depositLiquidityInPoolFromCFMM(pool18x8, cfmm18x8, addr2);
        depositLiquidityInCFMMByToken(address(usdc), address(weth8), 100*1e18, 100*1e8, addr1);

        // 6x8 = usdc6/weth8
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), 100*1e6, 100*1e8, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), 100*1e6, 100*1e8, addr2);
        depositLiquidityInPoolFromCFMM(pool6x8, cfmm6x8, addr2);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), 100*1e6, 100*1e8, addr1);
    }

    function testFeeCollectorOwner() public {
        address payable addr = payable(address(feeCollector));
        assertEq(FeeCollector(addr).owner(), address(this));

        vm.expectRevert("INITIALIZED");
        FeeCollector(addr).initialize();
    }

    function testSetFeeReceiver() public {
        assertEq(feeReceiver, feeCollector.feeReceiver());

        address newFeeReceiver = vm.addr(0x123456789);
        assertNotEq(feeReceiver, newFeeReceiver);

        vm.startPrank(addr1);

        vm.expectRevert("Ownable: caller is not the owner");
        feeCollector.setFeeReceiver(newFeeReceiver);

        vm.stopPrank();

        feeCollector.setFeeReceiver(newFeeReceiver);

        assertEq(newFeeReceiver, feeCollector.feeReceiver());
    }

    function testSetExecutor() public {
        assertEq(executor, feeCollector.executor());

        address newExecutor = vm.addr(0x123456789);
        assertNotEq(executor, newExecutor);

        vm.startPrank(addr1);

        vm.expectRevert("Ownable: caller is not the owner");
        feeCollector.setExecutor(newExecutor);

        vm.stopPrank();

        feeCollector.setExecutor(newExecutor);

        assertEq(newExecutor, feeCollector.executor());
    }

    function testClearToken() public {
        address payable _feeCollector = payable(address(feeCollector));

        vm.startPrank(addr1);

        uint256 bal0 = IERC20(weth9).balanceOf(address(feeCollector));

        IERC20(weth9).transfer(address(feeCollector), 1e18);

        assertEq(bal0 + 1e18, IERC20(weth9).balanceOf(address(feeCollector)));

        vm.expectRevert("Ownable: caller is not the owner");
        FeeCollector(_feeCollector).clearToken(address(weth9), addr1, 1e18);

        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("NotEnoughTokens()")));
        FeeCollector(_feeCollector).clearToken(address(weth9), addr1, 1e18 + 1);

        assertEq(0, IERC20(weth).balanceOf(address(feeCollector)));

        vm.expectRevert(bytes4(keccak256("NotEnoughTokens()")));
        FeeCollector(_feeCollector).clearToken(address(weth), addr1, 1e18);

        bal0 = IERC20(weth9).balanceOf(address(feeCollector));
        uint256 addr1Bal = IERC20(weth9).balanceOf(addr1);

        FeeCollector(_feeCollector).clearToken(address(weth9), addr1, 1e18);

        assertEq(bal0 - 1e18, IERC20(weth9).balanceOf(address(feeCollector)));
        assertEq(addr1Bal + 1e18, IERC20(weth9).balanceOf(addr1));
    }

    function testCollectFees1(bool isCFMM) public {
        vm.prank(addr1);
        if(isCFMM) {
            IERC20(address(cfmmW9)).transfer(address(feeCollector), 1e18);
        } else {
            IERC20(address(poolW9)).transfer(address(feeCollector), 1e18);
        }

        uint256 balance0 = IERC20(weth9).balanceOf(feeReceiver);

        vm.prank(executor);
        if(isCFMM) {
            feeCollector.collectDSProtocolFees(cfmmW9, 1, 1e18, new uint256[](2), new uint256[](2),
                new address[](0), new address[](0), new bytes(0), new bytes(0));
        } else {
            feeCollector.collectGSProtocolFees(cfmmW9, 1, 1e18, new uint256[](2), new uint256[](2),
                new address[](0), new address[](0), new bytes(0), new bytes(0));
        }
        uint256 balance1 = IERC20(weth9).balanceOf(feeReceiver);

        assertApproxEqRel(balance1,balance0 + 2*1e18,1e16);
    }

    function testCollectFees2(uint8 typ, bool isCFMM) public {
        uint256 amount = 1e18;
        address _pool = address(pool);
        address _cfmm = address(cfmm);
        if(typ == 1){
            _pool = address(pool18x6);
            _cfmm = address(cfmm18x6);
            amount = 1e12;
        } else if(typ == 2) {
            _pool = address(pool6x18);
            _cfmm = address(cfmm6x18);
            amount = 1e12;
        } else if(typ == 3) {
            _pool = address(pool6x6);
            _cfmm = address(cfmm6x6);
            amount = 1e6;
        } else if(typ == 4) {
            _pool = address(pool6x8);
            _cfmm = address(cfmm6x8);
            amount = 1e7;
        } else if(typ == 5) {
            _pool = address(pool18x8);
            _cfmm = address(cfmm18x8);
            amount = 1e13;
        } else if(typ == 6) {
            _pool = address(poolW9);
            _cfmm = address(cfmmW9);
        }

        vm.prank(addr1);
        if(isCFMM) {
            IERC20(address(_cfmm)).transfer(address(feeCollector), amount);
        } else {
            IERC20(address(_pool)).transfer(address(feeCollector), amount);
        }

        address[] memory path0 = new address[](0);
        address[] memory path1 = new address[](0);
        address[] memory tokens = IGammaPool(address(_pool)).tokens();
        if(address(weth) == tokens[0]) {
            console.log("token0 is weth:",tokens[0]);
            path0 = getPathForWETH();
        } else if(address(weth) == tokens[1]) {
            console.log("token1 is weth:",tokens[1]);
            path1 = getPathForWETH();
        }
        if(address(usdc) == tokens[0]) {
            console.log("token0 is usdc:",tokens[1]);
            path0 = getPathForUSDC();
        } else if(address(usdc) == tokens[1]) {
            console.log("token1 is usdc:",tokens[1]);
            path1 = getPathForUSDC();
        }
        if(address(weth6) == tokens[0]) {
            console.log("token0 is weth6:",tokens[0]);
            path0 = getPathForWETH6();
        } else if(address(weth6) == tokens[1]) {
            console.log("token1 is weth6:",tokens[1]);
            path1 = getPathForWETH6();
        }
        if(address(usdc6) == tokens[0]) {
            console.log("token0 is usdc6:",tokens[0]);
            path0 = getPathForUSDC6();
        } else if(address(usdc6) == tokens[1]) {
            console.log("token1 is usdc6:",tokens[1]);
            path1 = getPathForUSDC6();
        }
        if(address(weth8) == tokens[0]) {
            console.log("token0 is weth8:",tokens[0]);
            path0 = getPathForWETH8();
        } else if(address(weth8) == tokens[1]) {
            console.log("token1 is weth8:",tokens[1]);
            path1 = getPathForWETH8();
        }

        uint256 balance0 = IERC20(weth9).balanceOf(feeReceiver);

        vm.prank(executor);
        if(isCFMM) {
            feeCollector.collectDSProtocolFees(address(_cfmm), 1, amount, new uint256[](2), new uint256[](2),
                path0, path1, new bytes(0), new bytes(0));
        } else {
            feeCollector.collectGSProtocolFees(address(_cfmm), 1, amount, new uint256[](2), new uint256[](2),
                path0, path1, new bytes(0), new bytes(0));
        }

        uint256 balance1 = IERC20(weth9).balanceOf(feeReceiver);
        assertApproxEqRel(balance1,balance0 + 2*1e18,1e16);
    }

    function getPathForWETH6() internal view returns(address[] memory path) {
        path = new address[](3);
        path[0] = address(weth6);
        path[1] = address(usdc);
        path[2] = address(weth9);
    }

    function getPathForWETH() internal view returns(address[] memory path) {
        path = new address[](3);
        path[0] = address(weth);
        path[1] = address(usdc);
        path[2] = address(weth9);
    }

    function getPathForUSDC() internal view returns(address[] memory path) {
        path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth9);
    }

    function getPathForUSDC6() internal view returns(address[] memory path) {
        path = new address[](4);
        path[0] = address(usdc6);
        path[1] = address(weth);
        path[2] = address(usdc);
        path[3] = address(weth9);
    }

    function getPathForWETH8() internal view returns(address[] memory path) {
        path = new address[](3);
        path[0] = address(weth8);
        path[1] = address(usdc);
        path[2] = address(weth9);
    }
}
