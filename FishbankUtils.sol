pragma solidity ^0.4.18;

import "./Ownable.sol";

contract FishbankUtils is Ownable {

    uint32 public initialWeight = 36;
    uint32 public whaleInitialWeight = 10e6;


    uint32[100] cooldowns = [
        720 minutes, 720 minutes, 720 minutes, 720 minutes, 720 minutes, //1-5
        660 minutes, 660 minutes, 660 minutes, 660 minutes, 660 minutes, //6-10
        600 minutes, 600 minutes, 600 minutes, 600 minutes, 600 minutes, //11-15
        540 minutes, 540 minutes, 540 minutes, 540 minutes, 540 minutes, //16-20
        480 minutes, 480 minutes, 480 minutes, 480 minutes, 480 minutes, //21-25
        420 minutes, 420 minutes, 420 minutes, 420 minutes, 420 minutes, //26-30
        360 minutes, 360 minutes, 360 minutes, 360 minutes, 360 minutes, //31-35
        300 minutes, 300 minutes, 300 minutes, 300 minutes, 300 minutes, //36-40
        240 minutes, 240 minutes, 240 minutes, 240 minutes, 240 minutes, //41-45
        180 minutes, 180 minutes, 180 minutes, 180 minutes, 180 minutes, //46-50
        120 minutes, 120 minutes, 120 minutes, 120 minutes, 120 minutes, //51-55
        90 minutes,  90 minutes,  90 minutes,  90 minutes,  90 minutes,  //56-60
        75 minutes,  75 minutes,  75 minutes,  75 minutes,  75 minutes,  //61-65
        60 minutes,  60 minutes,  60 minutes,  60 minutes,  60 minutes,  //66-70
        50 minutes,  50 minutes,  50 minutes,  50 minutes,  50 minutes,  //71-75
        40 minutes,  40 minutes,  40 minutes,  40 minutes,  40 minutes,  //76-80
        30 minutes,  30 minutes,  30 minutes,  30 minutes,  30 minutes,  //81-85
        20 minutes,  20 minutes,  20 minutes,  20 minutes,  20 minutes,  //86-90
        10 minutes,  10 minutes,  10 minutes,  10 minutes,  10 minutes,  //91-95
        5 minutes,   5 minutes,   5 minutes,   5 minutes,   5 minutes    //96-100
    ];


    function setCooldowns(uint32[100] _cooldowns) onlyOwner public {
        cooldowns = _cooldowns;
    }

    function setInitialWeights(uint32 _initialWeight, uint32 _whaleInitialWeight) public onlyOwner {
        initialWeight = _initialWeight;
        whaleInitialWeight = _whaleInitialWeight;
    }

    function getFishParams(uint256 hashSeed1, uint256 hashSeed2, uint256 fishesLength, address coinbase) external view returns (uint32[4]) {
        uint32 weight = initialWeight;

        bytes32[5] memory hashSeeds;
        hashSeeds[0] = keccak256(hashSeed1 ^ hashSeed2); //xor both seed from owner and user so no one can cheat
        hashSeeds[1] = keccak256(hashSeeds[0], fishesLength);
        hashSeeds[2] = keccak256(hashSeeds[1], coinbase);
        hashSeeds[3] = keccak256(hashSeeds[2], coinbase, fishesLength);
        hashSeeds[4] = keccak256(hashSeeds[1], hashSeeds[2], hashSeeds[0]);

        uint24[6] memory seeds = [
            uint24(uint(hashSeeds[3]) % 10e6 + 1), //whale_chance
            uint24(uint(hashSeeds[0]) % 420 + 1), //power
            uint24(uint(hashSeeds[1]) % 420 + 1), //agility
            uint24(uint(hashSeeds[2]) % 150 + 1), //speed
            uint24(uint(hashSeeds[4]) % 16 + 1), //whale_type
            uint24(uint(hashSeeds[4]) % 5000 + 1) //rarity
        ];

        uint32[4] memory fishParams;

        if (seeds[0] == 10e6) {//This is a whale
            weight = whaleInitialWeight;

            if (seeds[4] == 1) {//Orca
                fishParams = [140 + uint8(seeds[1] / 42), 140 + uint8(seeds[2] / 42), 75 + uint8(seeds[3] / 6), weight];
            } else if (seeds[4] < 4) {//Blue whale
                fishParams = [130 + uint8(seeds[1] / 42), 130 + uint8(seeds[2] / 42), 75 + uint8(seeds[3] / 6), weight];
            } else {//Cachalot
                fishParams = [115 + uint8(seeds[1] / 28), 115 + uint8(seeds[2] / 28), 75 + uint8(seeds[3] / 6), weight];
            }
        } else {
            if (seeds[5] == 5000) {//Legendary
                fishParams = [85 + uint8(seeds[1] / 14), 85 + uint8(seeds[2] / 14), uint8(50 + seeds[3] / 3), weight];
            } else if (seeds[5] > 4899) {//Epic
                fishParams = [50 + uint8(seeds[1] / 12), 50 + uint8(seeds[2] / 12), uint8(25 + seeds[3] / 3), weight];
            } else if (seeds[5] > 4000) {//Rare
                fishParams = [20 + uint8(seeds[1] / 14), 20 + uint8(seeds[2] / 14), uint8(25 + seeds[3] / 2), weight];
            } else {//Common
                fishParams = [uint8(seeds[1] / 21), uint8(seeds[2] / 21), uint8(seeds[3] / 3), weight];
                if (fishParams[0] == 0) {
                    fishParams[0] = 1;
                }
                if (fishParams[1] == 0) {
                    fishParams[1] = 1;
                }
                if (fishParams[2] == 0) {
                    fishParams[2] = 1;
                }
            }
        }

        return fishParams;
    }

    function getCooldown(uint8 speed) external view returns (uint64){
        return uint64(now + cooldowns[speed]);
    }

    //Ceiling function for fish generator
    function ceil(uint base, uint divider) internal pure returns (uint) {
        return base / divider + ((base % divider > 0) ? 1 : 0);
    }
}