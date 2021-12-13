// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable quotes
pragma solidity ^0.8.7;
import "./baseBuilder.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract DefaultIPFSBuilder is BaseBuilder {
    address public governance;
    string public defaultIpfsHash;

    // --- Auth Owner---
    mapping(address => uint256) public owner;
    function rely(address usr) external onlyOwner {
        owner[usr] = 1;
    }
    function deny(address usr) external onlyOwner {
        owner[usr] = 0;
    }
    modifier onlyOwner() {
        require(owner[msg.sender] == 1, "not-authorized");
        _;
    }

    event NewDefaultIPFS(string ipfsHash);

    constructor(address owner_, string memory defaultIpfsHash_) {
        owner[owner_] = 1;
        defaultIpfsHash = defaultIpfsHash_;
        emit NewDefaultIPFS(defaultIpfsHash);
    }

    function changeDefaultIPFS(string calldata newDefaultIpfsHash) public onlyOwner {
        defaultIpfsHash = newDefaultIpfsHash;
        emit NewDefaultIPFS(defaultIpfsHash);
    }

    function buildMetaData(
        string memory projectName,
        uint128 tokenId,
        uint128 nftType,
        bool streaming,
        uint128 amtPerCycle,
        bool active
    ) external view override returns (string memory) {
        string memory tokenIdStr = Strings.toString(tokenId);
        string memory nftTypeStr = Strings.toString(nftType);
        string memory supportRate = _toTwoDecimals(amtPerCycle);
        return
            _buildJSON(
                projectName,
                tokenIdStr,
                nftTypeStr,
                supportRate,
                active,
                streaming,
                defaultIpfsHash
            );
    }

    function buildMetaData(
        string memory projectName,
        uint128 tokenId,
        uint128 nftType,
        bool streaming,
        uint128 amtPerCycle,
        bool active,
        string memory ipfsHash
    ) external pure override returns (string memory) {
        string memory supportRate = _toTwoDecimals(amtPerCycle);
        string memory tokenIdStr = Strings.toString(tokenId);
        string memory nftTypeStr = Strings.toString(nftType);
        return
            _buildJSON(
                projectName,
                tokenIdStr,
                nftTypeStr,
                supportRate,
                active,
                streaming,
                ipfsHash
            );
    }
}
