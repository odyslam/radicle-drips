// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import "ds-test/test.sol";
import {Governance} from "./governance.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

// contract should be maintained by governance
contract DripsContract is Ownable {
    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    uint256 public value = 0;

    function setValue(uint256 newValue) public onlyOwner {
        value = newValue;
    }
}

// contract which performs a set of instructions
// no state
contract ChangeValueSpellAction {
    function execute(DripsContract dripsContract) public {
        dripsContract.setValue(1);
    }
}

contract ChangeValueSpell {
    bytes public sig;
    address public action;
    Governance public governance;
    uint256 public earliestExeTime;
    bool public done;
    uint256 public delay;

    constructor(
        Governance governance_,
        address dripsContract,
        uint256 delay_
    ) {
        sig = abi.encodeWithSignature("execute(address)", dripsContract);
        action = address(new ChangeValueSpellAction());
        governance = governance_;
        delay = delay_;
    }

    function schedule() public {
        require(earliestExeTime == 0, "already-scheduled");
        earliestExeTime = block.timestamp + delay;
        governance.schedule(action, sig, earliestExeTime);
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        governance.execute(action, sig, earliestExeTime);
    }
}

contract GovernanceTest is DSTest {
    Governance public governance;
    DripsContract public dripsContract;

    function setUp() public {
        governance = new Governance(address(this));
        dripsContract = new DripsContract(address(governance.executor()));
    }

    function assertPreCondition() public {
        assertEq(dripsContract.value(), 0, "pre-condition-err");
    }

    function assertPostCondition() public {
        assertEq(dripsContract.value(), 1, "post-condition-err");
    }

    function testSpell() public {
        ChangeValueSpell spell = new ChangeValueSpell(governance, address(dripsContract), 0);
        governance.approveSpell(address(spell));
        spell.schedule();
        assertPreCondition();
        spell.cast();
        assertPostCondition();
    }

    function testScheduleExecuteDirectly() public {
        bytes memory sig = abi.encodeWithSignature("execute(address)", dripsContract);
        address action = address(new ChangeValueSpellAction());
        governance.schedule(action, sig, block.timestamp);
        assertPreCondition();
        governance.execute(action, sig, block.timestamp);
        assertPostCondition();
    }
}
