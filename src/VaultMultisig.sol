// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AccessManager.sol";

contract VaultMultisig {
    /// @notice The number of signatures required to execute a transaction
    uint256 public quorum;

    /// @notice The number of transfers executed
    uint256 public transfersCount;

    /// @notice The number of contract operations executed
    uint256 public operationsCount;

    /// @notice The access manager
    AccessManager public accessManager;

    /// @notice The current multisig signers
    address[] public currentMultiSigSigners;

    /// @dev The struct is used to store the details of a transfer
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param approvals The number of approvals required to execute the transfer
    /// @param executed Whether the transfer has been executed
    /// @param approved The mapping of signers to their approval status
    struct Transfer {
        address to;
        uint256 amount;
        uint256 approvals;
        bool executed;
        mapping(address => bool) approved;
    }

    /// @dev The struct is used to store the details of a contract operation
    /// @param target The target contract address
    /// @param data The encoded function call data
    /// @param description Human readable description
    /// @param approvals The number of approvals received
    /// @param executed Whether the operation has been executed
    /// @param approved The mapping of signers to their approval status
    struct Operation {
        address target;
        bytes data;
        string description;
        uint256 approvals;
        bool executed;
        mapping(address => bool) approved;
    }

    /// @notice The mapping of transfer IDs to transfer details
    mapping(uint256 => Transfer) private transfers;

    /// @notice The mapping of operation IDs to operation details
    mapping(uint256 => Operation) private operations;

    /// @notice The mapping for verification that address is a signer
    mapping(address => bool) private multiSigSigners;

    /// @notice Checks that signers array is not empty
    error SignersArrayCannotBeEmpty();

    /// @notice Checks that quorum is not greather than the number of signers
    error QuorumGreaterThanSigners();

    /// @notice Checks that quorum is greater than zero
    error QuorumCannotBeZero();

    /// @notice Checks that the recipient is not the zero address
    error InvalidRecipient();

    /// @notice Checks that amount is greater than zero
    error InvalidAmount();

    /// @notice Checks that the signer is a multisig signer
    error InvalidMultisigSigner();

    /// @notice Checks that the balance is sufficient for the transfer
    error InsufficientBalance(uint256 balance, uint256 desiredAmount);

    /// @notice Checks that the transfer is not already executed
    /// @param transferId The ID of the transfer
    error TransferIsAlreadyExecuted(uint256 transferId);

    /// @notice Checks that the operation is not already executed
    /// @param operationId The ID of the operation
    error OperationIsAlreadyExecuted(uint256 operationId);

    /// @notice Checks that the signer is already approved
    /// @param signer The address of the signer
    error SignerAlreadyApproved(address signer);

    /// @notice Checks that the transfer failed
    /// @param transferId The ID of the transfer
    error TransferFailed(uint256 transferId);

    /// @notice Checks that the operation failed
    /// @param operationId The ID of the operation
    error OperationFailed(uint256 operationId);

    /// @notice Checks that quorum was reached for transfer
    /// @param transferId The ID of the transfer
    error QuorumHasNotBeenReached(uint256 transferId);

    /// @notice Checks that quorum was reached for operation
    /// @param operationId The ID of the operation
    error OperationQuorumHasNotBeenReached(uint256 operationId);

    /// @notice Checks that the signer is a multisig admin
    error InvalidMultisigAdmin();

    /// @notice Checks that target address is not zero
    error InvalidTarget();

    /// @notice Checks that operation data is not empty
    error InvalidOperationData();

    /// @notice Emitted when a transfer is initiated
    event TransferInitiated(uint256 indexed transferId, address indexed to, uint256 amount);

    /// @notice Emitted when a transfer is approved
    /// @param transferId The ID of the transfer
    /// @param approver The address of the approver
    event TransferApproved(uint256 indexed transferId, address indexed approver);

    /// @notice Emitted when a transfer is executed
    /// @param transferId The ID of the transfer
    event TransferExecuted(uint256 indexed transferId);

    /// @notice Emitted when a contract operation is initiated
    event OperationInitiated(uint256 indexed operationId, address indexed target, string description);

    /// @notice Emitted when an operation is approved
    /// @param operationId The ID of the operation
    /// @param approver The address of the approver
    event OperationApproved(uint256 indexed operationId, address indexed approver);

    /// @notice Emitted when an operation is executed
    /// @param operationId The ID of the operation
    event OperationExecuted(uint256 indexed operationId);

    /// @notice Emitted when the multisig signers are updated
    event MultiSigSignersUpdated();

    /// @notice Emitted when the quorum is updated
    /// @param quorum The new quorum
    event QuorumUpdated(uint256 quorum);

    modifier onlyMultisigSigner() {
        if (!multiSigSigners[msg.sender]) revert InvalidMultisigSigner();
        _;
    }

    modifier onlyMultisigAdmin() {
        if (!accessManager.isMultisigAdmin(msg.sender)) revert InvalidMultisigAdmin();
        _;
    }

    /// @notice Initializes the multisig contract
    /// @param _signers The array of multisig signers
    /// @param _quorum The number of signatures required to execute a transaction
    constructor(address[] memory _signers, uint256 _quorum, address _accessManager) {
        if (_signers.length == 0) revert SignersArrayCannotBeEmpty();
        if (_quorum > _signers.length) revert QuorumGreaterThanSigners();
        if (_quorum == 0) revert QuorumCannotBeZero();

        for (uint256 i = 0; i < _signers.length; i++) {
            multiSigSigners[_signers[i]] = true;
        }

        currentMultiSigSigners = _signers;
        quorum = _quorum;
        accessManager = AccessManager(_accessManager);
    }

    /// @notice Updates the multisig signers
    /// @param _signers The array of multisig signers
    function updateSigners(address[] memory _signers) external onlyMultisigAdmin {
        if (_signers.length == 0) revert SignersArrayCannotBeEmpty();
        if (_signers.length < quorum) revert QuorumGreaterThanSigners();

        for (uint256 i = 0; i < currentMultiSigSigners.length; i++) {
            multiSigSigners[currentMultiSigSigners[i]] = false;
        }

        for (uint256 i = 0; i < _signers.length; i++) {
            multiSigSigners[_signers[i]] = true;
        }

        currentMultiSigSigners = _signers;

        emit MultiSigSignersUpdated();
    }

    /// @notice Updates the quorum
    /// @param _quorum The new quorum
    function updateQuorum(uint256 _quorum) external onlyMultisigAdmin {
        if (_quorum > currentMultiSigSigners.length) revert QuorumGreaterThanSigners();
        if (_quorum == 0) revert QuorumCannotBeZero();

        quorum = _quorum;

        emit QuorumUpdated(_quorum);
    }

    /// @notice Initiates a transfer
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function initiateTransfer(address _to, uint256 _amount) external onlyMultisigSigner {
        if (_to == address(0)) revert InvalidRecipient();
        if (_amount <= 0) revert InvalidAmount();

        uint256 transferId = transfersCount++;
        Transfer storage transfer = transfers[transferId];
        transfer.to = _to;
        transfer.amount = _amount;
        transfer.approvals = 1; // Count initiator
        transfer.executed = false;
        transfer.approved[msg.sender] = true;

        emit TransferInitiated(transferId, _to, _amount);
    }

    /// @notice Approves a transfer
    /// @param _transferId The ID of the transfer
    function approveTransfer(uint256 _transferId) external onlyMultisigSigner {
        Transfer storage transfer = transfers[_transferId];
        if (transfer.executed) revert TransferIsAlreadyExecuted(_transferId);
        if (transfer.approved[msg.sender]) revert SignerAlreadyApproved(msg.sender);

        transfer.approvals++;
        transfer.approved[msg.sender] = true;

        emit TransferApproved(_transferId, msg.sender);
    }

    function executeTransfer(uint256 _transferId) external onlyMultisigSigner {
        Transfer storage transfer = transfers[_transferId];
        if (transfer.approvals < quorum) revert QuorumHasNotBeenReached(_transferId);
        if (transfer.executed) revert TransferIsAlreadyExecuted(_transferId);

        uint256 balance = address(this).balance;
        if (transfer.amount >= balance) revert InsufficientBalance(balance, transfer.amount);

        (bool success,) = transfer.to.call{value: transfer.amount}("");
        if (!success) revert TransferFailed(_transferId);

        transfer.executed = true;

        emit TransferExecuted(_transferId);
    }

    /// @notice Initiates a contract operation (e.g., LiquidityPool function call)
    /// @param _target The target contract address
    /// @param _data The encoded function call data
    /// @param _description Human readable description of the operation
    function initiateOperation(address _target, bytes memory _data, string memory _description)
        public
        onlyMultisigSigner
    {
        if (_target == address(0)) revert InvalidTarget();
        if (_data.length == 0) revert InvalidOperationData();

        uint256 operationId = operationsCount++;
        Operation storage operation = operations[operationId];
        operation.target = _target;
        operation.data = _data;
        operation.description = _description;
        operation.approvals = 1; // Count initiator
        operation.executed = false;
        operation.approved[msg.sender] = true;

        emit OperationInitiated(operationId, _target, _description);
    }

    /// @notice Approves a contract operation
    /// @param _operationId The ID of the operation
    function approveOperation(uint256 _operationId) external onlyMultisigSigner {
        Operation storage operation = operations[_operationId];
        if (operation.executed) revert OperationIsAlreadyExecuted(_operationId);
        if (operation.approved[msg.sender]) revert SignerAlreadyApproved(msg.sender);

        operation.approvals++;
        operation.approved[msg.sender] = true;

        emit OperationApproved(_operationId, msg.sender);
    }

    /// @notice Executes a contract operation
    /// @param _operationId The ID of the operation
    function executeOperation(uint256 _operationId) external onlyMultisigSigner {
        Operation storage operation = operations[_operationId];
        if (operation.approvals < quorum) revert OperationQuorumHasNotBeenReached(_operationId);
        if (operation.executed) revert OperationIsAlreadyExecuted(_operationId);

        (bool success,) = operation.target.call(operation.data);
        if (!success) revert OperationFailed(_operationId);

        operation.executed = true;

        emit OperationExecuted(_operationId);
    }

    /// @notice Default fallback function for receiving ETH
    receive() external payable {}

    /// @notice Gets the details of a transfer
    /// @param _transferId The ID of the transfer
    /// @return to The address of the recipient
    /// @return amount The amount of tokens to transfer
    /// @return approvals The number of approvals required to execute the transfer
    /// @return executed Whether the transfer has been executed
    function getTransfer(uint256 _transferId)
        external
        view
        returns (address to, uint256 amount, uint256 approvals, bool executed)
    {
        Transfer storage transfer = transfers[_transferId];
        return (transfer.to, transfer.amount, transfer.approvals, transfer.executed);
    }

    /// @notice Gets the details of an operation
    /// @param _operationId The ID of the operation
    /// @return target The target contract address
    /// @return data The encoded function call data
    /// @return description The operation description
    /// @return approvals The number of approvals received
    /// @return executed Whether the operation has been executed
    function getOperation(uint256 _operationId)
        external
        view
        returns (address target, bytes memory data, string memory description, uint256 approvals, bool executed)
    {
        Operation storage operation = operations[_operationId];
        return (operation.target, operation.data, operation.description, operation.approvals, operation.executed);
    }

    /// @notice Checks if a signer has signed a transfer
    /// @param _transferId The ID of the transfer
    /// @param _signer The address of the signer
    /// @return hasSigned Whether the signer has signed the transfer
    function hasSignedTransfer(uint256 _transferId, address _signer) external view returns (bool) {
        Transfer storage transfer = transfers[_transferId];
        return transfer.approved[_signer];
    }

    /// @notice Checks if a signer has signed an operation
    /// @param _operationId The ID of the operation
    /// @param _signer The address of the signer
    /// @return hasSigned Whether the signer has signed the operation
    function hasSignedOperation(uint256 _operationId, address _signer) external view returns (bool) {
        Operation storage operation = operations[_operationId];
        return operation.approved[_signer];
    }

    /// @notice Gets the number of transfers
    /// @return The number of transfers
    function getTransferCount() external view returns (uint256) {
        return transfersCount;
    }

    /// @notice Gets the number of operations
    /// @return The number of operations
    function getOperationCount() public view returns (uint256) {
        return operationsCount;
    }
}
