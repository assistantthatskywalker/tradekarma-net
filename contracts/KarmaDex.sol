// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title KarmaDex ($KDEX) — Investment & Governance Token
 * @notice ERC-20 on Base. FIXED SUPPLY minted once at construction and
 *         distributed (community, team vesting, liquidity, investor round).
 *         Purchasable on a DEX. Carries governance voting power. Deliberately
 *         separated from the reputation layer (KRUNE) so price speculation
 *         cannot distort behavioral incentives.
 */
contract KarmaDex {
    string public constant name = "KarmaDex";
    string public constant symbol = "KDEX";
    uint8 public constant decimals = 18;

    uint256 public immutable totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @param initialSupply fixed supply (e.g. 100_000_000e18), minted to treasury.
     * @param treasury address receiving the full fixed supply for distribution.
     */
    constructor(uint256 initialSupply, address treasury) {
        require(treasury != address(0), "KDEX: zero treasury");
        totalSupply = initialSupply;
        balanceOf[treasury] = initialSupply;
        emit Transfer(address(0), treasury, initialSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "KDEX: allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "KDEX: balance");
        require(to != address(0), "KDEX: zero address");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
