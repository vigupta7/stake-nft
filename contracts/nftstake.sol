// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface Token {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface NFT {
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

contract StakeNFT is Pausable, Ownable, ReentrancyGuard {
    Token erc20Token;
    NFT nftToken;
    uint256 public planCount;

    struct Plan {
        uint256 rewardBal;
        uint256 maxApyPer;
        uint256 maxCount;
        uint256 stakeCount;
        uint256 currCount;
        uint256 maxUsrStake;
        uint256 lockSeconds;
        uint256 expireSeconds;
        uint256 perNFTPrice;
        uint256 closeTS;
    }

    struct TokenInfo {
        uint256 planId;
        uint256 startTS;
        uint256 endTS;
        uint256 claimed;
    }

    event StakePlan(uint256 id);
    event Staked(address indexed from, uint256 planId, uint256[] _ids);
    event UnStaked(address indexed from, uint256[] _ids);
    event Claimed(address indexed from, uint256[] _ids, uint256 amount);

    /* planId => plan mapping */
    mapping(uint256 => Plan) public plans;

    /* tokenId => token info */
    mapping(uint256 => TokenInfo) public tokenInfos;

    // Mapping owner address to stake token count
    mapping(address => uint256) public userStakeCnt;

    // Mapping from token ID to staker address
    mapping(uint256 => address) public stakers;

    /* address->array index->tokenId */
    mapping(address => mapping(uint256 => uint256)) stakedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) stakedTokensIndex;

    constructor(Token _tokenAddress, NFT _nfttokenAddress) {
        require(
            address(_tokenAddress) != address(0),
            "Token Address cannot be address 0"
        );
        require(
            address(_nfttokenAddress) != address(0),
            "NFT Token Address cannot be address 0"
        );

        erc20Token = _tokenAddress;
        nftToken = _nfttokenAddress;
    }

    function setStakePlan(
        uint256 id,
        uint256 _rewardBal,
        uint256 _maxApyPer,
        uint256 _maxCount,
        uint256 _maxUsrStake,
        uint256 _lockSeconds,
        uint256 _expireSeconds,
        uint256 _perNFTPrice,
        uint256 _planExpireSeconds
    ) external onlyOwner {
        //require(_rewardBal <= erc20Token.balanceOf(address(this)),"Given reward is less then balance");

        if (plans[id].maxApyPer == 0) planCount++;

        plans[id].rewardBal = _rewardBal; // Staking reward bucket
        plans[id].maxApyPer = _maxApyPer;
        plans[id].maxCount = _maxCount;
        plans[id].maxUsrStake = _maxUsrStake;
        plans[id].lockSeconds = _lockSeconds; // stake lock seconds
        plans[id].expireSeconds = _expireSeconds; // yield maturity seconds
        plans[id].perNFTPrice = _perNFTPrice;
        plans[id].closeTS = block.timestamp + _planExpireSeconds; // plan closing timestamp

        emit StakePlan(id);
    }

    function transferToken(address to, uint256 amount) external onlyOwner {
        require(erc20Token.transfer(to, amount), "Token transfer failed!");
    }

    function transferNFT(address to, uint256 tokenId) external onlyOwner {
        nftToken.transferFrom(address(this), to, tokenId);
    }

    function getCurrentAPY(uint256 planId) public view returns (uint256) {
        require(plans[planId].rewardBal > 0, "Invalid staking plan");
        uint256 perNFTShare;
        uint256 stakingBucket = plans[planId].rewardBal;
        uint256 currstakeCount = plans[planId].currCount == 0
            ? 1
            : plans[planId].currCount; // avoid divisible by 0 error

        uint256 maxNFTShare = (currstakeCount *
            plans[planId].perNFTPrice *
            plans[planId].maxApyPer) / 100;

        if (maxNFTShare < stakingBucket)
            perNFTShare = maxNFTShare / currstakeCount;
        else perNFTShare = stakingBucket / currstakeCount;

        return (perNFTShare * 100) / plans[planId].perNFTPrice;
    }

    function getUnClaimedReward(uint256 tokenId) public view returns (uint256) {
        require(tokenInfos[tokenId].startTS > 0, "Token not staked");

        uint256 apy;
        uint256 anualReward;
        uint256 perSecondReward;
        uint256 stakeSeconds;
        uint256 reward;
        uint256 matureTS;

        apy = getCurrentAPY(tokenInfos[tokenId].planId);
        anualReward =
            (plans[tokenInfos[tokenId].planId].perNFTPrice * apy) /
            100;
        perSecondReward = anualReward / (365 * 86400);
        matureTS =
            tokenInfos[tokenId].startTS +
            plans[tokenInfos[tokenId].planId].expireSeconds;

        if (tokenInfos[tokenId].endTS == 0)
            if (block.timestamp > matureTS)
                stakeSeconds = matureTS - tokenInfos[tokenId].startTS;
            else stakeSeconds = block.timestamp - tokenInfos[tokenId].startTS;
        else if (tokenInfos[tokenId].endTS > matureTS)
            stakeSeconds = matureTS - tokenInfos[tokenId].startTS;
        else
            stakeSeconds =
                tokenInfos[tokenId].endTS -
                tokenInfos[tokenId].startTS;

        reward = stakeSeconds * perSecondReward;
        reward = reward - tokenInfos[tokenId].claimed;

        return reward;
    }

    function claimReward(uint256[] calldata _ids) external nonReentrant {
        require(_ids.length > 0, "invalid arguments");
        uint256 totalClaimAmt = 0;
        uint256 claimAmt = 0;

        for (uint256 i = 0; i < _ids.length; i++) {
            require(
                plans[tokenInfos[_ids[i]].planId].closeTS < block.timestamp,
                "Cannot claim during staking period"
            );
            require(
                stakers[_ids[i]] == _msgSender(),
                "NFT does not belong to sender address"
            );
            claimAmt = getUnClaimedReward(_ids[i]);
            tokenInfos[_ids[i]].claimed += claimAmt;
            totalClaimAmt += claimAmt;
        }

        require(totalClaimAmt > 0, "Claim amount invalid.");

        emit Claimed(_msgSender(), _ids, totalClaimAmt);
        require(
            erc20Token.transfer(_msgSender(), totalClaimAmt),
            "Token transfer failed!"
        );
    }

    function _claimStakeReward(address sender, uint256[] calldata _ids)
        internal
    {
        require(_ids.length > 0, "invalid arguments");
        uint256 totalClaimAmt = 0;
        uint256 claimAmt = 0;

        for (uint256 i = 0; i < _ids.length; i++) {
            claimAmt = getUnClaimedReward(_ids[i]);
            tokenInfos[_ids[i]].claimed += claimAmt;
            totalClaimAmt += claimAmt;
        }

        if (totalClaimAmt > 0) {
            emit Claimed(sender, _ids, totalClaimAmt);
            require(
                erc20Token.transfer(sender, totalClaimAmt),
                "Token transfer failed!"
            );
        }
    }

    function stakeNFT(uint256 _planId, uint256[] calldata _ids)
        external
        whenNotPaused
    {
        require(plans[_planId].rewardBal > 0, "Invalid staking plan");
        require(block.timestamp < plans[_planId].closeTS, "Plan Expired");

        require(_ids.length > 0, "invalid arguments");
        require(
            (plans[_planId].currCount + _ids.length) <= plans[_planId].maxCount,
            "NFT Collection Staking limit exceeded"
        );
        require(
            (userStakeCnt[_msgSender()] + _ids.length) <=
                plans[_planId].maxUsrStake,
            "User Staking limit exceeded"
        );

        for (uint256 i = 0; i < _ids.length; i++) {
            nftToken.transferFrom(_msgSender(), address(this), _ids[i]);
            plans[_planId].currCount++;
            plans[_planId].stakeCount++;
            stakers[_ids[i]] = _msgSender();

            stakedTokens[_msgSender()][userStakeCnt[_msgSender()]] = _ids[i];
            stakedTokensIndex[_ids[i]] = userStakeCnt[_msgSender()]; // check utility

            userStakeCnt[_msgSender()]++;

            tokenInfos[_ids[i]] = TokenInfo({
                planId: _planId,
                startTS: block.timestamp,
                endTS: 0,
                claimed: 0
            });
        }

        emit Staked(_msgSender(), _planId, _ids);
    }

    function UnStakeNFT(uint256[] calldata _ids)
        external
        whenNotPaused
        nonReentrant
    {
        require(_ids.length > 0, "invalid arguments");

        for (uint256 i = 0; i < _ids.length; i++) {
            require(
                stakers[_ids[i]] == _msgSender(),
                "NFT is not staked by sender address"
            );
            require(tokenInfos[_ids[i]].endTS == 0, "NFT is already unstaked");
            require(
                block.timestamp >
                    (tokenInfos[_ids[i]].startTS +
                        plans[tokenInfos[_ids[i]].planId].lockSeconds),
                "NFT cannot be unstake before locking period."
            );

            nftToken.transferFrom(address(this), _msgSender(), _ids[i]);
            plans[tokenInfos[_ids[i]].planId].currCount--;

            tokenInfos[_ids[i]].endTS = block.timestamp;

            unStakeUserNFT(_msgSender(), _ids[i]); // minus from array, adjust array length

            userStakeCnt[_msgSender()]--;
            stakers[_ids[i]] = address(0);
        }

        emit UnStaked(_msgSender(), _ids);
        _claimStakeReward(_msgSender(), _ids);
    }

    function unStakeUserNFT(address from, uint256 tokenId) internal {
        uint256 lastTokenIndex = userStakeCnt[from] - 1;
        uint256 tokenIndex = stakedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = stakedTokens[from][lastTokenIndex];

            stakedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            stakedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete stakedTokensIndex[tokenId];
        delete stakedTokens[from][lastTokenIndex];
    }

    function tokensOfStaker(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = userStakeCnt[_owner];

        uint256[] memory result = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            result[i] = stakedTokens[_owner][i];
        }
        return result;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
