// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Protocol} from "../src/Protocol.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {ProtocolScript} from "../script/ProtocolScript.s.sol";

contract ProtocolTest is Test {
    ProtocolScript public protocolScript;
    Protocol public protocol;
    MockUSDC public mockUSDC;

    address public mockUSDCAddress;
    address public protocolAddress;

    address public LENDER = makeAddr("lender");
    address public BORROWER = makeAddr("borrower");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint64 public LenderUSDCAmount = 1000 *10**6; //1000 USDC
    uint64 public BorrwerUSDCAmount = 100 *10**6; //100 USDC


    function setUp() public {
        protocolScript = new ProtocolScript();
        (mockUSDCAddress, protocolAddress) =protocolScript.run();
        protocol = Protocol(protocolAddress);
        mockUSDC = MockUSDC(mockUSDCAddress);
        mockUSDC.mint(LENDER,  10000 *10**6);
        mockUSDC.mint(address(this),  10000 *10**6);
        mockUSDC.mint(LIQUIDATOR,  10000 *10**6);
    }

    function testdepositAsLender() public{
        vm.startPrank(LENDER);
        mockUSDC.approve(address(protocol), LenderUSDCAmount);
        protocol.depositAsLender( LenderUSDCAmount );
        assertEq(protocol.totalLiquidity(),  LenderUSDCAmount );
        vm.stopPrank();
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
    }

    function testdepositAndBorrow() public{
        vm.startPrank(LENDER);
        mockUSDC.approve(address(protocol), LenderUSDCAmount);
        protocol.depositAsLender( LenderUSDCAmount );
        assertEq(protocol.totalLiquidity(),  LenderUSDCAmount );
        vm.stopPrank();
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        protocol.depositAndBorrow{value: 0.2 ether }(BorrwerUSDCAmount);
        assertEq(protocol.totalLoans(), BorrwerUSDCAmount);
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        console.log("Total Loan present in USDC:", protocol.totalLoans()/10**6);
    }

    function testrepayLoan() public{
        vm.startPrank(LENDER);
        mockUSDC.approve(address(protocol), LenderUSDCAmount);
        protocol.depositAsLender( LenderUSDCAmount );
        assertEq(protocol.totalLiquidity(),  LenderUSDCAmount );
        vm.stopPrank();
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        protocol.depositAndBorrow{value: 0.2 ether }(BorrwerUSDCAmount);
        assertEq(protocol.totalLoans(), BorrwerUSDCAmount);
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        console.log("Total Loan present in USDC:", protocol.totalLoans()/10**6);
        
        skip(31536000);
        console.log("Borrower Balance before repaying:", mockUSDC.balanceOf(address(this))/10**6);
        console.log("Lender Balance before repaying:", mockUSDC.balanceOf(LENDER)/10**6);
        mockUSDC.approve(address(protocol), 1000*10**6);
        protocol.repayLoan();
        // assertEq(protocol.totalLoans(), 0);
        console.log("Borrower Balance after repaying:", mockUSDC.balanceOf(address(this))/10**6);
        console.log("Lender Balance after repaying:", mockUSDC.balanceOf(LENDER)/10**6);
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        console.log("Total Loan present in USDC:", protocol.totalLoans()/10**6);
    }

    function testLiquidation() public{
        vm.startPrank(LENDER);
        mockUSDC.approve(address(protocol), LenderUSDCAmount);
        protocol.depositAsLender( LenderUSDCAmount );
        assertEq(protocol.totalLiquidity(),  LenderUSDCAmount );
        vm.stopPrank();
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);

        protocol.depositAndBorrow{value: 0.2 ether }(BorrwerUSDCAmount);
        assertEq(protocol.totalLoans(), BorrwerUSDCAmount);
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        console.log("Total Loan present in USDC:", protocol.totalLoans()/10**6);

        protocol.setETHprice(500*1e6);
        vm.startPrank(LIQUIDATOR);
        mockUSDC.approve(address(protocol), 10000*10**6);
        protocol.liquidate(address(this));
        vm.stopPrank();
        console.log("Total Liquidity present in USDC:", protocol.totalLiquidity()/10**6);
        console.log("Total Loan present in USDC:", protocol.totalLoans()/10**6);

    }

    receive() external payable{

    }
}
