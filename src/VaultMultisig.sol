/// SPDX-License-Identifier: MIT
/// @title: Contract for wallet with multisig withdraw functionality.
/// @notice: Allows to withdraw funds from the vault only if a certain number of signers approve the transaction.
/// @author: Solidity University
pragma solidity ^0.8.30;

contract VaultMultisig {
    /// @notice The number of signatures required to execute a transaction
    uint256 public quorum;

    /// @notice The number of transfers executed
    uint256 public transfersCount;

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

    /// @notice The mapping of transfer IDs to transfer details
    mapping(uint256 => Transfer) private transfers;

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

    /// @notice Checks that the signer is already approved
    /// @param signer The address of the signer
    error SignerAlreadyApproved(address signer);

    /// @notice Checks that the transfer failed
    /// @param transferId The ID of the transfer
    error TransferFailed(uint256 transferId);

    /// @notice Cheks that contract balance is positiv
    error VaultIsEmpty();

    /// @notice Checks that quorum was reached for transfer
    /// @param transferId The ID of the transfer
    error QuorumHasNotBeenReached(uint256 transferId);

    /// @notice Checks that the signer is a multisig admin
    error InvalidMultisigAdmin();

    /// @notice Emitted when a transfer is initiated
    event TransferInitiated(uint256 indexed transferId, address indexed to, uint256 amount);

    /// @notice Emitted when a transfer is approved
    /// @param transferId The ID of the transfer
    /// @param approver The address of the approver
    event TransferApproved(uint256 indexed transferId, address indexed approver);

    /// @notice Emitted when a transfer is executed
    /// @param transferId The ID of the transfer
    event TransferExecuted(uint256 indexed transferId);

    /// @notice Emitted when the multisig signers are updated
    event MultiSigSignersUpdated();

    /// @notice Emitted when the quorum is updated
    /// @param quorum The new quorum
    event QuorumUpdated(uint256 quorum);

    modifier onlyMultisigSigner() {
        if (!multiSigSigners[msg.sender]) revert InvalidMultisigSigner();
        _;
    }

    /// @notice Initializes the multisig contract
    /// @param _signers The array of multisig signers
    /// @param _quorum The number of signatures required to execute a transaction
    constructor(address[] memory _signers, uint256 _quorum) {
        if (_signers.length == 0) revert SignersArrayCannotBeEmpty();
        if (_quorum > _signers.length) revert QuorumGreaterThanSigners();
        if (_quorum == 0) revert QuorumCannotBeZero();

        for (uint256 i = 0; i < _signers.length; i++) {
            multiSigSigners[_signers[i]] = true;
        }

        quorum = _quorum;
    }

    /// @notice Initiates a transfer
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function initiateTransfer(address _to, uint256 _amount) external onlyMultisigSigner {
        if (_to == address(0)) revert InvalidRecipient();
        if (_amount <= 0) revert InvalidAmount();
        if (address(this).balance <= 0) revert VaultIsEmpty();

        uint256 transferId = transfersCount++;
        Transfer storage transfer = transfers[transferId];
        transfer.to = _to;
        transfer.amount = _amount;
        transfer.approvals = transfer.approvals + 1;
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
        if (transfer.amount > balance) revert InsufficientBalance(balance, transfer.amount);

        (bool success,) = transfer.to.call{value: transfer.amount}("");
        if (!success) revert TransferFailed(_transferId);

        transfer.executed = true;

        emit TransferExecuted(_transferId);
    }

    /// @notice Updates the list of multisig signers and sets a new quorum
    /// @dev Only callable by all current signers via consensus (i.e., must call from multisig itself)
    /// @param newSigners The new array of signer addresses
    /// @param newQuorum The new required quorum
    function updateSignersAndQuorum(address[] calldata newSigners, uint256 newQuorum) external onlyMultisigSigner {
        if (newSigners.length == 0) revert SignersArrayCannotBeEmpty();
        if (newQuorum == 0) revert QuorumCannotBeZero();
        if (newQuorum > newSigners.length) revert QuorumGreaterThanSigners();

        // Clear old signers
        for (uint256 i = 0; i < currentMultiSigSigners.length; i++) {
            multiSigSigners[currentMultiSigSigners[i]] = false;
        }

        delete currentMultiSigSigners;

        // Set new signers
        for (uint256 i = 0; i < newSigners.length; i++) {
            address signer = newSigners[i];
            require(signer != address(0), "Zero address in signers");
            multiSigSigners[signer] = true;
            currentMultiSigSigners.push(signer);
        }

        quorum = newQuorum;
        emit MultiSigSignersUpdated();
        emit QuorumUpdated(newQuorum);
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

    /// @notice Checks if a signer has signed a transfer
    /// @param _transferId The ID of the transfer
    /// @param _signer The address of the signer
    /// @return hasSigned Whether the signer has signed the transfer
    function hasSignedTransfer(uint256 _transferId, address _signer) external view returns (bool) {
        Transfer storage transfer = transfers[_transferId];
        return transfer.approved[_signer];
    }

    /// @notice Gets the number of transfers
    /// @return The number of transfers
    function getTransferCount() external view returns (uint256) {
        return transfersCount;
    }
}
