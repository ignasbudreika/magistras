/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

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

contract OffChainDAO is DAO, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    error InvalidRequestId(bytes32 requestId);

    struct RequestData {
        uint256 blockNumber;
        uint256 proposalsCount;
        uint32 totalCapital;
    }
    
    uint64 private subId;
    bytes32 private donId;

    string private source;
    string private fetchAddress;
    bytes private secrets;

    uint32 private functionResultGasLimit = 500000;

    mapping(bytes32 => RequestData) private requestsData;
    bytes32[] private pendingRequests;

    constructor(address _router, uint64 _subId, bytes32 _donId) FunctionsClient(_router) DAO() {
        subId = _subId;
        donId = _donId;
    }

    function setFunctionData(string memory _source, bytes memory _secrets, string calldata _fetchAddress) external {
        require(msg.sender == owner, "Sender is not contract owner");

        secrets = _secrets;
        source = _source;
        fetchAddress = _fetchAddress;
    }

    function updatFunctionResultGasLimit(uint32 _gasLimit) external {
        require(msg.sender == owner, "Sender is not contract owner");

        require(_gasLimit > 21000, "Invalid gas limit");
        functionResultGasLimit = _gasLimit;
    }

    /// @dev Implements off-chain based knapsack solution
    function calculateMaxROI(uint32 _totalCapital) internal override {
        require(bytes(fetchAddress).length > 0, "Proposals fetch address not set");
        require(bytes(source).length > 0, "Source code not set");

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        req.addSecretsReference(secrets);

        string[] memory args = new string[](2);
        args[0] = fetchAddress;
        args[1] = Strings.toString(_totalCapital);
        req.setArgs(args);
        
        bytes32 requestId = _sendRequest(req.encodeCBOR(), subId, functionResultGasLimit, donId);

        // pendingRequests.push(requestId);
        // requestsData[requestId] = RequestData(block.number, suggestedProposals.length, _totalCapital);
    }

    function fulfillRequest(bytes32 _requestId, bytes memory response, bytes memory err) internal override {
        require(pendingRequests.length > 0, "All requests are already processed");

        bool requestExists = false;
        uint256 requestIndex = 0;
        for (uint256 i = 0; i < pendingRequests.length; i++) {
            if (_requestId == pendingRequests[i]) {
                requestExists = true;
                requestIndex = i;
                break;
            }
        }
        if (!requestExists) {
            revert InvalidRequestId(_requestId);
        } 
        
        if (err.length != 0) {
            delete requestsData[_requestId];
            delete pendingRequests[requestIndex];

            return;
        }

        uint256 result = abi.decode(response, (uint256));

        RequestData memory data = requestsData[_requestId];

        resultBlockNumber = data.blockNumber;
        proposalsCount = data.proposalsCount;
        totalCapital = data.totalCapital;
        maxROI = uint32(result);

        emit MaxROIResult(data.blockNumber, data.proposalsCount, data.totalCapital, uint32(result));

        delete requestsData[_requestId];
        delete pendingRequests[requestIndex];
    }

    function getElements(uint256 page, uint256 size) external view returns (uint16[] memory, uint16[] memory) {
        require(size > 0, "Invalid page size");

        if (page * size >= suggestedProposals.length) {
            return (new uint16[](0), new uint16[](0));
        }

        uint256 from = page * size;
        uint256 to = page * size + size;
        if (to > suggestedProposals.length) {
            to = suggestedProposals.length;
        }

        uint16[] memory rois = new uint16[](to - from);
        uint16[] memory amounts = new uint16[](to - from);
        for (uint i = from; i < to; i++) {
            Proposal memory proposal = suggestedProposals[i];
            rois[i - from] = proposal.estimatedROI;
            amounts[i - from] = proposal.investmentAmount;
        }

        return (rois, amounts);
    }

    function getPendingFunctionRequests() external view returns(bytes32[] memory) {
        return pendingRequests;
    }

    function getRequestData(bytes32 _requestId) external view returns (RequestData memory) {
        bool requestExists = false;
        for (uint256 i = 0; i < pendingRequests.length; i++) {
            if (_requestId == pendingRequests[i]) {
                requestExists = true;
                break;
            }
        }
        if (!requestExists) {
            revert InvalidRequestId(_requestId);
        } 

        return requestsData[_requestId];
    }

    /// @notice Resets Function request ID (results in failure to accept previous unprocessed calculation results)
    function deletePendingRequestData(bytes32 _requestId) external {
        require(msg.sender == owner, "Sender is not contract owner");

        bool requestExists = false;
        uint256 requestIndex = 0;
        for (uint256 i = 0; i < pendingRequests.length; i++) {
            if (_requestId == pendingRequests[i]) {
                requestExists = true;
                requestIndex = i;
                break;
            }
        }
        if (!requestExists) {
            revert InvalidRequestId(_requestId);
        } 

        delete requestsData[_requestId];
        delete pendingRequests[requestIndex];
    }
}
