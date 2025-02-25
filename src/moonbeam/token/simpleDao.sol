// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SimpleDAO {
    struct Proposal {
        address target; // 外部合约地址
        bytes data; // 调用数据
        uint256 voteCount; // 得票数
        bool executed; // 是否已执行
    }


    MyToken public token; // ERC20Votes代币
    Proposal[] public proposals; // 提案列表

    mapping(uint256 => mapping(address => bool)) public votes; // 投票记录

    constructor(MyToken _token) {
        token = _token;
    }

    function propose(address target, bytes calldata data) external {
        proposals.push(Proposal({
            target: target,
            data: data,
            voteCount: 0,
            executed: false
        }));
    }

    function vote(uint256 proposalId) external {
        require(token.balanceOf(msg.sender) > 0, "No voting rights");
        require(!votes[proposalId][msg.sender], "Already voted");

        votes[proposalId][msg.sender] = true;
        proposals[proposalId].voteCount += token.balanceOf(msg.sender);
    }

    function execute(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.voteCount > 0, "No votes");
        require(!proposal.executed, "Already executed");

        (bool success, ) = proposal.target.call(proposal.data);
        require(success, "Execution failed");

        proposal.executed = true;
    }
}