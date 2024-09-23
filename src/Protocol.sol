// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Protocol {
    using SafeERC20 for IERC20; // Use SafeERC20 library for IERC20 tokens

    ///////////////////
    // Errors
    ///////////////////
    error ETHAmountNotMoreThanZero();
    error USDCAmountNotMoreThanZero();
    error NotEnoughLiquidityUSDC();
    error TransferFailed();

    ///////////////////
    // State variables
    ///////////////////
    IERC20 public usdc;
    //This means that in order to borrow a certain amount of USDC, the borrower must provide collateral (in ETH) worth at least 150% of the borrowed amount.
    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateral ratio
    //The interest rate is a fixed 5% per year. This means that if you borrow USDC, the amount you owe will increase by 5% annually.
    //We can also make the interest dynamic but I made it fixed cause I want to make it simple.
    uint8 public constant INTEREST_RATE = 5; // 5% fixed interest rate per year
    // This means that if the value of the collateral falls below 110% of the borrowed USDC amount, the collateral is at risk of liquidation.
    uint256 public constant LIQUIDATION_THRESHOLD = 110; // 110% for liquidation
    uint32 public constant SECONDS_IN_A_YEAR = 31536000; // Seconds in 1 year.
    uint64 public totalLiquidity; // Total USDC available for loans
    uint64 public totalLoans; // Total USDC loaned out
    address[] public lendersArray;
    uint256 public mockETHprice = 2000 * 1e6; //Usually we use chainlink oracle but to keep things simple for testing I am using default value.

    ///////////////////
    // Struct
    ///////////////////
    //I have done type pacakging here.
    struct Loan {
        uint64 collateralAmount; // in ETH
        uint64 borrowedAmount; // in USDC
        uint128 borrowTimestamp;
    }

    struct Lender {
        uint64 depositedAmount; // in USDC
        uint64 interestEarned; // in USDC
    }

    ///////////////////
    // Mapping
    ///////////////////
    mapping(address => Loan) public loans;
    mapping(address => Lender) public lenders;

    ///////////////////
    // Modifiers
    ///////////////////

    modifier moreThanZeroETH(uint256 _amount) {
        if (_amount == 0) {
            revert ETHAmountNotMoreThanZero(); // Revert if the amount is zero
        }
        _;
    }

    modifier moreThanZeroUSDC(uint256 _amount) {
        if (_amount == 0) {
            revert USDCAmountNotMoreThanZero(); // Revert if the amount is zero
        }
        _;
    }

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    // Lender deposits USDC into the pool
    function depositAsLender(uint64 usdcAmount) external moreThanZeroUSDC(usdcAmount) {
        // Transfer USDC from lender to contract
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Update lender's record and total liquidity
        lendersArray.push(msg.sender);
        lenders[msg.sender].depositedAmount += usdcAmount;
        totalLiquidity += usdcAmount;
    }

    // Borrower deposits ETH as collateral and borrows USDC
    function depositAndBorrow(uint64 usdcAmount)
        external
        payable
        moreThanZeroETH(msg.value)
        moreThanZeroUSDC(usdcAmount)
    {
        if (totalLiquidity < usdcAmount) {
            revert NotEnoughLiquidityUSDC();
        }

        // Calculate the required collateral amount based on the borrow amount
        uint256 collateralRequired = (usdcAmount * COLLATERAL_RATIO) / 100; // For eg. 100*150/100 -> 15000/100 -> 150 USDC

        uint256 ethPrice = mockETHprice;
        uint256 requiredEth = (collateralRequired * 1e18) / ethPrice;
        require(msg.value >= requiredEth, "Not enough ETH as collateral.");

        // Transfer USDC to borrower
        usdc.transfer(msg.sender, usdcAmount);

        // Record the loan
        loans[msg.sender] =
            Loan({collateralAmount: uint64(msg.value), borrowedAmount: usdcAmount, borrowTimestamp: uint128(block.timestamp)});

        // Update total loans and liquidity
        totalLoans += usdcAmount;
        totalLiquidity -= usdcAmount;
    }

    // Repay the borrowed USDC with interest
    //First user needs ot give appoval.
    function repayLoan() external {
        Loan storage loan = loans[msg.sender];
        require(loan.borrowedAmount > 0, "No loan to repay.");

        uint256 timeElapsed = block.timestamp - loan.borrowTimestamp; //The time passed between the loan taken and repaied by borrower.
        uint256 interest = (loan.borrowedAmount * INTEREST_RATE * uint64(timeElapsed)) / (100 * SECONDS_IN_A_YEAR);
        uint256 totalRepayment = loan.borrowedAmount + interest;

        // Transfer the repayment amount of USDC from the borrower
        usdc.safeTransferFrom(msg.sender, address(this), totalRepayment);

        // Return the collateral to the borrower
        (bool success,) = payable(msg.sender).call{value: loan.collateralAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        // Distribute interest to the lenders
        distributeInterest(uint64(interest));

        
        // Update total loans and liquidity
        totalLoans -= loan.borrowedAmount;
        totalLiquidity += loan.borrowedAmount;
       
        // Clear the loan record
        delete loans[msg.sender];
    }

    // Distribute interest to lenders proportionally
    function distributeInterest(uint64 interest) internal {
        uint256 totalDeposited = totalLiquidity + totalLoans;
        if (totalDeposited == 0) return;

        // Distribute interest to each lender based on their proportion of the total deposits
        for (uint256 i = 0; i < lendersArray.length; i++) {
            address lenderAddr = lendersArray[0];
            Lender storage lender = lenders[lenderAddr];
            if (lender.depositedAmount > 0) {
                uint64 lenderShare = (lender.depositedAmount * interest) / uint64(totalDeposited);
                lender.interestEarned += lenderShare;
                lender.depositedAmount += lenderShare;
            }
        }
    }

    // Lender withdraws their USDC and earned interest
    function withdrawAsLender(uint64 usdcAmount) external {
        Lender storage lender = lenders[msg.sender];

        require(lender.depositedAmount >= usdcAmount, "Not enough deposited.");


        // Transfer USDC to lender
        usdc.safeTransfer(msg.sender, usdcAmount);

        // Update lender's record and total liquidity
        lender.depositedAmount -= usdcAmount;
        totalLiquidity -= usdcAmount;
        if(lender.depositedAmount == 0){
            lender.interestEarned = 0; // Reset the interest earned after full withdrawal
        }
    }

// Liquidate the collateral if the collateralization ratio is below the threshold
function liquidate(address borrower) external {
    Loan storage loan = loans[borrower];
    require(loan.borrowedAmount > 0, "No loan to liquidate.");

    uint256 ethPrice = mockETHprice;

    uint256 collateralValue = (loan.collateralAmount * ethPrice) / 1e18;

    // Check if the collateral is below the liquidation threshold
    uint256 liquidationThreshold = (loan.borrowedAmount * LIQUIDATION_THRESHOLD) / 100;
    require(collateralValue < liquidationThreshold, "Collateral above liquidation threshold.");

    // Calculate interest owed on the loan
    uint256 timeElapsed = block.timestamp - loan.borrowTimestamp;
    uint256 interest = (loan.borrowedAmount * INTEREST_RATE * timeElapsed) / (100 * SECONDS_IN_A_YEAR);

    uint256 totalOwed = loan.borrowedAmount + interest;

    // The liquidator pays the total amount owed in USDC
    usdc.transferFrom(msg.sender, address(this), totalOwed);

    (bool success,) = payable(msg.sender).call{value: loan.collateralAmount}("");
    if (!success) {
        revert("TransferFailed");
    }

    
    totalLoans -= loan.borrowedAmount;
    totalLiquidity += loan.borrowedAmount; 
    
    delete loans[borrower];
}

function setETHprice(uint256 amount) public {
    mockETHprice = amount;
}


}
