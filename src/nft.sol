// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReceiverWeight} from "../lib/radicle-streaming/src/Pool.sol";
import "openzeppelin-contracts/access/Ownable.sol";

import {DaiPool} from "../lib/radicle-streaming/src/DaiPool.sol";

struct InputNFTType {
    uint128 nftTypeId;
    uint64 limit;
    uint128 minAmtPerSec;
}

contract FundingNFT is ERC721, Ownable {
    /// @notice The amount passed as the withdraw amount to withdraw all the withdrawable funds
    uint128 public constant WITHDRAW_ALL = type(uint128).max;

    DaiPool public pool;
    IERC20 public dai;

    struct NFTType {
        uint64 limit;
        uint64 minted;
        uint128 minAmtPerSec;
    }

    mapping (uint128 => NFTType) public nftTypes;

    mapping (uint => uint64) public minted;

    string public contractURI;

    // events
    event NewNFTType(uint128 indexed nftType, uint64 limit, uint128 minAmtPerSec);
    event NewNFT(uint indexed tokenId, address indexed receiver, uint128 indexed typeId, uint128 topUp, uint128 amtPerSec);

    constructor(DaiPool pool_, string memory name_, string memory symbol_, address owner_,
        InputNFTType[] memory inputNFTTypes, string memory ipfsHash) ERC721(name_, symbol_) {
        pool = pool_;
        dai = pool.erc20();
        addTypes(inputNFTTypes);
        transferOwnership(owner_);
        contractURI = ipfsHash;
    }

    modifier onlyTokenHolder(uint tokenId) {
        require(ownerOf(tokenId) == msg.sender, "not-nft-owner");
        _;
    }

    function changeIPFSHash(string memory ipfsHash) public onlyOwner {
        contractURI = ipfsHash;
    }

    function addTypes(InputNFTType[] memory inputNFTTypes) public onlyOwner {
        for(uint i = 0; i < inputNFTTypes.length; i++) {
            uint64 limit = inputNFTTypes[i].limit;
            uint128 nftTypeId = inputNFTTypes[i].nftTypeId;
            uint128 minAmtPerSec = inputNFTTypes[i].minAmtPerSec;
            // nftType already exists or limit is not > 0
            require(nftTypes[nftTypeId].limit == 0, "nftTypeId-already-in-usage");
            require(limit > 0, "zero-limit-not-allowed");

            nftTypes[nftTypeId].limit = limit;
            nftTypes[nftTypeId].minAmtPerSec = minAmtPerSec;
            emit NewNFTType(nftTypeId, limit, minAmtPerSec);
        }
    }

    function createTokenId(uint128 id, uint128 nftType) public pure returns(uint tokenId) {
        return uint((uint(nftType) << 128)) | id;
    }

    function tokenType(uint tokenId) public pure returns(uint128 nftType) {
        return uint128(tokenId >> 128);
    }

    function mint(address nftReceiver, uint128 typeId, uint128 topUpAmt, uint128 amtPerSec) external returns (uint256) {
        require(amtPerSec >= nftTypes[typeId].minAmtPerSec, "amt-per-sec-too-low");
        uint128 cycleSecs = uint128(pool.cycleSecs());
        require(topUpAmt >= amtPerSec * cycleSecs, "toUp-too-low");
        require(nftTypes[typeId].minted++ < nftTypes[typeId].limit, "nft-type-reached-limit");

        uint256 newTokenId = createTokenId(nftTypes[typeId].minted, typeId);

        _mint(nftReceiver, newTokenId);
        minted[newTokenId] = uint64(block.timestamp);

        // transfer currency to NFT registry
        dai.transferFrom(nftReceiver, address(this), topUpAmt);
        dai.approve(address(pool), topUpAmt);

        // start streaming
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver: address(this), weight:1});
        pool.updateSubSender(newTokenId, topUpAmt, 0, amtPerSec, receivers);

        emit NewNFT(newTokenId, nftReceiver, typeId, topUpAmt, amtPerSec);

        return newTokenId;
    }

    function collect() public onlyOwner {
        pool.collect(address(this));
        dai.transfer(owner(), dai.balanceOf(address(this)));
    }

    function topUp(uint tokenId, uint128 topUpAmt) public onlyTokenHolder(tokenId) {
        dai.transferFrom(msg.sender, address(this), topUpAmt);
        dai.approve(address(pool), topUpAmt);
        pool.updateSubSender(tokenId, topUpAmt, 0, pool.AMT_PER_SEC_UNCHANGED(), new ReceiverWeight[](0));
    }

    function withdraw(uint tokenId, uint128 withdrawAmt) public onlyTokenHolder(tokenId) returns(uint128 withdrawn) {
        uint128 withdrawableAmt = withdrawable(tokenId);
        if (withdrawAmt == WITHDRAW_ALL) {
            withdrawAmt = withdrawableAmt;
        } else {
            require(withdrawAmt <= withdrawableAmt, "withdraw-amount-too-high");
        }
        withdrawn = pool.updateSubSender(tokenId, 0, withdrawAmt, pool.AMT_PER_SEC_UNCHANGED(), new ReceiverWeight[](0));
        dai.transfer(msg.sender, withdrawn);
    }

    function withdrawable(uint tokenId) public view returns(uint128) {
        uint128 amtPerSec = pool.getAmtPerSecSubSender(address(this), tokenId);
        if (amtPerSec == 0) {
            return type(uint128).max;
        }

        uint128 withdrawable_ = pool.withdrawableSubSender(address(this), tokenId);

        uint128 amtLocked = 0;
        uint64 fullCycleTimestamp = minted[tokenId] + uint64(pool.cycleSecs());
        if(block.timestamp < fullCycleTimestamp) {
            amtLocked = uint128(fullCycleTimestamp - block.timestamp) * amtPerSec;
        }

        //  mint requires topUp to be at least amtPerSec * pool.cycleSecs therefore
        // if amtLocked > 0 => withdrawable_ > amtLocked
        return withdrawable_ - amtLocked;

    }

    function amtPerSecond(uint tokenId) public view returns(uint128) {
        return pool.getAmtPerSecSubSender(address(this), tokenId);
    }

    function activeUntil(uint tokenId) public view returns(uint128) {
        uint128 amtNotStreamed = pool.withdrawableSubSender(address(this), tokenId);
        uint128 amtPerSec = pool.getAmtPerSecSubSender(address(this), tokenId);
        if (amtNotStreamed < amtPerSec) {
            return 0;
        }

        return uint128(block.timestamp + amtNotStreamed/amtPerSec);
    }

    function secsUntilInactive(uint tokenId) public view returns(uint128) {
        if (nftTypes[tokenType(tokenId)].minAmtPerSec == 0) {
            return type(uint128).max;
        }

        uint128 amtNotStreamed = pool.withdrawableSubSender(address(this), tokenId);
        if (amtNotStreamed == 0) {
            return 0;
        }

        uint128 amtPerSec = pool.getAmtPerSecSubSender(address(this), tokenId);

        uint128 secsLeft = currLeftSecsInCycle();
        uint128 neededCurrCycle = secsLeft * amtPerSec;

        // not enough to cover full current cycle => inactive
        if (amtNotStreamed < neededCurrCycle) {
            return 0;
        }

        uint64 cycleSecs = pool.cycleSecs();
        // todo optimize for gas
        uint128 leftFullCycles = ((amtNotStreamed-neededCurrCycle) / (cycleSecs * amtPerSec));
        return (leftFullCycles * cycleSecs) + secsLeft;

    }

    function active(uint tokenId) public view returns(bool) {
        return secsUntilInactive(tokenId) != 0;
    }

    // todo needs to be implemented
    function tokenURI(uint256) public view virtual override returns (string memory)  {
        // test metadata json
        return "QmaoWScnNv3PvguuK8mr7HnPaHoAD2vhBLrwiPuqH3Y9zm";
    }

    function currLeftSecsInCycle() public view returns(uint64) {
        uint64 cycleSecs = pool.cycleSecs();
        return cycleSecs - (uint64(block.timestamp) % cycleSecs);
    }

    function influence(uint tokenId) public view returns(uint influenceScore) {
        if(secsUntilInactive(tokenId) == 0) {
            return 0;
        }

       return pool.getAmtPerSecSubSender(address(this), tokenId);
    }
}
