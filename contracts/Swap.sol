pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import './owner/Operator.sol';

contract Swap is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public feeFund;
    address public createFeeToken;
    uint256 public createFee;
    uint256 public dealFeeRate;
    
    mapping (address => bool) public supportedAssetTokens;
    mapping (address => bool) public supportedAskTokens;
    uint256 public maxExpirePeroid;

    enum OrderStatus {
        ACTIVE,
        DONE,
        DELETE
    }

    struct Order {
        uint256 createTime;
        address owner;
        address assetToken;
        address askToken;
        uint256 assetAmount;
        uint256 askAmount;
        uint256 expire;
        OrderStatus status;
    }

    Order[] public orders;
    mapping (address => uint256[]) public userOrders;
    mapping (address => uint256) public userOrdersCount;

    event CreateOrder( 
        uint256 orderId, 
        uint256 timestamp,
        address onwer, 
        address assetToken, 
        uint256 assetAmount
    );
    event CancelOrder(
        uint256 orderId,
        uint256 timestamp
    );
    event DealOrder(
        uint256 orderId,
        uint256 timestamp,
        address deal,
        address bidToken,
        uint256 bidAmount
    );
    event DoneOrder(
        uint256 orderId,
        uint256 timestamp
    );

    constructor(
        address _feeFund,
        address _createFeeToken,
        uint256 _createFee,
        uint256 _dealFeeRate,
        uint256 _maxExpirePeroid
    ) public {
        feeFund = _feeFund;
        createFeeToken = _createFeeToken;
        createFee = _createFee;
        dealFeeRate = _dealFeeRate;
        maxExpirePeroid = _maxExpirePeroid;
    }

    // ============== ORDER OPERATION ====================
    function createOrder(
        address assetToken,
        address askToken,
        uint256 assetAmount,
        uint256 askAmount,
        uint256 expire
    ) public {
        uint256 expirePeriod = expire.sub(block.timestamp);
        require(expirePeriod <= maxExpirePeroid, "SWAP: expire invalid");

        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), assetAmount);
        if (createFee > 0) {
            IERC20(createFeeToken).safeTransferFrom(msg.sender, feeFund, createFee);
        }
        
        Order memory order;
        order.owner = msg.sender;
        order.createTime = block.timestamp;
        order.assetToken = assetToken;
        order.assetAmount = assetAmount;
        order.askToken = askToken;
        order.askAmount = askAmount;
        order.expire = expire;
        order.status = OrderStatus.ACTIVE;

        uint256 orderId = orders.length;
        orders.push(order);
        userOrders[msg.sender].push(orderId);
        userOrdersCount[msg.sender] = userOrdersCount[msg.sender].add(1);

        emit CreateOrder(orderId, block.timestamp, msg.sender, assetToken, assetAmount);
    }

    function cancelOrder(
        uint256 orderId
    ) public {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "SWAP: no owner");
        require(
            order.status == OrderStatus.ACTIVE,
            "SWAP: invalid order status"
        );
        IERC20(order.assetToken).safeTransfer(msg.sender, order.assetAmount);
        order.status = OrderStatus.DELETE;

        emit CancelOrder(orderId, block.timestamp);
    }

    function dealOrder(
        uint256 orderId
    ) public {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.ACTIVE, "SWAP: invalid order");
        require(block.timestamp >= order.expire, "SWAP: order expire");

        IERC20(order.askToken).safeTransferFrom(msg.sender, address(this), order.askAmount);
        IERC20(order.assetToken).safeTransfer(msg.sender, order.assetAmount);
        order.status = OrderStatus.DONE;

        emit DealOrder(orderId, block.timestamp, msg.sender, order.askToken, order.askAmount);
    }

    function doneOrder(
        uint256 orderId
    ) public {
        Order storage order = orders[orderId];
        require(order.owner == msg.sender, "SWAP: no owner");
        require(
            order.status == OrderStatus.DONE,
            "SWAP: invalid order status"
        );
        
        uint256 feeAmount = order.askAmount.mul(dealFeeRate).div(10000);
        uint256 amount = order.askAmount.sub(feeAmount);
        IERC20(order.askToken).safeTransfer(feeFund, feeAmount);
        IERC20(order.askToken).safeTransfer(msg.sender, amount);
        order.status = OrderStatus.DELETE;

        emit DoneOrder(orderId, block.timestamp);
    }

    // ============== GOV =============== 
    function setFeeFund(address _feeFund) public onlyOperator {
        feeFund = _feeFund;
    }

    function setCreateFeeToken(address _createFeeToken) public onlyOperator {
        createFeeToken = _createFeeToken;
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

    function setSupportedAssetTokens(address token, bool set) public onlyOperator {
        supportedAssetTokens[token] = set;
    }

    function setSupportedAskTokens(address token, bool set) public onlyOperator {
        supportedAskTokens[token] = set;
    }

}