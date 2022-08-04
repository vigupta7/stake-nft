# NFT STAKE Contract

There are many token projects will allow their users to stake ERC20/BEP20 tokens and earn yield in same token, but there are very few projects in NFTs which allow people to stake NFT and earn yield.

This project demonstrates staking an NFT use case. 
The project uses Solidity for the staking DAPP Contract and targets all EVM compatible blockchain like BSC/TRC/ETH etc.

You may directly use the contracts/nftstake.sol in web3 IDE like Remix or use framework like hardhat or truffle for deployment and testing.

This project uses hardhat framework.

# DAPP Features

1. The DAPP allow creators to create multiple staking plans that offers different types of yields. for example, they can create plan1 for certain amount of time, than start plan2 and so on.

2. Each plan can be configured with several parameters like Maximum APY, Plan Validity, Staking open/close time etc.

3. The APY is calculated dynamically based on certain parameters like 
    - Number of NFTs staked. (Value of stake is identified by defined token price of each NFT)
    - Maximum APY defined in the staking Plan.
    - Staking Validity defined in Plan
    - Total balance available for distributing rewards.

4. Staking APY adjust automatically as new users stake there NFT or old users unstake their NFTs.

5. There are many getters which allow to view the current APY, current active Plan, unclaimed rewards etc.
