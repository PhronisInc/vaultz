// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @notice Holds a single Uniswap v3 LP position NFT for one launch. Nothing,
/// including the beneficiary, can move the position out before unlockTime —
/// there is no admin override and no early-withdraw path.
contract LPLocker is ERC721Holder {
    error NotYetUnlocked();
    error NotBeneficiary();
    error AlreadyWithdrawn();

    IERC721 public immutable positionManager;
    uint256 public immutable tokenId;
    address public immutable beneficiary;
    uint256 public immutable unlockTime;
    bool public withdrawn;

    constructor(address positionManager_, uint256 tokenId_, address beneficiary_, uint256 unlockTime_) {
        positionManager = IERC721(positionManager_);
        tokenId = tokenId_;
        beneficiary = beneficiary_;
        unlockTime = unlockTime_;
    }

    function withdraw() external {
        if (msg.sender != beneficiary) revert NotBeneficiary();
        if (block.timestamp < unlockTime) revert NotYetUnlocked();
        if (withdrawn) revert AlreadyWithdrawn();
        withdrawn = true;
        positionManager.safeTransferFrom(address(this), beneficiary, tokenId);
    }
}
