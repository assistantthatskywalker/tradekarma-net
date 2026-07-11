// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title KarmaRune ($KRUNE) — Reputation Token
 * @notice ERC-20 on Base. NON-PURCHASABLE by design: tokens can only be minted
 *         by the platform MINTER (the earning engine) as reputation is earned.
 *         There is deliberately NO public mint / buy function. This is the
 *         load-bearing rule of TradeKarma: reputation is earned, never bought.
 */
contract KarmaRune {
    string public constant name = "KarmaRune";
    string public constant symbol = "KRUNE";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    mapping(address => bool) public minters; // Only the earning engine / bridge

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterSet(address indexed minter, bool enabled);
    event Earned(address indexed user, uint256 amount, bytes32 reasonHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "KRUNE: not owner");
        _;
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "KRUNE: not minter");
        _;
    }

    constructor() {
        owner = msg.sender;
        minters[msg.sender] = true;
    }

    function setMinter(address minter, bool enabled) external onlyOwner {
        minters[minter] = enabled;
        emit MinterSet(minter, enabled);
    }

    /**
     * @notice Mint KRUNE as reputation earned. Callable ONLY by the earning
     *         engine / migration bridge. `reasonHash` links to the off-chain
     *         earning event (review, help, referral, ship) for auditability.
     * @dev There is no payable path anywhere in this contract — KRUNE cannot
     *      be purchased.
     */
    function mintEarned(address user, uint256 amount, bytes32 reasonHash) external onlyMinter {
        require(user != address(0), "KRUNE: zero address");
        totalSupply += amount;
        balanceOf[user] += amount;
        emit Transfer(address(0), user, amount);
        emit Earned(user, amount, reasonHash);
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
        require(allowed >= value, "KRUNE: allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "KRUNE: balance");
        require(to != address(0), "KRUNE: zero address");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
