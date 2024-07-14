// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Escrow is ReentrancyGuard {
    // State variables
    IERC20 public token;
    address private admin;
    address payable private receiver;
    bool public isActive;
    uint256 public nextEscrowId;
    uint256 public sellersCount;
    uint256 public buyersCount;
    uint256 public abitratorsCount;
    uint256 public refundFee;
    uint256 public commissionRate;
    
    // Enums
    enum Authorization { Pending, Claim, Cancel, Disputed }
    enum Roles { Abitrates, Sells, Buys }
    enum Listings { List, UnList } 
    
    // Structs 
    struct Product {
        bytes32 id;
        string itemName;
        uint256 price;
        address seller;
        bool onsale;
    }
    struct EscrowDetails {
        bytes32 escrowId;
        bytes32 productId;
        string productName;
        uint256 productPrice;
        address productSeller;
        address productBuyer;
        address productAbitrator;
        uint256 claimTime;
        uint256 expiryTime;
        Authorization authorization;
        bool bought;
    }
    
    // Mappings
    mapping(address => uint256) public sellers;
    mapping(address => uint256) public buyers;
    mapping(address => uint256) public abitrators;
    mapping(bytes32 => Product) public products;
    mapping(bytes32 => EscrowDetails) public escrows;
    mapping(uint256 => address) public buyerList;
    mapping(string => bytes32) public productNames;
    mapping(address => Product) public boughtProducts;
    
    // Modifiers 
    modifier OnlyAdmin() {
        require(msg.sender == admin, "Only Admin Can Do This");
        _;
    }
    
    modifier OnlyAbitrators() {
        require(abitrators[msg.sender] != 0, "You Are Not An Abitrator");
        _;
    }
    
    modifier OnlySellers() {
        require(sellers[msg.sender] != 0, "You Are Not A Seller");
        _;
    }
    
    modifier OnlyBuyers() {
        require(buyers[msg.sender] != 0, "You Are Not A Registered Customer");
        _;
    }
    
    modifier OnlyWhenActive() {
        require(isActive == true, "Contract Not Active");
        _;
    }
     
    // Events
    event BuyerOrSellerAdded(address user, Roles roles);
    event AbitratorAdded(address user, Roles roles);
    event BadRole(address user, Roles roles);
    event Deposit(address user, uint256 amount);
    event ContractDeactivatedBy(address user);
    event Authorized(bytes32 id, Authorization authority, address infavourof);
    event RateSet(uint256 commissionrate, uint256 refundfee, address ratesetter);
    event RefundSent(bytes32 id, uint256 amount, address refundedto);
    event PaymentSent(bytes32 id, uint256 amount, address paidto);
    event ProductUnlisted(string itemName, bytes32 id, address user);
    event ProductRelisted(string itemName, bytes32 id, address user);
    event ReceiptConfirmed(bytes32 id, address confirmedby);
    event CompliantSubmitted(bytes32 escrowid, address complainer, address abitrator, string compliant);
    event ProductAdded(bytes32 id, string itemName, uint256 price, address seller, bool onsale);
    event ProductBought(bytes32 escrowid, uint256 price, uint256 blocknumber, uint256 claimtime, uint256 expirytime);
    event RoleRemoved(address user, Roles roles);
    
    // Constructor 
    constructor(address _admin, address _receiver, address tokenAddress, uint256 _initialRefundPercent, uint256 _initialCommissionPercent) {
        admin = _admin;
        receiver = payable(_receiver);
        token = IERC20(tokenAddress);
        buyersCount = 1;
        sellersCount = 1;
        abitratorsCount = 1;
        refundFee = _initialRefundPercent / 100;
        commissionRate = _initialCommissionPercent / 100;
        isActive = true;
    }
    
    // Functions 
    function addBuyerOrSeller(Roles _roles) external OnlyWhenActive {
        require(sellers[msg.sender] == 0 && buyers[msg.sender] == 0 && abitrators[msg.sender] == 0, "You Have A Role Already");
    
        if (_roles == Roles.Buys) {
           buyers[msg.sender] = buyersCount;
           buyersCount++;
           emit BuyerOrSellerAdded(msg.sender, _roles);
        } else if (_roles == Roles.Sells) {
           sellers[msg.sender] = sellersCount;
           sellersCount++;
           emit BuyerOrSellerAdded(msg.sender, _roles);
        } else if (_roles == Roles.Abitrates) {
            emit BadRole(msg.sender, _roles);
        }
    }

    function removeRoles(Roles _roles, address user) external OnlyWhenActive OnlyAdmin {
    
        if (_roles == Roles.Buys) {
          require(buyers[user] != 0, "User Not Buyer");
          buyers[user] = 0;
          emit RoleRemoved(user, _roles);
        } else if (_roles == Roles.Sells) {
            require(sellers[user] != 0, "User Not Seller");
            sellers[user] = 0;
            emit RoleRemoved(user, _roles);
        } else if (_roles == Roles.Abitrates) {
            require(abitrators[user] != 0, "User Not Abitrator");
            abitrators[user] = 0;
            emit RoleRemoved(user, _roles);
        }
    }

    function addAbitrator(address _abitrator, Roles _roles) external OnlyAdmin OnlyWhenActive {
        require(sellers[_abitrator] == 0 && buyers[_abitrator] == 0 && abitrators[_abitrator] == 0, "This Address Has A Role Already");
    
        if (_roles == Roles.Abitrates) {
           abitrators[_abitrator] = abitratorsCount;
           abitratorsCount++;
           emit AbitratorAdded(_abitrator, _roles);
        } else {
           revert("You Can't Add This Role With This Function");
        }
    }
    
    function addProduct(string memory _itemName, uint256 _price) external OnlySellers OnlyWhenActive returns (bytes32) {
        bytes32 id = generateID(address(msg.sender), _itemName);
        Product memory product = Product(id, _itemName, _price, address(msg.sender), true);
        products[id] = product;
        productNames[_itemName] = id;
        emit ProductAdded(id, _itemName, _price, address(msg.sender), true);
        return id;
    }
    
    function generateID(address str1, string memory str2) public view OnlyWhenActive returns (bytes32) {
        return(keccak256(abi.encodePacked(str1, str2)));
    }

    function generateEscrowID() public view OnlyWhenActive returns (bytes32) {
        return(keccak256(abi.encodePacked(address(msg.sender), block.number)));
    }

    function regenerateEscrowID(address _buyer, uint256 blocknumber) public view OnlyWhenActive returns (bytes32) {
        return(keccak256(abi.encodePacked(_buyer, blocknumber)));
    }

    function approveToken() external OnlyWhenActive {
        require(token.approve(address(this), 1e27), "Token Approval Unsuccessful");
    }

    function deapproveToken() external OnlyWhenActive {
        require(token.approve(address(this), 0), "Token Deapproval Unsuccessful");
    }
    
    function buyProduct(string memory name, uint256 _claimTime, uint256 _expiryTime ) external OnlyBuyers OnlyWhenActive {
        require(_claimTime < _expiryTime, "ClaimTime >= ExpiryTime");
        bytes32 _id = productNames[name];
        require(_id != 0, "Product Doesn't Exist");
        Product memory product = products[_id];
        require(product.seller != address(0) && product.price != 0, "Product Doesn't Exist");
        require(product.onsale == true, "Product Not On Sale");
        bytes32 newId = generateEscrowID();
        EscrowDetails memory escrow = EscrowDetails(newId, _id, product.itemName, product.price, product.seller, msg.sender, address(0), block.timestamp + _claimTime, block.timestamp + _expiryTime, Authorization.Pending, true);
        uint256 amount = escrow.productPrice;
        buyerList[block.number] = msg.sender;
        escrows[newId] = escrow;
        require(token.balanceOf(msg.sender) >= amount, "Insufficient Balance");
        require(token.transferFrom(address(msg.sender), address(this), amount), "Transfer Failed");
        emit ProductBought(newId, escrow.productPrice, block.number - 1, _claimTime, _expiryTime);
    }

    function AdminProductListing(string memory name, Listings _verdict) external OnlyAdmin OnlyWhenActive {
        bytes32 _id = productNames[name];
        require(_id != 0, "Product Doesn't Exist");
        Product memory product = products[_id];
        if (_verdict == Listings.List) {
           product.onsale = true;
           emit ProductRelisted(name, _id, msg.sender);
        } else if (_verdict == Listings.UnList) {
            product.onsale = false;
            emit ProductUnlisted(name, _id, msg.sender);
        }
        products[_id] = product;   
    }

    function relistProduct(string memory name, Listings _verdict) external OnlySellers OnlyWhenActive {
        bytes32 _id = productNames[name];
        require(_id != 0, "Product Doesn't Exist");
        Product memory product = products[_id];
        require(product.seller == msg.sender, "Not An Authorized User");
        if (_verdict == Listings.List) {
           product.onsale = true;
           emit ProductRelisted(name, _id, msg.sender);
        } else if (_verdict == Listings.UnList) {
            product.onsale = false;
            emit ProductUnlisted(name, _id, msg.sender);
        }
        products[_id] = product; 
    }

    function Compliant(uint256 _escrowId, string memory compliant, address _abitrator) external OnlyWhenActive {
        require(buyers[msg.sender] != 0 || sellers[msg.sender] != 0, "Not an Authorized User");
        address _buyer = buyerList[_escrowId];
        bytes32 productEscrowId = regenerateEscrowID(_buyer, _escrowId);
        EscrowDetails memory escrow = escrows[productEscrowId];
        require(escrow.escrowId != 0, "Escrow Not Found");
        require(escrow.productBuyer == msg.sender || escrow.productSeller == msg.sender, "Not User's Escrow");
        require(abitrators[_abitrator] != 0, "Not an Arbitrator");
        escrow.productAbitrator = _abitrator;
        escrow.authorization = Authorization.Disputed;
        escrows[productEscrowId] = escrow;
        emit CompliantSubmitted(productEscrowId, msg.sender, _abitrator, compliant);
    }

    function Resolution(uint256 _escrowId, string memory resolution, Authorization _verdict) external OnlyAbitrators OnlyWhenActive returns (string memory) {
        address _buyer = buyerList[_escrowId];
        bytes32 productEscrowId = regenerateEscrowID(_buyer, _escrowId);
        EscrowDetails memory escrow = escrows[productEscrowId];
        require(escrow.escrowId != 0, "Escrow Not Found");
        require(escrow.productAbitrator == msg.sender, "Not User's Escrow");
        if (_verdict == Authorization.Cancel) {
            escrow.authorization = Authorization.Cancel;
            emit Authorized(productEscrowId, _verdict, _buyer);
        } else if (_verdict == Authorization.Claim) {
            escrow.authorization = Authorization.Claim;
            address user = escrow.productSeller;
            emit Authorized(productEscrowId, _verdict, user);
        } else if (_verdict == Authorization.Pending || _verdict == Authorization.Disputed) {
            return("Not An Allowed Verdict");
        }
        escrows[productEscrowId] = escrow;
        return resolution;
    }
    
    function getRefunds(uint256 _escrowId) external OnlyBuyers OnlyWhenActive nonReentrant {
        address _buyer = buyerList[_escrowId];
        bytes32 productEscrowId = regenerateEscrowID(_buyer, _escrowId);
        EscrowDetails memory escrow = escrows[productEscrowId];
        require(escrow.escrowId != 0, "Escrow Not Found");
        require(block.timestamp > escrow.expiryTime || escrow.authorization == Authorization.Cancel, "Conditions Not Met");
        require(escrow.productBuyer == msg.sender, "Not User's Escrow");
        require(escrow.productPrice != 0, "Funds Already Withdrawn");
        uint256 refundAmount = escrow.productPrice;
        escrow.productPrice = 0;
        uint256 commission = refundAmount * refundFee;
        require(token.transfer(receiver, commission), "Commission Not Sent");
        require(token.transfer(address(msg.sender), refundAmount - commission), "Refund Transfer Failed");
        escrows[productEscrowId] = escrow;
        emit RefundSent(productEscrowId, refundAmount - commission, msg.sender);
    }

    function confirmReceipt(uint256 _escrowId) external OnlyBuyers OnlyWhenActive {
        address _buyer = buyerList[_escrowId];
        bytes32 productEscrowId = regenerateEscrowID(_buyer, _escrowId);
        EscrowDetails memory escrow = escrows[productEscrowId];
        require(escrow.escrowId != 0, "Escrow Not Found");
        require(block.timestamp > escrow.claimTime && block.timestamp < escrow.expiryTime, "Conditions Not Met");
        require(escrow.productBuyer == msg.sender, "Not User's Escrow");
        escrow.authorization = Authorization.Claim;
        escrows[productEscrowId] = escrow;
        emit ReceiptConfirmed(productEscrowId, msg.sender);
    }

    function getPayment(uint256 _escrowId) external OnlySellers OnlyWhenActive nonReentrant {
        address _buyer = buyerList[_escrowId];
        bytes32 productEscrowId = regenerateEscrowID(_buyer, _escrowId);
        EscrowDetails memory escrow = escrows[productEscrowId];
        require(escrow.escrowId != 0, "Escrow Not Found");
        require(escrow.authorization == Authorization.Claim, "Conditions Not Met");
        require(escrow.productSeller == msg.sender, "Not User's Escrow");
        require(escrow.productPrice != 0, "Funds Already Withdrawn");
        uint256 paymentAmount = escrow.productPrice;
        escrow.productPrice = 0;
        uint256 commission = paymentAmount * commissionRate;
        require(token.transfer(receiver, commission), "Commission Not Sent");
        require(token.transfer(address(msg.sender), paymentAmount - commission), "Refund Transfer Failed");
        escrows[productEscrowId] = escrow;
        emit PaymentSent(productEscrowId, paymentAmount - commission, msg.sender);
    }

    function setRate(uint256 _commissionRate, uint256 _refundFee) external OnlyAdmin OnlyWhenActive {
        commissionRate = _commissionRate / 100;
        refundFee = _refundFee / 100;
        emit RateSet(_commissionRate, _refundFee, msg.sender);
    }

    function deleteContract() external OnlyAdmin OnlyWhenActive {
        isActive = false;
        require(token.transfer(receiver, token.balanceOf(address(this))), "Delete Withdrawal Unsuccessful");
        receiver.transfer(address(this).balance);
        emit ContractDeactivatedBy(msg.sender);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}
