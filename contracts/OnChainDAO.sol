/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

/// @title On-chain solution for calculating maximum ROI of DAO proposals
contract OnChainDAO is DAO {

    constructor() DAO() {}

    /// @dev Implements space-optimized dynamic programming algorithm
    function calculateMaxROI(uint32 _totalCapital) internal override {
        Proposal[] memory proposals = suggestedProposals;
        uint32[] memory dynamicROIs = new uint32[](_totalCapital + 1);
        
        for (uint16 i = 0; i < proposals.length; i++) {
            for (uint32 amount = _totalCapital; amount > 0; amount--) {
                
                uint32 partialAmount = proposals[i].investmentAmount;
                if (partialAmount <= amount) {
                    uint32 tempROI = dynamicROIs[amount - partialAmount] + proposals[i].estimatedROI;
                    if (tempROI > dynamicROIs[amount]) {
                        dynamicROIs[amount] = tempROI;
                    }
                }
            }
        }

        uint32 result = dynamicROIs[_totalCapital]; 

        resultBlockNumber = block.number;
        proposalsCount = proposals.length;
        totalCapital = _totalCapital;
        maxROI = result;

        emit MaxROIResult(block.number, proposals.length, _totalCapital, result);
    }
}
