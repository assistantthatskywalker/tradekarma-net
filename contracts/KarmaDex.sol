// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title KarmaDex ($KDEX) — Investment & Governance Token
 * @notice ERC-20 on Base. FIXED SUPPLY minted once at construction and
 *         distributed (community, team vesting, liquidity, investor round).
 *         Purchasable on a DEX. Carries governance voting power. Deliberately
 *         separated from the reputation layer (KRUNE) so price speculation
 *         cannot distort behavioral incentives.
 * @dev Built on OpenZeppelin ERC20. There is no mint function after
 *      construction and no owner — the supply is immutable forever.
 */
contract KarmaDex is ERC20 {
    /**
     * @param initialSupply fixed supply (e.g. 100_000_000e18), minted to treasury.
     * @param treasury address receiving the full fixed supply for distribution.
     */
    constructor(uint256 initialSupply, address treasury) ERC20("KarmaDex", "KDEX") {
        require(treasury != address(0), "KDEX: zero treasury");
        _mint(treasury, initialSupply);
    }
}
