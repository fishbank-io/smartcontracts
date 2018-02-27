pragma solidity ^0.4.18;

import "./Beneficiary.sol";
import "./FishbankChests.sol";

contract ChestsStore is Beneficiary {


    struct chestProduct {
        uint256 price; // Price in wei
        bool isLimited; // is limited sale chest
        uint32 limit; // Sell limit
        uint16 boosters; // count of boosters
        uint24 raiseChance;// in 1/10 of percent
        uint24 raiseStrength;// in 1/10 of percent for params or minutes for timebased boosters
        uint8 onlyBoosterType;//If set chest will produce only this type
        uint8 onlyBoosterStrength;
    }


    chestProduct[255] public chestProducts;
    FishbankChests chests;

    event ChestProductUpdated(
        uint256 chestId,
        uint256 price,
        bool isLimited,
        uint32 limit,
        uint16 boosters,
        uint24 raiseChance,
        uint24 raiseStrength,
        uint8 onlyBoosterType,
        uint8 onlyBoosterStrength);

    function ChestsStore(address _chests) public {
        chests = FishbankChests(_chests);
        //set chests to this address
    }

    function initChestsStore() public onlyOwner {
        // Create basic chests types
        setChestProduct(1, 0, 1, false, 0, 0, 0, 0, 0);
        setChestProduct(2, 15 finney, 3, false, 0, 0, 0, 0, 0);
        setChestProduct(3, 20 finney, 5, false, 0, 0, 0, 0, 0);
    }

    function setChestProduct(uint16 chestId, uint256 price, uint16 boosters, bool isLimited, uint32 limit, uint24 raiseChance, uint24 raiseStrength, uint8 onlyBoosterType, uint8 onlyBoosterStrength) onlyOwner public {
        chestProduct storage newProduct = chestProducts[chestId];
        newProduct.price = price;
        newProduct.boosters = boosters;
        newProduct.isLimited = isLimited;
        newProduct.limit = limit;
        newProduct.raiseChance = raiseChance;
        newProduct.raiseStrength = raiseStrength;
        newProduct.onlyBoosterType = onlyBoosterType;
        newProduct.onlyBoosterStrength = onlyBoosterStrength;

        ChestProductUpdated(chestId, price, isLimited, limit, boosters, raiseChance, raiseStrength, onlyBoosterType, onlyBoosterStrength);
    }

    function setChestPrice(uint16 chestId, uint256 price) onlyOwner public {
        chestProducts[chestId].price = price;

        ChestProductUpdated(chestId, price, chestProducts[chestId].isLimited, chestProducts[chestId].limit, chestProducts[chestId].boosters, chestProducts[chestId].raiseChance, chestProducts[chestId].raiseStrength, chestProducts[chestId].onlyBoosterType, chestProducts[chestId].onlyBoosterStrength);
    }

    function buyChest(uint16 _chestId) payable public {
        chestProduct memory tmpChestProduct = chestProducts[_chestId];

        require(tmpChestProduct.price > 0);
        // only chests with price
        require(msg.value >= tmpChestProduct.price);
        //check if enough ether is send
        require(!tmpChestProduct.isLimited || tmpChestProduct.limit > 0);
        //check limits if they exists

        chests.mintChest(msg.sender, tmpChestProduct.boosters, tmpChestProduct.raiseStrength, tmpChestProduct.raiseChance, tmpChestProduct.onlyBoosterType, tmpChestProduct.onlyBoosterStrength);

        if (msg.value > chestProducts[_chestId].price) {//send to much ether send some back
            msg.sender.transfer(msg.value - chestProducts[_chestId].price);
        }

        beneficiary.transfer(chestProducts[_chestId].price);
        //send paid eth to beneficiary

    }


}
