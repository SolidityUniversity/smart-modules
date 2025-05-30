/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/VaultMultisig.sol";

contract VaultMultisigTest is Test {
    VaultMultisig vault;
    uint256 quorum = 2;
    address[] signers;
    address[] signersArray;

    address signer1 = vm.addr(1);
    address signer2 = vm.addr(2);
    address signer3 = vm.addr(3);
    address defaultRecepient = vm.addr(999);
    address stranger = vm.addr(777);

    function setUp() public {
        signers.push(signer1);
        signers.push(signer2);
        signers.push(signer3);

        vault = new VaultMultisig(signers, quorum);
    }

    function test_InitiateTransferRevertsIfNoEtherOnVault(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.VaultIsEmpty.selector);
        console.log("Vault Balance: ", address(vault).balance);

        vault.initiateTransfer(_randomAddress, 1 wei);
    }

    function test_InitiateTransferRevertsInvalidRecipient() public {
        address recepient = address(0);

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.InvalidRecipient.selector);

        vault.initiateTransfer(recepient, 1 wei);
    }

    function test_InitiateTransferRevertsInvalidMain(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.InvalidAmount.selector);

        vault.initiateTransfer(_randomAddress, 0);
    }

    function test_InitiateTransferShouldWork(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        fundVault(1 ether);

        vm.prank(signer1);

        vm.expectEmit(true, true, false, true);
        emit VaultMultisig.TransferInitiated(0, _randomAddress, 1 ether);

        vault.initiateTransfer(_randomAddress, 1 ether);

        (address to, uint256 amount, uint256 approvals, bool executed) = vault.getTransfer(0);

        assertEq(to, _randomAddress);
        assertEq(amount, 1 ether);
        assertEq(approvals, 1);
        assertEq(executed, false);
    }

    function test_approveTransferShouldWork() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        //1st approve
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.SignerAlreadyApproved.selector, signer1));
        vault.approveTransfer(0);

        //2nd approve
        vm.startPrank(signer2);
        vault.approveTransfer(0);

        //3d approve
        vm.startPrank(signer3);
        vault.approveTransfer(0);

        (,, uint256 approvals,) = vault.getTransfer(0);

        assertEq(approvals, 3);
    }

    function test_approveTransferShoulEmitTransferApproved() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.expectEmit(true, true, false, false);
        emit VaultMultisig.TransferApproved(0, signer2);
        vm.startPrank(signer2);
        vault.approveTransfer(0);
    }

    function test_executeTransferWors() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.QuorumHasNotBeenReached.selector, 0));
        vault.executeTransfer(0);

        vm.startPrank(signer2);
        vault.approveTransfer(0);

        vm.expectEmit(true, false, false, false);
        emit VaultMultisig.TransferExecuted(0);
        vault.executeTransfer(0);

        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.TransferIsAlreadyExecuted.selector, 0));
        vault.executeTransfer(0);

        (address to, uint256 amount, uint256 approvals, bool executed) = vault.getTransfer(0);

        assertEq(to, defaultRecepient);
        assertEq(amount, 1 ether);
        assertEq(approvals, 2);
        assertEq(executed, true);
    }

    function test_hasSignedTransferWorks() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);
        assertTrue(vault.hasSignedTransfer(0, signer1));
        assertFalse(vault.hasSignedTransfer(0, signer2));

        vm.startPrank(signer2);
        vault.approveTransfer(0);

        assertTrue(vault.hasSignedTransfer(0, signer1));
        assertTrue(vault.hasSignedTransfer(0, signer2));
    }

    function test_getTransferCountWorks() public {
        uint256 beforeTransferInitiation = vault.getTransferCount();
        assertEq(beforeTransferInitiation, 0);

        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        uint256 afterTransferInitiation = vault.getTransferCount();
        assertEq(afterTransferInitiation, 1);
    }

    function test_onlyMultisigSignerModifierWorks() public {
        vm.prank(stranger);
        fundVault(1 ether);

        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);
    }

    function test_constructrRevertsSignersArrayCannotBeEmpty() public {
        address[] memory empty;

        vm.expectRevert(VaultMultisig.SignersArrayCannotBeEmpty.selector);
        new VaultMultisig(empty, 1);
    }

    function test_constructrRevertsQuorumGreaterThanSigners() public {
        signersArray.push(signer1);
        signersArray.push(signer2);

        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        new VaultMultisig(signersArray, 3);
    }

    function test_constructrRevertsQuorumCannotBeZero() public {
        signersArray.push(signer1);

        vm.expectRevert(VaultMultisig.QuorumCannotBeZero.selector);
        new VaultMultisig(signersArray, 0);
    }

    function fundVault(uint256 amount) internal {
        vm.deal(address(vault), amount);
    }
}
