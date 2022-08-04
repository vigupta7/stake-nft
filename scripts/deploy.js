// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const erc20tokenAddress="";// write your Token Contract Address here in which stake rewards will be given
  const nfttokenAddress=""; // write you ERC721/1155 NFT contract address here which you want people to stake
  
  const NftStake = await hre.ethers.getContractFactory("StakeNFT");
  const nftStake = await NftStake.deploy(erc20tokenAddress,nfttokenAddress);

  await nftStake.deployed();

  console.log("NFtStake Contract deployed to:", nftStake.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
