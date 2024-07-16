// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/TestToken.sol";

contract EscrowTest is Test {
    Escrow escrow;
    TestToken token;
    address admin = address(0x1);
    address receiver = address(0x2);
    address seller = address(0x3);
    address buyer = address(0x4);
    address arbitrator = address(0x5);

    function setUp() public {
        token = new TestToken();
        escrow = new Escrow(admin, receiver, address(token));

        // Distribute tokens to users
        token.transfer(seller, 100000e18);
        token.transfer(buyer, 100000e18);
        vm.deal(buyer, 100 ether);
    }

    function testAddBuyerOrSeller() public {
        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);
        assertEq(escrow.buyers(buyer), 1);

        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);
        assertEq(escrow.sellers(seller), 1);

        vm.prank(seller);
        vm.expectRevert();
        escrow.addBuyerOrSeller(Escrow.Roles.Abitrates);
    }

    function testAddArbitrator() public {
        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);
        assertEq(escrow.abitrators(arbitrator), 1);
    }

    function testAddProduct() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);
        bytes32 productId = escrow.generateID(seller, "Test Product");
        (bytes32 id, string memory itemName, uint256 price, address productSeller, bool onsale) =
            escrow.products(productId);
        assertEq(itemName, "Test Product");
        assertEq(price, 100e18);
        assertEq(productSeller, seller);
        assertEq(id, productId);
        assertEq(onsale, true);
    }

    function testBuyProduct() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);
        bytes32 productId = escrow.generateID(seller, "Test Product");

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        // Check escrow details
        bytes32 newId = escrow.regenerateEscrowID(buyer, currentBlock);
        (
            bytes32 escrowId,
            bytes32 productID,
            string memory productName,
            uint256 productPrice,
            address productSeller,
            address productBuyer,
            ,
            uint256 claimTime,
            uint256 expiryTime,
            Escrow.Authorization authorization,
            bool bought
        ) = escrow.escrows(newId);
        assertEq(productID, productId);
        assertEq(productName, "Test Product");
        assertEq(productPrice, 100e18);
        assertEq(escrowId, newId);
        assertEq(productSeller, seller);
        assertEq(productBuyer, buyer);
        assertEq(bought, true);
        assertEq(claimTime, block.timestamp + 1 days);
        assertEq(expiryTime, block.timestamp + 2 days);
        assertEq(uint256(authorization), uint256(Escrow.Authorization.Pending));
        assertEq(token.balanceOf(buyer), 99900e18);
    }

    function testAdminListProduct() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(admin);
        escrow.AdminProductListing("Test Product", Escrow.Listings.UnList);
        bytes32 productId = escrow.generateID(seller, "Test Product");
        (,,,, bool onsale) = escrow.products(productId);
        assertEq(onsale, false);
    }

    function testSellerListProduct() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(seller);
        escrow.relistProduct("Test Product", Escrow.Listings.UnList);
        bytes32 productId = escrow.generateID(seller, "Test Product");
        (,,,, bool onsale) = escrow.products(productId);
        assertEq(onsale, false);
    }

    function testRemoveRole() public {
        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);

        vm.prank(admin);
        escrow.removeRoles(Escrow.Roles.Abitrates, arbitrator);
        assertEq(escrow.abitrators(arbitrator), 0);
    }

    function testCompliant() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);

        vm.prank(seller);
        escrow.Compliant(currentBlock, "I have Delivered, Buyer Refused To Release Funds", arbitrator);
        bytes32 newId = escrow.regenerateEscrowID(buyer, currentBlock);
        (,,,,,, address productArbitrator,,, Escrow.Authorization authorization,) = escrow.escrows(newId);
        assertEq(uint256(authorization), uint256(Escrow.Authorization.Disputed));
        assertEq(productArbitrator, arbitrator);
    }

    function testResolution() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);

        vm.prank(seller);
        escrow.Compliant(currentBlock, "I have Delivered, Buyer Refused To Release Funds", arbitrator);

        vm.prank(arbitrator);
        escrow.Resolution(currentBlock, "Funds Rightfully Belong to Seller", Escrow.Authorization.Claim);
        bytes32 newId = escrow.regenerateEscrowID(buyer, currentBlock);
        (,,,,,,,,, Escrow.Authorization authorization,) = escrow.escrows(newId);
        assertEq(uint256(authorization), uint256(Escrow.Authorization.Claim));

        vm.prank(arbitrator);
        vm.expectRevert();
        escrow.Resolution(currentBlock, "Funds Rightfully Belong to Seller", Escrow.Authorization.Pending);
    }

    function testGetRefundsAfterResolution() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);

        vm.prank(seller);
        escrow.Compliant(currentBlock, "I have Delivered, Buyer Refused To Release Funds", arbitrator);

        vm.prank(arbitrator);
        escrow.Resolution(currentBlock, "Funds Rightfully Belong to Buyer", Escrow.Authorization.Cancel);

        vm.prank(buyer);
        escrow.getRefunds(currentBlock);
        uint256 receiverBalance = token.balanceOf(receiver);
        uint256 buyerBalance = token.balanceOf(buyer);
        assertEq(receiverBalance, 3e18);
        assertEq(buyerBalance, 99997e18);
    }

    function testGetRefundsAfterExpiry() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.warp(2 days + 1 hours);

        vm.prank(buyer);
        escrow.getRefunds(currentBlock);
        uint256 receiverBalance = token.balanceOf(receiver);
        uint256 buyerBalance = token.balanceOf(buyer);
        assertEq(receiverBalance, 3e18);
        assertEq(buyerBalance, 99997e18);
    }

    function testGetPaymentAfterResolution() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.prank(admin);
        escrow.addAbitrator(arbitrator, Escrow.Roles.Abitrates);

        vm.prank(seller);
        escrow.Compliant(currentBlock, "I have Delivered, Buyer Refused To Release Funds", arbitrator);

        vm.prank(arbitrator);
        escrow.Resolution(currentBlock, "Funds Rightfully Belong to Buyer", Escrow.Authorization.Claim);

        vm.prank(seller);
        escrow.getPayment(currentBlock);
        uint256 receiverBalance = token.balanceOf(receiver);
        uint256 sellerBalance = token.balanceOf(seller);
        assertEq(receiverBalance, 10e18);
        assertEq(sellerBalance, 100090e18);
    }

    function testConfirmReceipt() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.warp(1 days + 1 hours);

        vm.prank(buyer);
        escrow.confirmReceipt(currentBlock);
        bytes32 newId = escrow.regenerateEscrowID(buyer, currentBlock);
        (,,,,,,,,, Escrow.Authorization authorization,) = escrow.escrows(newId);
        assertEq(uint256(authorization), uint256(Escrow.Authorization.Claim));
    }

    function testGetPaymentAfterClaimTime() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        uint256 currentBlock = block.number;
        escrow.buyProduct("Test Product", 1 days, 2 days);

        vm.warp(1 days + 1 hours);

        vm.prank(buyer);
        escrow.confirmReceipt(currentBlock);

        vm.prank(seller);
        escrow.getPayment(currentBlock);
        uint256 receiverBalance = token.balanceOf(receiver);
        uint256 sellerBalance = token.balanceOf(seller);
        assertEq(receiverBalance, 10e18);
        assertEq(sellerBalance, 100090e18);
    }

    function testDeleteContract() public {
        vm.prank(seller);
        escrow.addBuyerOrSeller(Escrow.Roles.Sells);

        vm.prank(seller);
        escrow.addProduct("Test Product", 100e18);

        vm.prank(buyer);
        token.approve(address(escrow), 100e18);

        vm.prank(buyer);
        escrow.addBuyerOrSeller(Escrow.Roles.Buys);

        // Buy product
        vm.prank(buyer);
        escrow.buyProduct("Test Product", 1 days, 2 days);
        uint256 contractTokenBalanceBefore = token.balanceOf(address(escrow));
        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        vm.warp(1 days);

        vm.prank(admin);
        escrow.deleteContract();
        uint256 contractTokenBalanceAfter = token.balanceOf(address(escrow));
        uint256 receiverBalanceAfter = token.balanceOf(receiver);
        assertTrue(!escrow.isActive());
        assertEq(contractTokenBalanceAfter, 0);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + contractTokenBalanceBefore);
    }

    function testReceiveWIthWrongFunction() public {
        vm.prank(buyer);
        (bool success,) = address(escrow).call{value: 10 ether}("0x12345");
        assertFalse(success, "Transaction Should Fail, No throwback Function");
        uint256 contractBalance = address(escrow).balance;
        assertEq(contractBalance, 0 ether, "Balance Should Be 0 Ether");
    }

    function testReceive() public {
        vm.prank(buyer);
        (bool success,) = address(escrow).call{value: 10 ether}("");
        assertTrue(success, "Receive Function Should be Called");
        uint256 contractBalance = address(escrow).balance;
        assertEq(contractBalance, 10 ether, "Balance Should Be 10 Ether");
    }
    // Additional tests for other functions...
}
