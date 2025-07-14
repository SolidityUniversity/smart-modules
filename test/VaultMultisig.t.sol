// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/VaultMultisig.sol";
import "../src/AccessManager.sol";

contract VaultMultisigTest is Test {
    VaultMultisig public vault;
    AccessManager public accessManager;

    address public admin;
    address public multisigAdmin;
    address public signer1;
    address public signer2;
    address public signer3;
    address public nonSigner;
    address public recipient;

    address[] public signers;
    uint256 public constant QUORUM = 2;

    event TransferInitiated(uint256 indexed transferId, address indexed to, uint256 amount);
    event TransferApproved(uint256 indexed transferId, address indexed approver);
    event TransferExecuted(uint256 indexed transferId);
    event MultiSigSignersUpdated();
    event QuorumUpdated(uint256 quorum);

    function setUp() public {
        admin = makeAddr("admin");
        multisigAdmin = makeAddr("multisigAdmin");
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
        signer3 = makeAddr("signer3");
        nonSigner = makeAddr("nonSigner");
        recipient = makeAddr("recipient");

        // Setup access manager
        vm.prank(admin);
        accessManager = new AccessManager();

        vm.prank(admin);
        accessManager.addMultisigAdmin(multisigAdmin);

        // Setup signers array
        signers.push(signer1);
        signers.push(signer2);
        signers.push(signer3);

        // Deploy vault
        vault = new VaultMultisig(signers, QUORUM, address(accessManager));

        // Fund the vault
        vm.deal(address(vault), 10 ether);
    }

    function test_InitialState() public view {
        assertEq(vault.quorum(), QUORUM);
        assertEq(vault.transfersCount(), 0);
        assertEq(address(vault.accessManager()), address(accessManager));
        assertEq(address(vault).balance, 10 ether);
    }

    function test_Constructor_RevertWhen_EmptySignersArray() public {
        address[] memory emptySigners = new address[](0);

        vm.expectRevert(VaultMultisig.SignersArrayCannotBeEmpty.selector);
        new VaultMultisig(emptySigners, QUORUM, address(accessManager));
    }

    function test_Constructor_RevertWhen_QuorumGreaterThanSigners() public {
        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        new VaultMultisig(signers, 4, address(accessManager));
    }

    function test_Constructor_RevertWhen_QuorumIsZero() public {
        vm.expectRevert(VaultMultisig.QuorumCannotBeZero.selector);
        new VaultMultisig(signers, 0, address(accessManager));
    }

    function test_InitiateTransfer() public {
        uint256 amount = 1 ether;

        vm.prank(signer1);
        vm.expectEmit(true, true, false, true);
        emit TransferInitiated(0, recipient, amount);
        vault.initiateTransfer(recipient, amount);

        assertEq(vault.transfersCount(), 1);

        (address to, uint256 transferAmount, uint256 approvals, bool executed) = vault.getTransfer(0);
        assertEq(to, recipient);
        assertEq(transferAmount, amount);
        assertEq(approvals, 1); // Was 0, now 1 because initiator counts
        assertFalse(executed);
        assertTrue(vault.hasSignedTransfer(0, signer1));
    }

    function test_InitiateTransfer_RevertWhen_NotSigner() public {
        vm.prank(nonSigner);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(recipient, 1 ether);
    }

    function test_InitiateTransfer_RevertWhen_InvalidRecipient() public {
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.InvalidRecipient.selector);
        vault.initiateTransfer(address(0), 1 ether);
    }

    function test_InitiateTransfer_RevertWhen_InvalidAmount() public {
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.InvalidAmount.selector);
        vault.initiateTransfer(recipient, 0);
    }

    function test_ApproveTransfer() public {
        // First initiate a transfer
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        // Approve by another signer
        vm.prank(signer2);
        vm.expectEmit(true, true, false, false);
        emit TransferApproved(0, signer2);
        vault.approveTransfer(0);

        (,, uint256 approvals,) = vault.getTransfer(0);
        assertEq(approvals, 2); // Was 1, now 2 (initiator + one approval)
        assertTrue(vault.hasSignedTransfer(0, signer2));
    }

    function test_ApproveTransfer_RevertWhen_NotSigner() public {
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        vm.prank(nonSigner);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.approveTransfer(0);
    }

    function test_ApproveTransfer_RevertWhen_AlreadyApproved() public {
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.SignerAlreadyApproved.selector, signer1));
        vault.approveTransfer(0);
    }

    function test_ApproveTransfer_RevertWhen_AlreadyExecuted() public {
        // Create and execute a transfer
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        vm.prank(signer2);
        vault.approveTransfer(0);

        vm.prank(signer3);
        vault.executeTransfer(0);

        // Try to approve executed transfer
        vm.prank(signer2);
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.TransferIsAlreadyExecuted.selector, 0));
        vault.approveTransfer(0);
    }

    function test_ExecuteTransfer() public {
        uint256 amount = 1 ether;
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 vaultBalanceBefore = address(vault).balance;

        // Initiate transfer
        vm.prank(signer1);
        vault.initiateTransfer(recipient, amount);

        // Get one more approval to reach quorum
        vm.prank(signer2);
        vault.approveTransfer(0);

        // Execute transfer
        vm.prank(signer3);
        vm.expectEmit(true, false, false, false);
        emit TransferExecuted(0);
        vault.executeTransfer(0);

        // Verify transfer
        (,,, bool executed) = vault.getTransfer(0);
        assertTrue(executed);
        assertEq(recipient.balance, recipientBalanceBefore + amount);
        assertEq(address(vault).balance, vaultBalanceBefore - amount);
    }

    function test_ExecuteTransfer_RevertWhen_QuorumNotReached() public {
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        // Initiator counts as 1 approval, need 2 total for quorum, so 1 more needed
        // Try to execute with only initiator approval (should fail)
        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.QuorumHasNotBeenReached.selector, 0));
        vault.executeTransfer(0);
    }

    function test_ExecuteTransfer_RevertWhen_InsufficientBalance() public {
        uint256 amount = 15 ether; // More than vault balance

        vm.prank(signer1);
        vault.initiateTransfer(recipient, amount);

        vm.prank(signer2);
        vault.approveTransfer(0);

        vm.prank(signer3);
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.InsufficientBalance.selector, 10 ether, amount));
        vault.executeTransfer(0);
    }

    function test_ExecuteTransfer_RevertWhen_AlreadyExecuted() public {
        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);

        vm.prank(signer2);
        vault.approveTransfer(0);

        vm.prank(signer3);
        vault.executeTransfer(0);

        // Try to execute again
        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.TransferIsAlreadyExecuted.selector, 0));
        vault.executeTransfer(0);
    }

    function test_UpdateSigners() public {
        // First set current signers via constructor, then update
        address[] memory newSigners = new address[](2);
        newSigners[0] = makeAddr("newSigner1");
        newSigners[1] = makeAddr("newSigner2");

        vm.prank(multisigAdmin);
        vault.updateSigners(newSigners);
        // This should succeed, not revert
    }

    function test_UpdateSigners_RevertWhen_NotMultisigAdmin() public {
        address[] memory newSigners = new address[](2);
        newSigners[0] = makeAddr("newSigner1");
        newSigners[1] = makeAddr("newSigner2");

        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.InvalidMultisigAdmin.selector);
        vault.updateSigners(newSigners);
    }

    function test_UpdateSigners_RevertWhen_EmptyArray() public {
        address[] memory emptySigners = new address[](0);

        vm.prank(multisigAdmin);
        vm.expectRevert(VaultMultisig.SignersArrayCannotBeEmpty.selector);
        vault.updateSigners(emptySigners);
    }

    function test_UpdateSigners_RevertWhen_LessThanQuorum() public {
        address[] memory newSigners = new address[](1); // Less than current quorum of 2
        newSigners[0] = makeAddr("newSigner1");

        vm.prank(multisigAdmin);
        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        vault.updateSigners(newSigners);
    }

    function test_UpdateQuorum() public {
        uint256 newQuorum = 3;

        vm.prank(multisigAdmin);
        vault.updateQuorum(newQuorum);

        assertEq(vault.quorum(), newQuorum);
    }

    function test_UpdateQuorum_RevertWhen_NotMultisigAdmin() public {
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.InvalidMultisigAdmin.selector);
        vault.updateQuorum(3);
    }

    function test_UpdateQuorum_RevertWhen_GreaterThanSigners() public {
        vm.prank(multisigAdmin);
        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        vault.updateQuorum(4); // More than 3 signers
    }

    function test_UpdateQuorum_RevertWhen_Zero() public {
        vm.prank(multisigAdmin);
        vm.expectRevert(VaultMultisig.QuorumCannotBeZero.selector);
        vault.updateQuorum(0);
    }

    function test_GetTransferCount() public {
        assertEq(vault.getTransferCount(), 0);

        vm.prank(signer1);
        vault.initiateTransfer(recipient, 1 ether);
        assertEq(vault.getTransferCount(), 1);

        vm.prank(signer2);
        vault.initiateTransfer(recipient, 2 ether);
        assertEq(vault.getTransferCount(), 2);
    }

    function test_ReceiveEther() public {
        uint256 balanceBefore = address(vault).balance;

        vm.deal(admin, 5 ether);
        vm.prank(admin);
        (bool success,) = address(vault).call{value: 5 ether}("");

        assertTrue(success);
        assertEq(address(vault).balance, balanceBefore + 5 ether);
    }

    function test_CompleteWorkflow() public {
        uint256 amount = 2 ether;

        // 1. Initiate transfer
        vm.prank(signer1);
        vault.initiateTransfer(recipient, amount);

        // 2. Get one approval
        vm.prank(signer2);
        vault.approveTransfer(0);

        // 3. Verify state before execution
        (address to, uint256 transferAmount, uint256 approvals, bool executed) = vault.getTransfer(0);
        assertEq(to, recipient);
        assertEq(transferAmount, amount);
        assertEq(approvals, 2); // Was 1, now 2
        assertFalse(executed);

        // 4. Execute transfer
        vm.prank(signer3);
        vault.executeTransfer(0);

        // 5. Verify final state
        (,, approvals, executed) = vault.getTransfer(0);
        assertTrue(executed);
        assertEq(recipient.balance, amount);
    }
}
