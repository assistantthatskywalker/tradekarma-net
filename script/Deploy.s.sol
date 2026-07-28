// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {KarmaRune} from "../contracts/KarmaRune.sol";
import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";

/**
 * @title Deploy — the entire TradeKarma on-chain layer in one broadcast
 * @notice Deploys KRUNE, KDEX, KSHRD, Staking and Treasury, then wires the
 *         three roles the system cannot function without, then hands both
 *         admin keys to the multi-sig. It does NOT call `KarmaShard.lockRoles()`
 *         — that seal is irreversible and lives alone in `LockRoles.s.sol`.
 * @dev The ordering here is load-bearing in two directions.
 *
 *      Construction order is forced by the constructors: Staking and Treasury
 *      both take token addresses, so all three tokens exist first. KDEX is the
 *      awkward one — Treasury needs KDEX's address and KDEX needs a recipient
 *      for its entire fixed supply, and that circle can only be broken by
 *      sending the supply to a WALLET. `ADMIN_ADDRESS` (the multi-sig) receives
 *      it and funds the Treasury afterwards with a plain `transfer`. Passing a
 *      contract address here would be unrecoverable: KDEX has no mint, no owner
 *      and no rescue, and `Treasury.recoverToken` deliberately refuses to move
 *      KDEX.
 *
 *      Wiring order is forced by audit finding H-03: `Staking` starts accepting
 *      deposits the instant it is deployed, and until KSHRD's MINTER_ROLE lands
 *      it cannot pay yield. The contract now degrades gracefully — `unstake()`
 *      wraps the mint and defers the shortfall into `unclaimedYield` — so the
 *      window costs a `claimYield()` call rather than a staker's principal, but
 *      it is still a window, which is why the grants go out in this same
 *      broadcast rather than in a follow-up transaction someone might forget.
 *
 *      The deploying key holds DEFAULT_ADMIN_ROLE on KRUNE and KSHRD for the
 *      length of this script and no longer. That is the whole reason the wiring
 *      is done here: a multi-sig cannot sign a `grantRole` mid-deployment
 *      without a human quorum, so the alternative is hours or days of a live
 *      Staking contract with no minter. Treat the deploy key as critical for
 *      that window — while it holds KSHRD's admin role it can mint KSHRD from
 *      nothing (audit C-01) — and retire it afterwards; this script leaves it
 *      holding no role on any contract.
 *
 *      Configuration is read entirely from the environment. Every value is
 *      checked before a single contract is deployed, because none of these
 *      mistakes are correctable afterwards: the tokens are immutable, the
 *      Treasury's `usdcScale` is immutable, and KDEX's supply is minted once.
 */
contract Deploy is Script {
    /**
     * @return krune reputation token, minted only by the earning-engine bridge
     * @return kdex fixed-supply investment token, entire supply at ADMIN_ADDRESS
     * @return kshrd yield token, mintable only by Staking, burnable only by Treasury
     * @return staking the KRUNE+KDEX anti-whale stake
     * @return treasury the USDC/KDEX backing for KSHRD redemption
     */
    function run()
        external
        returns (KarmaRune krune, KarmaDex kdex, KarmaShard kshrd, Staking staking, Treasury treasury)
    {
        address admin = _envAddress("ADMIN_ADDRESS");
        address bridge = _envAddress("EARNING_ENGINE_BRIDGE");
        address usdc = _envAddress("USDC_ADDRESS");
        uint256 kdexSupply = vm.envOr("KDEX_INITIAL_SUPPLY", uint256(0));

        // KDEX has no mint function after construction, so a supply typed in
        // whole tokens instead of wei produces a permanently, silently wrong
        // token. 1e18 is one whole KDEX; anything below it is a typo.
        require(
            kdexSupply >= 1e18,
            "DEPLOY: KDEX_INITIAL_SUPPLY missing or below 1e18. It is denominated in wei -- 100000000000000000000000000 is 100,000,000 KDEX"
        );

        // Treasury reads USDC's decimals at construction to fix `usdcScale`
        // forever. A wrong address here misprices every redemption by orders of
        // magnitude and cannot be repaired, so fail before spending any gas.
        require(usdc.code.length > 0, "DEPLOY: USDC_ADDRESS has no code on this chain -- wrong address or wrong network");
        uint8 usdcDecimals = IERC20Metadata(usdc).decimals();
        require(usdcDecimals <= 18, "DEPLOY: USDC_ADDRESS reports more than 18 decimals");

        // The bridge is a hot key that signs `mintEarned` from a server process.
        // If it were also the multi-sig, a server compromise would hand over
        // role administration on both tokens as well (audit H-05).
        require(admin != bridge, "DEPLOY: ADMIN_ADDRESS must not be the earning-engine bridge (hot key)");

        address deployer = msg.sender;
        require(deployer != address(0), "DEPLOY: no sender -- pass --account, --ledger or --private-key");

        console2.log("== TradeKarma deployment ==");
        console2.log("chain id       ", block.chainid);
        console2.log("deployer       ", deployer);
        console2.log("admin (multisig)", admin);
        console2.log("bridge (minter)", bridge);
        console2.log("USDC           ", usdc);
        console2.log("USDC decimals  ", usdcDecimals);
        console2.log("KDEX supply    ", kdexSupply);

        vm.startBroadcast();

        // --- contracts -----------------------------------------------------
        // Admin roles go to the deployer so the wiring below can run now; they
        // are handed to `admin` at the end of this same broadcast.
        krune = new KarmaRune(deployer);
        kdex = new KarmaDex(kdexSupply, admin); // full supply to the multi-sig WALLET
        kshrd = new KarmaShard(deployer);
        staking = new Staking(address(krune), address(kdex), address(kshrd), admin);
        treasury = new Treasury(usdc, address(kdex), address(kshrd), admin);

        // --- wiring --------------------------------------------------------
        // 1. Without this, `unstake()` cannot mint yield and every payout defers
        //    into `unclaimedYield`.
        kshrd.grantRole(kshrd.MINTER_ROLE(), address(staking));
        // 2. Without this, `Treasury.redeem` reverts for everyone.
        kshrd.grantRole(kshrd.BURNER_ROLE(), address(treasury));
        // 3. The off-chain settlement wallet, and the only KRUNE minter that
        //    outlives this script.
        krune.grantRole(krune.MINTER_ROLE(), bridge);
        // 4. KarmaRune's constructor seeds MINTER_ROLE on its admin — here, the
        //    deploy key. Now that the bridge holds it, the deploy key gives it
        //    up. This is not optional in this script: the multi-sig never
        //    receives MINTER_ROLE at all, so once this lands the bridge is the
        //    sole minter, which is the property the audit asks for (H-05).
        krune.revokeRole(krune.MINTER_ROLE(), deployer);

        // --- handover ------------------------------------------------------
        // Skipped when the deployer IS the admin (local anvil runs), where
        // renouncing would leave the role table with no administrator at all.
        if (admin != deployer) {
            krune.grantRole(krune.DEFAULT_ADMIN_ROLE(), admin);
            kshrd.grantRole(kshrd.DEFAULT_ADMIN_ROLE(), admin);
            krune.renounceRole(krune.DEFAULT_ADMIN_ROLE(), deployer);
            kshrd.renounceRole(kshrd.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();

        // --- post-conditions -----------------------------------------------
        // Asserted against the simulated state, so a wiring mistake aborts the
        // run before anything is broadcast. `Verify.s.sol` re-asserts all of
        // this against the real chain afterwards; that is the gate, this is the
        // seatbelt.
        require(kshrd.hasRole(kshrd.MINTER_ROLE(), address(staking)), "DEPLOY: KSHRD MINTER_ROLE did not land on Staking");
        require(kshrd.hasRole(kshrd.BURNER_ROLE(), address(treasury)), "DEPLOY: KSHRD BURNER_ROLE did not land on Treasury");
        require(krune.hasRole(krune.MINTER_ROLE(), bridge), "DEPLOY: KRUNE MINTER_ROLE did not land on the bridge");
        require(!krune.hasRole(krune.MINTER_ROLE(), deployer), "DEPLOY: deploy key still holds KRUNE MINTER_ROLE");
        require(!kshrd.rolesLocked(), "DEPLOY: KSHRD roles are locked -- this script must never lock them");
        if (admin != deployer) {
            require(krune.hasRole(krune.DEFAULT_ADMIN_ROLE(), admin), "DEPLOY: KRUNE admin handover failed");
            require(kshrd.hasRole(kshrd.DEFAULT_ADMIN_ROLE(), admin), "DEPLOY: KSHRD admin handover failed");
            require(!krune.hasRole(krune.DEFAULT_ADMIN_ROLE(), deployer), "DEPLOY: deploy key still admins KRUNE");
            require(!kshrd.hasRole(kshrd.DEFAULT_ADMIN_ROLE(), deployer), "DEPLOY: deploy key still admins KSHRD");
        }

        _summary(krune, kdex, kshrd, staking, treasury, deployer);
    }

    /// @dev `vm.envAddress` reverts with a parser error when a variable is
    ///      missing; this says which one and why it matters. A zero address is
    ///      treated as missing — no contract in this system may ever be wired
    ///      to address(0).
    function _envAddress(string memory key) internal view returns (address value) {
        value = vm.envOr(key, address(0));
        require(value != address(0), string.concat("DEPLOY: ", key, " is unset or zero -- refusing to deploy"));
    }

    function _summary(
        KarmaRune krune,
        KarmaDex kdex,
        KarmaShard kshrd,
        Staking staking,
        Treasury treasury,
        address deployer
    ) internal pure {
        console2.log("");
        console2.log("== deployed ==");
        console2.log("KarmaRune  (KRUNE)", address(krune));
        console2.log("KarmaDex   (KDEX) ", address(kdex));
        console2.log("KarmaShard (KSHRD)", address(kshrd));
        console2.log("Staking           ", address(staking));
        console2.log("Treasury          ", address(treasury));
        console2.log("");
        console2.log("== paste into .env, then run Verify.s.sol ==");
        console2.log(string.concat("KRUNE_ADDRESS=", vm.toString(address(krune))));
        console2.log(string.concat("KDEX_ADDRESS=", vm.toString(address(kdex))));
        console2.log(string.concat("KSHRD_ADDRESS=", vm.toString(address(kshrd))));
        console2.log(string.concat("STAKING_ADDRESS=", vm.toString(address(staking))));
        console2.log(string.concat("TREASURY_ADDRESS=", vm.toString(address(treasury))));
        console2.log(string.concat("DEPLOYER_ADDRESS=", vm.toString(deployer)));
        console2.log("");
        console2.log("KSHRD rolesLocked is FALSE. Do not lock until Verify.s.sol passes. See script/README.md.");
    }
}
