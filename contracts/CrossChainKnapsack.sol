/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

/// @title Knapsack problem algorithm for cross-chain solution
/// @author Ignas Budreika
contract CrossChainKnapsack is CCIPReceiver {

    event MaxValueCalculatedEvent(bytes32 callbackMessageId, bytes32 messageId, uint32 maxWeight);

    error NotEnoughBalance(uint256 balance, uint256 fees);
    error InvalidMessageId(bytes32 messageId);    

    /// @title Represents a CCIP request message from source contract
    struct CCIPRequest {
        Element[] elements;
        uint32 maxWeight;
    }

    /// @title Represents a CCIP result message for source contract
    struct CCIPResult {
        bytes32 messageId;
        uint32 maxWeight;
    }

    struct Element {
        uint16 value;
        uint16 weight;
    }

    address private owner;

    IRouterClient private ccipRouter;
    LinkTokenInterface private linkToken;

    uint64 private initiatorChainID = 1;
    address private initiatorContract = address(1);
    
    mapping(bytes32 => CCIPRequest) private messagesData;
    bytes32[] private pendingMessages;

    /// @param _router The address of the router contract
    /// @param _link The address of the link contract
    constructor(address _router, address _link) CCIPReceiver(_router) {
        owner = msg.sender;

        ccipRouter = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
    }

    /// @notice Sets cross-chain based solution initiator contract
    /// @param _initiatorChainID CCIP chain identifier of initiator network chain
    /// @param _initiatorContract Initiator contract address on source chain
    function setInitiatorLocation(uint64 _initiatorChainID, address _initiatorContract) external {
        require(msg.sender == owner, "Sender is not contract owner");

        initiatorChainID = _initiatorChainID;
        initiatorContract = _initiatorContract;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        uint64 _initiatorChainID = initiatorChainID;
        require(_initiatorChainID != 1 && message.sourceChainSelector == _initiatorChainID, "Unexpected CCIP message source network chain ID");

        address _initiatorContract = initiatorContract;
        require(_initiatorContract != address(1) && abi.decode(message.sender, (address)) == _initiatorContract, "Unexpected CCIP message sender");

        CCIPRequest memory request = abi.decode(message.data, (CCIPRequest));
        require(request.elements.length > 0, "Knapsack elements not provided");
        require(request.maxWeight > 0, "Knapsack capacity not provided");

        bytes32 messageId = message.messageId;

        pendingMessages.push(messageId);

        messagesData[messageId].maxWeight = request.maxWeight;
        for (uint32 i = 0; i < request.elements.length; i++) {
            messagesData[messageId].elements.push(Element(request.elements[i].value, request.elements[i].weight));
        }
    }

    function sendResultCallback(bytes32 _messageId, uint256 _ccipGasLimit) external {
        require(msg.sender == owner, "Sender is not contract owner");

        uint64 _initiatorChainID = initiatorChainID;
        address _initiatorContract = initiatorContract;
        require(_initiatorChainID != 1 && _initiatorContract != address(1), "CCIP response call destination must be set");

        require(pendingMessages.length > 0, "No pending messages exist");
        
        bool messageExists = false;
        uint256 messageIndex = 0;
        for (uint256 i = 0; i < pendingMessages.length; i++) {
            if (_messageId == pendingMessages[i]) {
                messageExists = true;
                messageIndex = i;
                break;
            }
        }
        if (!messageExists) {
            revert InvalidMessageId(_messageId);
        } 

        CCIPRequest memory request = messagesData[_messageId];
        uint32 result = calculateKnapsackResult(request.elements, request.maxWeight);
       
        CCIPResult memory data = CCIPResult(_messageId, result);
        LinkTokenInterface _linkToken = linkToken;
        IRouterClient _ccipRouter = ccipRouter;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(initiatorContract),
            data: abi.encode(data),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: _ccipGasLimit,
                    allowOutOfOrderExecution: false
                })
            ),
            feeToken: address(_linkToken)
        });

        uint256 fees = _ccipRouter.getFee(_initiatorChainID, message);
        if (fees > _linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(_linkToken.balanceOf(address(this)), fees);
        }

        _linkToken.approve(address(_ccipRouter), fees);
        bytes32 callbackMessageId = _ccipRouter.ccipSend(_initiatorChainID, message);

        emit MaxValueCalculatedEvent(callbackMessageId, _messageId, result);

        delete pendingMessages[messageIndex];
        delete messagesData[_messageId];
    }

    /// @dev Implements space-optimized dynamic programming algorithm
    function calculateKnapsackResult(Element[] memory _elements, uint32 _maxWeight) private pure returns (uint32) {
        uint32[] memory dynamicValues = new uint32[](_maxWeight + 1);
        
        for (uint16 i = 0; i < _elements.length; i++) {
            for (uint32 weight = _maxWeight; weight > 0; weight--) {
                
                uint32 partialWeight = _elements[i].weight;
                if (partialWeight <= weight) {
                    uint32 tempValue = dynamicValues[weight - partialWeight] + _elements[i].value;
                    if (tempValue > dynamicValues[weight]) {
                        dynamicValues[weight] = tempValue;
                    }
                }
            }
        }

        return dynamicValues[_maxWeight];
    }

    function getInitiatorContract() external view returns (uint256, address) {
        return (initiatorChainID, initiatorContract);
    }

    function getPendingCCIPMessages() external view returns(bytes32[] memory) {
        return pendingMessages;
    }

    function getCCIPRequest(bytes32 _messageId) external view returns (CCIPRequest memory) {
        bool messageExists = false;
        for (uint256 i = 0; i < pendingMessages.length; i++) {
            if (_messageId == pendingMessages[i]) {
                messageExists = true;
                break;
            }
        }
        if (!messageExists) {
            revert InvalidMessageId(_messageId);
        } 

        return messagesData[_messageId];
    }
}
