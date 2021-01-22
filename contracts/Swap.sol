pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import './owner/Operator.sol';

contract Swap is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public assetToken;
    address public askToken;
    address public feeFund;
    address public createFeeToken;
    uint256 public createFee;
    uint256 public dealFeeRate;
    uint256 public maxExpirePeroid;

    struct Order {
        uint256 createTime;
        address owner;
        uint256 assetAmount;
        uint256 askAmount;
        uint256 expire;
    }

    Order[] public orders;
    mapping (address => uint256[]) public userOrders;

    event CreateOrder( 
        uint256 orderId, 
        uint256 timestamp,
        address onwer,  
        uint256 assetAmount,
        uint256 askAmount
    );
    event CancelOrder(
        uint256 orderId,
        uint256 timestamp
    );
    event DealOrder(
        uint256 orderId,
        uint256 timestamp,
        address dealer,
        uint256 bidAmount
    );

    constructor(
        address _assetToken,
        address _askToken,
        address _feeFund,
        address _createFeeToken,
        uint256 _createFee,
        uint256 _dealFeeRate,
        uint256 _maxExpirePeroid
    ) public {
        assetToken = _assetToken;
        askToken = _askToken;
        feeFund = _feeFund;
        createFeeToken = _createFeeToken;
        createFee = _createFee;
        dealFeeRate = _dealFeeRate;
        maxExpirePeroid = _maxExpirePeroid;
    }

    // ==================  VIEW   ========================
    function getOrdersCount() public view returns(uint256) {
        return orders.length;
    }

    function getUserOrdersCount(address owner) public view returns(uint256) {
        return userOrders[owner].length;
    }

    // ============== ORDER OPERATION ====================
    function createOrder(
        uint256 assetAmount,
        uint256 askAmount,
        uint256 expire
    ) public {
        uint256 expirePeriod = expire.sub(block.timestamp);
        require(expirePeriod <= maxExpirePeroid, "SWAP: expire invalid");
        require(assetAmount > 0, "SWAP: asset amount invalid");
        require(askAmount > 0, "SWAP: ask amount invalid");

        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), assetAmount);
        if (createFee > 0) {
            IERC20(createFeeToken).safeTransferFrom(msg.sender, feeFund, createFee);
        }
        
        Order memory order;
        order.owner = msg.sender;
        order.createTime = block.timestamp;
        order.assetAmount = assetAmount;
        order.askAmount = askAmount;
        order.expire = expire;

        uint256 orderId = orders.length;
        orders.push(order);
        userOrders[msg.sender].push(orderId);

        emit CreateOrder(orderId, block.timestamp, msg.sender, assetAmount, askAmount);
    }

    function cancelOrder(
        uint256 orderId
    ) public {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "SWAP: no owner");
        require(order.assetAmount > 0, "SWAP: done yet");

        IERC20(assetToken).safeTransfer(msg.sender, order.assetAmount);
        order.assetAmount = 0;
        order.askAmount = 0;

        emit CancelOrder(orderId, block.timestamp);
    }

    function dealOrder(
        uint256 orderId,
        uint256 bidAmount
    ) public {
        Order storage order = orders[orderId];
        require(block.timestamp >= order.expire, "SWAP: order expire");
        require(order.assetAmount > 0, "SWAP: done yet");

        uint256 dealAskAmount = bidAmount;
        if (dealAskAmount > order.askAmount) {
            dealAskAmount = order.askAmount;
        }
        uint256 dealAssetAmount = order.assetAmount.mul(dealAskAmount).div(order.askAmount);
        uint256 feeAmount = dealAskAmount.mul(dealFeeRate).div(10000);

        IERC20(askToken).safeTransferFrom(msg.sender, feeFund, feeAmount);   
        IERC20(askToken).safeTransferFrom(msg.sender, order.owner, dealAskAmount.sub(feeAmount));
        IERC20(assetToken).safeTransfer(msg.sender, dealAssetAmount);
        
        order.assetAmount = order.assetAmount.sub(dealAssetAmount);
        order.askAmount = order.askAmount.sub(dealAskAmount);
        
        emit DealOrder(orderId, block.timestamp, msg.sender, dealAskAmount);
    }

    // ============== GOV =============== 
    function setFeeFund(address _feeFund) public onlyOperator {
        feeFund = _feeFund;
    }

    function setCreateFee(uint256 _createFee) public onlyOperator {
        createFee = _createFee;
    }

    function setDealFeeRate(uint256 _dealFeeRate) public onlyOperator {
        dealFeeRate = _dealFeeRate;
    }

    function setMaxExpirePeroid(uint256 _maxExpirePeroid) public onlyOperator {
        maxExpirePeroid = _maxExpirePeroid;
    }

}