pragma solidity ^0.4.18;

import "./Ownable.sol";

contract Beneficiary is Ownable {

    address public beneficiary;

    function Beneficiary() public {
        beneficiary = msg.sender;
    }

    function setBeneficiary(address _beneficiary) onlyOwner public {
        beneficiary = _beneficiary;
    }


}
