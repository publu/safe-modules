pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/interfaces/ISignatureValidator.sol";
import "@gnosis.pm/safe-contracts/contracts/base/Module.sol";

/// @title ExecutionModule
/// @notice A Gnosis Safe module that enables a single multisig owner to 
/// execute transactions after a 1-week delay.

contract ExecutionModule is Module {
    
    uint256 public delay =  1 weeks;
    uint256 public constant maxDelay = 4 weeks;

    struct Execution {
        uint256 timestamp;
        bytes32 txHash;
        bytes signature;
        bool executed;
    }

    uint8 public constant version = 1;

    mapping(address => mapping(bytes32 => Execution)) public executionRequests;
    
    /// @notice Emitted when a new execution request is created.
    event ExecutionCreated(address indexed safe, bytes32 indexed executionRequestId);

    /// @notice Emitted when the delay is updated.
    event MinimumDelayChanged(uint256 newdelay);

    /// @notice Creates an execution request with a valid signature from one of the multisig owners.
    /// @param safe The address of the Gnosis Safe.
    /// @param txHash The transaction hash of the transaction to be executed.
    /// @param signature The signature of the transaction hash by one of the multisig owners.
    function createExecution(address safe, bytes32 txHash, bytes calldata signature) external {
        require(txHash != 0, "Invalid transaction hash");
        require(signature.length > 0, "Invalid signature");

        // Validate the signature
        bytes32 messageHash = ISignatureValidator(manager()).getMessageHash(txHash);
        address signer = ISignatureValidator(manager()).recover(messageHash, signature);
        require(manager().isOwner(signer), "Signer is not an owner");

        // Create a execution request
        bytes32 executionRequestId = keccak256(abi.encodePacked(txHash, signer));
        require(executionRequests[safe][executionRequestId].timestamp == 0, "Execution request already exists");

        executionRequests[safe][executionRequestId] = Execution({
            timestamp: block.timestamp,
            txHash: txHash,
            signature: signature,
            executed: false
        });

        emit ExecutionCreated(safe, executionRequestId);
    }

    /// @notice Executes an execution request after a 1-week delay has passed.
    /// @param safe The address of the Gnosis Safe.
    /// @param executionRequestId The unique identifier of the execution request.
    function executeExecution(address safe, bytes32 executionRequestId) external {
        Execution storage request = executionRequests[safe][executionRequestId];
        require(request.timestamp > 0, "Execution request not found");
        require(block.timestamp >= request.timestamp + 1 weeks, "1 week delay not passed");
        require(!request.executed, "Execution request already executed");

        // Recover the signer from the stored signature
        bytes32 messageHash = ISignatureValidator(manager()).getMessageHash(request.txHash);
        address signer = ISignatureValidator(manager()).recover(messageHash, request.signature);

        // Check if the signer is still an owner
        require(manager().isOwner(signer), "Signer is no longer an owner");

        // Mark the execution request as executed
        request.executed = true;
    }

    /// @notice Cancels an existing execution request.
    /// @param safe The address of the Gnosis Safe.
    /// @param executionRequestId The unique identifier of the execution request.
    function cancelExecution(address safe, bytes32 executionRequestId) external {
        Execution storage request = executionRequests[safe][executionRequestId];
        require(request.timestamp > 0, "Execution request not found");
        require(!request.executed, "Execution request already executed");

        // Recover the signer from the stored signature
        bytes32 messageHash = ISignatureValidator(manager()).getMessageHash(request.txHash);
        address signer = ISignatureValidator(manager()).recover(messageHash, request.signature);

        // Check if the signer is still an owner
        require(manager().isOwner(signer), "Signer is not an owner");

        // Delete the execution request
        delete executionRequests[safe][executionRequestId];

        // Emit the ExecutionCanceled event
        emit ExecutionCanceled(safe, executionRequestId);
    }

    /// @notice Changes the delay period for execution requests.
    /// @param _delay The new delay in seconds.
    /// @dev Callable only by the Gnosis Safe manager.
    function changeDelay(uint256 _delay) external {
        require(msg.sender == address(manager()), "Caller is not the Gnosis Safe manager");
        require(_delay <= maxDelay, "changeDelay: delay must be less than 4 weeks");
        delay = _delay;

        emit MinimumDelayChanged(_delay);
    }
}