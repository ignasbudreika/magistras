/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

/// @title PoC DAO example smart contract for 0/1 knapsack problem
/// @author Ignas Budreika
abstract contract DAO {

    event MaxROIResult(uint256 blockNumber, uint256 proposalsCount, uint32 totalCapital, uint32 maxROI);

    /// @title Represents knapsack problem element
    /// @notice estimatedROI - element value
    /// @notice investmentAmount - element weight
    struct Proposal {
        uint16 estimatedROI;
        uint16 investmentAmount;
    }

    struct ProposalsResult {
        uint256 blockNumber;
        uint256 proposalsCount;
        uint32 totalCapital;
        uint32 maxROI;
    }

    Proposal[] internal suggestedProposals;  // Investment proposals suggested by DAO members

    uint256 internal resultBlockNumber = 1;
    uint256 internal proposalsCount = 1;
    uint32 internal totalCapital = 1;
    uint32 internal maxROI = 1;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Allows to suggest new investment proposal
    /// @param _ROI Expected return on investment
    /// @param _amount Required investment amount
    function propose(uint16 _ROI, uint16 _amount) external {
        suggestedProposals.push(Proposal(_ROI, _amount));
    }

    /// @notice Allows to suggest new investment proposals in bulk
    function bulkPropose(uint16[] calldata _ROIs, uint16[] calldata _amounts) external {
        require(_ROIs.length == _amounts.length, "Input arrays must have the same length");
        require(_ROIs.length > 0, "Input arrays must not be empty");

        for (uint16 i = 0; i < _ROIs.length; i++) {
            suggestedProposals.push(Proposal(_ROIs[i], _amounts[i]));
        }
    }

    /// @param _totalCapital Represents knapsack capacity
    function calculate(uint32 _totalCapital) external {
        require(msg.sender == owner, "Only owner is allowed to init max ROI calculation");

        require(suggestedProposals.length > 0, "No proposals were suggested yet");
        calculateMaxROI(_totalCapital);
    }

    /// @dev Implementation depends on chosen solution
    /// @dev Result should be stored by updating resultBlockNumber/totalCapital/count/selectedProposals
    /// @dev Result should be sent to MaxROICalculatedEvent
    function calculateMaxROI(uint32 _totalCapital) internal virtual;

    /// @notice Deletes DAO proposals and previous selections
    function resetProposals() external {
        require(msg.sender == owner, "Only owner is allowed to reset suggested proposals");

        delete suggestedProposals;
        resultBlockNumber = 1;
    }

    function getProposalsCount() external view returns (uint256) {
        return suggestedProposals.length;
    }

    function getProposal(uint256 _index) external view returns (Proposal memory) {
        require(_index < suggestedProposals.length, "Out of suggested proposals bounds");

        return suggestedProposals[_index];
    }
    
    function getProposalsResult() external view returns (ProposalsResult memory) {
        require(resultBlockNumber > 1, "Result is not yet calculated");

        return ProposalsResult(resultBlockNumber, proposalsCount, totalCapital, maxROI);
    }
}

contract CrossChainDAO is CCIPReceiver, DAO {

    error NotEnoughBalance(uint256 balance, uint256 fees);
    error InvalidMessageId(bytes32 messageId);

    /// @title Represents a CCIP request message to solution contract
    struct CCIPRequest {
        Proposal[] proposals;
        uint32 totalCapital;
    }

    /// @title Represents a CCIP result message received from solution contract
    struct CCIPResult {
        bytes32 messageId;
        uint32 maxROI;
    }

    struct MessageData {
        uint256 blockNumber;
        uint256 proposalsCount;
        uint32 totalCapital;
    }

    IRouterClient private ccipRouter;
    LinkTokenInterface private linkToken;
    uint64 private solutionChainID;
    address private solutionContract;
    uint256 private ccipGasLimit = 500000;

    mapping(bytes32 => MessageData) private messagesData;
    bytes32[] private pendingMessages;

    /// @param _router The address of the router contract
    /// @param _link The address of the link contract
    constructor(address _router, address _link, uint64 _solutionChainID, address _solutionContract) CCIPReceiver(_router) DAO() {
        ccipRouter = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        solutionChainID = _solutionChainID;
        solutionContract = _solutionContract;
    }

    /// @notice Updates CCIP-based knapsack problem solution contract and chain ID
    /// @param _solutionChainID CCIP chain identifier of selected solution network chain
    /// @param _solutionContract Solution contract address on destination chain
    function updateSolutionContract(uint64 _solutionChainID, address _solutionContract) external {
        require(msg.sender == owner, "Sender is not contract owner");
        
        require(pendingMessages.length == 0, "Pending messages exist");

        solutionChainID = _solutionChainID;
        solutionContract = _solutionContract;
    }

    function updateCCIPGasLimit(uint256 _ccipGasLimit) external {
        require(msg.sender == owner, "Sender is not contract owner");

        require(_ccipGasLimit > 21000, "Invalid gas limit");
        ccipGasLimit = _ccipGasLimit;
    }

    /// @dev Implements CCIP-based knapsack solution
    function calculateMaxROI(uint32 _totalCapital) internal override {
        require(msg.sender == owner, "Sender is not contract owner");

        uint64 _solutionChainID = solutionChainID;
        address _solutionContract = solutionContract;

        CCIPRequest memory data = CCIPRequest(suggestedProposals, _totalCapital);
        LinkTokenInterface _linkToken = linkToken;
        IRouterClient _ccipRouter = ccipRouter;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_solutionContract),
            data: abi.encode(data),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: ccipGasLimit,
                    allowOutOfOrderExecution: false
                })
            ),
            feeToken: address(_linkToken)
        });

        uint256 fees = _ccipRouter.getFee(_solutionChainID, message);
        if (fees > _linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(_linkToken.balanceOf(address(this)), fees);
        }

        _linkToken.approve(address(_ccipRouter), fees);

        bytes32 messageId = _ccipRouter.ccipSend(_solutionChainID, message);
        
        pendingMessages.push(messageId);
        messagesData[messageId] = MessageData(block.number, suggestedProposals.length, _totalCapital);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        uint64 _solutionChainID = solutionChainID;
        require(_solutionChainID != 0 && message.sourceChainSelector == _solutionChainID, "Invalid CCIP message source network chain ID");

        address _solutionContract = solutionContract;
        require(_solutionContract != address(0) && abi.decode(message.sender, (address)) == _solutionContract, "Invalid CCIP message sender");

        require(pendingMessages.length > 0, "All messages are already processed");

        CCIPResult memory response = abi.decode(message.data, (CCIPResult));
        bytes32 messageId = response.messageId;

        bool messageExists = false;
        uint256 messageIndex = 0;
        for (uint256 i = 0; i < pendingMessages.length; i++) {
            if (messageId == pendingMessages[i]) {
                messageExists = true;
                messageIndex = i;
                break;
            }
        }
        if (!messageExists) {
            revert InvalidMessageId(messageId);
        } 

        MessageData memory data = messagesData[messageId];

        resultBlockNumber = data.blockNumber;
        proposalsCount = data.proposalsCount;
        totalCapital = data.totalCapital;
        maxROI = response.maxROI;

        emit MaxROIResult(data.blockNumber, data.proposalsCount, data.totalCapital, response.maxROI);

        delete messagesData[messageId];
        delete pendingMessages[messageIndex];
    }

    function getSolutionContract() external view returns (uint256, address) {
        return (solutionChainID, solutionContract);
    }

    function getPendingCCIPMessages() external view returns(bytes32[] memory) {
        return pendingMessages;
    }

    function getMessageData(bytes32 _messageId) external view returns (MessageData memory) {
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

    /// @notice Resets CCIP messageId (results in failure to accept previous unprocessed calculation results)
    function deletePendingMessageData(bytes32 _messageId) external {
        require(msg.sender == owner, "Sender is not contract owner");

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

        delete messagesData[_messageId];
        delete pendingMessages[messageIndex];
    }
}
