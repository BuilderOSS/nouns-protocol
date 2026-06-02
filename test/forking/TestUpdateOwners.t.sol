// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { ViaIRTestHelper } from "../utils/ViaIRTestHelper.sol";
import { Token } from "../../src/token/Token.sol";
import { Governor } from "../../src/governance/governor/Governor.sol";
import { IManager } from "../../src/manager/IManager.sol";
import { Manager } from "../../src/manager/Manager.sol";
import { UUPS } from "../../src/lib/proxy/UUPS.sol";

contract PurpleTests is ViaIRTestHelper {
    Manager internal immutable manager = Manager(0xd310A3041dFcF14Def5ccBc508668974b5da7174);
    Token internal immutable token = Token(0xa45662638E9f3bbb7A6FeCb4B17853B7ba0F3a60);
    Governor internal immutable governor = Governor(0xFB4A96541E1C70FC85Ee512420eB0B05C542df57);
    address internal immutable fawkes = 0x617Cb4921071e73D0C41B5354F5246F12518745e;

    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal description;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("ETH_RPC_MAINNET"));
        vm.selectFork(mainnetFork);
        vm.rollFork(16171761);

        // Initialize time tracking for via_ir safety
        initTime();

        Token newTokenImpl = new Token(address(manager));

        vm.prank(manager.owner());
        manager.registerUpgrade(address(0x3E8c48b46C5752F40c6772520f03a4D8EDa49706), address(newTokenImpl));

        IManager.FounderParams[] memory newFounderParams = new IManager.FounderParams[](3);
        newFounderParams[0] =
            IManager.FounderParams({ wallet: address(0x06B59d0b6AdCc6A5Dc63553782750dc0b41266a3), ownershipPct: 10, vestExpiry: 2556057600 });
        newFounderParams[1] =
            IManager.FounderParams({ wallet: address(0x349993989b5AC27Fd033AcCb86a84920DEb91ABa), ownershipPct: 10, vestExpiry: 2556057600 });
        newFounderParams[2] =
            IManager.FounderParams({ wallet: address(0x0BC3807Ec262cB779b38D65b38158acC3bfedE10), ownershipPct: 1, vestExpiry: 2556057600 });

        targets = new address[](2);
        targets[0] = address(token);
        targets[1] = address(token);
        values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(UUPS.upgradeTo.selector, address(newTokenImpl));
        calldatas[1] = abi.encodeWithSelector(Token.updateFounders.selector, newFounderParams);
    }

    function test_purpleUpgrade() public {
        uint256 proposalTime = block.timestamp;

        vm.prank(fawkes);
        bytes32 proposalId = governor.propose(targets, values, calldatas, "");

        uint256 voteTime = proposalTime + 3 days;
        vm.warp(voteTime);
        vm.prank(fawkes);
        governor.castVote(proposalId, 1);
        vm.prank(0x8700B87C2A053BDE8Cdc84d5078B4AE47c127FeB);
        governor.castVote(proposalId, 1);

        uint256 queueTime = voteTime + 4 days;
        vm.warp(queueTime);
        governor.queue(proposalId);

        uint256 executeTime = queueTime + 3 days;
        vm.warp(executeTime);
        governor.execute(targets, values, calldatas, keccak256(""), fawkes);
    }
}
