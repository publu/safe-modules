// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing the necessary Gnosis Safe contracts
import "@gnosis.pm/safe-contracts/contracts/interfaces/ISignatureValidator.sol";
import "@gnosis.pm/safe-contracts/contracts/base/Module.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "@gnosis.pm/safe-contracts/contracts/interfaces/IGnosisSafe.sol";

/// @title WhitelistedExecutionModule
/// @notice A module for the Gnosis Safe Multisig wallet which allows whitelisted addresses 
/// to propose transactions with a delay before execution. Only the multisig can add or remove
/// addresses from the whitelist.
contract WhitelistedExecutionModule is Module {
    
    // The delay before a proposed transaction can be executed, default to 1 week.
    uint256 public delay = 1 weeks;

    // The maximum delay that can be set.
    uint256 public constant maxDelay = 4 weeks;

    // Execution struct represents a proposed transaction.
    struct Execution {
        uint256 timestamp;       // When the transaction was proposed.
        address to;              // The recipient address of the transaction.
        uint256 value;           // The amount of ether to send.
        bytes data;              // Data payload of the transaction.
        Enum.Operation operation; // Operation type of the transaction.
        bool executed;           // Whether the transaction has been executed or not.
    }

    // SafeSettings struct to keep track of proposers for each Safe.
    struct SafeSettings {
        mapping(address => bool) proposerWhitelist;  // A mapping of whitelisted proposers.
    }

    // A mapping to store Safe settings for each Safe address.
    mapping(address => SafeSettings) public safeSettings;

    // A mapping to store all the proposed transactions.
    mapping(address => mapping(bytes32 => Execution)) public executionRequests;

    // Emitted when a new proposed transaction is created.
    event ExecutionCreated(address indexed safe, bytes32 indexed executionRequestId);

    // Emitted when the delay is changed.
    event DelayChanged(uint256 newDelay);

    // Emitted when a proposer is added to the whitelist.
    event ProposerAdded(address indexed safe, address indexed proposer);

    // Emitted when a proposer is removed from the whitelist.
    event ProposerRemoved(address indexed safe, address indexed proposer);

    // Modifier to check if the caller is the manager (Safe Multisig).
    modifier onlyManager() {
        require(msg.sender == address(manager()), "Caller is not the manager");
        _;
    }

    // Modifier to check if the caller is a whitelisted proposer.
    modifier onlyValidProposer(address safe) {
        require(safeSettings[safe].proposerWhitelist[msg.sender], "Caller is not a proposer");
        _;
    }

    // Constructor to initialize the delay.
    constructor() {
        delay = 1 weeks;
    }

    /// @notice Allows a whitelisted proposer to propose a transaction.
    /// @param safe The address of the Gnosis Safe.
    /// @param to The address of the recipient.
    /// @param value The amount of ether to send.
    /// @param data The data payload of the transaction.
    /// @param operation The operation type of the transaction.
    function createExecution(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external onlyValidProposer(safe) {
        require(to != address(0), "Invalid target address");

        // Create a unique identifier for the proposed transaction.
        bytes32 executionRequestId = keccak256(abi.encodePacked(safe, to, value, data, operation));
        require(executionRequests[safe][executionRequestId].timestamp == 0, "Execution request already exists");

        // Create the proposed transaction and store it.
        executionRequests[safe][executionRequestId] = Execution({
            timestamp: block.timestamp,
            to: to,
            value: value,
            data: data,
            operation: operation,
            executed: false
        });

        emit ExecutionCreated(safe, executionRequestId);
    }

    /// @notice Allows a whitelisted proposer to execute a transaction after the delay.
    /// @param safe The address of the Gnosis Safe.
    /// @param executionRequestId The unique identifier of the proposed transaction.
    function executeExecution(address safe, bytes32 executionRequestId) external onlyValidProposer(safe) {
        Execution storage request = executionRequests[safe][executionRequestId];
        require(request.timestamp > 0, "Execution request not found");
        require(block.timestamp >= request.timestamp + delay, "Delay period not passed");
        require(!request.executed, "Execution request already executed");

        // Mark the transaction as executed.
        request.executed = true;

        // Execute the transaction using Gnosis Safe's execTransactionFromModule function.
        require(
            IGnosisSafe(safe).execTransactionFromModule(
                request.to, 
                request.value, 
                request.data, 
                request.operation
            ), 
            "Could not execute transaction"
        );
    }

    /// @notice Allows the manager (Safe Multisig) to change the delay period.
    /// @param _delay The new delay in seconds.
    function changeDelay(uint256 _delay) external onlyManager {
        require(_delay <= maxDelay, "Delay too long");
        delay = _delay;
        emit DelayChanged(delay);
    }

    /// @notice Allows the manager (Safe Multisig) to add a proposer to the whitelist.
    /// @param safe The address of the Gnosis Safe.
    /// @param proposer The address of the proposer to add.
    function addProposer(address safe, address proposer) external onlyManager {
        safeSettings[safe].proposerWhitelist[proposer] = true;
        emit ProposerAdded(safe, proposer);
    }

    /// @notice Allows the manager (Safe Multisig) to remove a proposer from the whitelist.
    /// @param safe The address of the Gnosis Safe.
    /// @param proposer The address of the proposer to remove.
    function removeProposer(address safe, address proposer) external onlyManager {
        safeSettings[safe].proposerWhitelist[proposer] = false;
        emit ProposerRemoved(safe, proposer);
    }
}