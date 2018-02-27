pragma solidity ^0.4.18;

import "./ChestsStore.sol";
import "./FishbankBoosters.sol";
import "./FishbankChests.sol";
import "./FishbankUtils.sol";

/// @title Core contract of fishbank
/// @author Fishbank
contract Fishbank is ChestsStore {

    struct Fish {
        address owner;
        uint8 activeBooster;
        uint64 boostedTill;
        uint8 boosterStrength;
        uint24 boosterRaiseValue;
        uint32 weight;
        uint8 power;
        uint8 agility;
        uint8 speed;
        bytes16 color;
        uint64 canFightAgain;
        uint64 canBeAttackedAgain;
    }

    struct FishingAttempt {
        address fisher;
        uint256 feePaid;
        address affiliate;
        uint256 seed;
        uint64 deadline;//till when does the contract owner have time to resolve;
    }

    modifier onlyFishOwner(uint256 _tokenId) {
        require(fishes[_tokenId].owner == msg.sender);
        _;
    }

    modifier onlyResolver() {
        require(msg.sender == resolver);
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter);
        _;
    }

    Fish[] public fishes;
    address public resolver;
    address public auction;
    address public minter;
    bool public implementsERC721 = true;
    string public name = "Fishbank";
    string public symbol = "FISH";
    bytes32[] public randomHashes;
    uint256 public hashesUsed;
    uint256 public aquariumCost = 1 ether / 100 * 3;//fee for fishing starts at 0.03 ether
    uint256 public resolveTime = 30 minutes;//how long does the contract owner have to resolve hashes
    uint16 public fightFactor = 60;
    uint16 public fightBase = 100;
    uint16 public weightLostPartLimit = 5;
    FishbankBoosters public boosters;
    FishbankChests public chests;
    FishbankUtils private utils;


    mapping(bytes32 => FishingAttempt) public pendingFishing;//attempts that need solving;

    mapping(uint256 => address) public approved;
    mapping(address => uint256) public balances;
    mapping(address => bool) public affiliated;//keep track who came in via affiliate

    event AquariumFished(bytes32 indexed hash, address indexed fisher, uint256 feePaid);//event broadcated when someone fishes in aqaurium
    event AquariumResolved(bytes32 indexed hash, address indexed fisher);
    event Attack(
        uint256 indexed attacker,
        uint256 indexed victim,
        uint256 indexed winner,
        uint32 weight,
        uint256 ap, uint256 vp, uint256 random
    );

    event BoosterApplied(uint256 tokenId, uint256 boosterId);
    event Sleep(uint256 indexed tokenId);
    event Awake(uint256 indexed tokenId);


    /// @notice Constructor of the contract. Sets resolver, beneficiary, boosters and chests
    /// @param _boosters the address of the boosters smart contract
    /// @param _chests the address of the chests smart contract
    function Fishbank(address _boosters, address _chests, address _utils) ChestsStore(_chests) public {
        resolver = msg.sender;
        beneficiary = msg.sender;
        boosters = FishbankBoosters(_boosters);
        chests = FishbankChests(_chests);
        utils = FishbankUtils(_utils);
    }

    /// @notice Mints fishes according to params can only be called by the owner
    /// @param _owner array of addresses the fishes should be owned by
    /// @param _weight array of weights for the fishes
    /// @param _power array of power levels for the fishes
    /// @param _agility array of agility levels for the fishes
    /// @param _speed array of speed levels for the fishes
    /// @param _color array of color params for the fishes
    function mintFish(address[] _owner, uint32[] _weight, uint8[] _power, uint8[] _agility, uint8[] _speed, bytes16[] _color) onlyMinter public {
        for (uint i = 0; i < _owner.length; i ++) {
            _mintFish(_owner[i], _weight[i], _power[i], _agility[i], _speed[i], _color[i]);
        }
    }

    /// @notice Internal method for minting a fish
    /// @param _owner address of owner for the fish
    /// @param _weight weight param for fish
    /// @param _power power param for fish
    /// @param _agility agility param for the fish
    /// @param _speed speed param for the fish
    /// @param _color color param for the fish
    function _mintFish(address _owner, uint32 _weight, uint8 _power, uint8 _agility, uint8 _speed, bytes16 _color) internal {
        fishes.length += 1;
        uint256 newFishId = fishes.length - 1;

        Fish storage newFish = fishes[newFishId];

        newFish.owner = _owner;
        newFish.weight = _weight;
        newFish.power = _power;
        newFish.agility = _agility;
        newFish.speed = _speed;
        newFish.color = _color;

        balances[_owner] ++;

        Transfer(address(0), _owner, newFishId);
    }

    function setFightFactor(uint8 _fightFactor, uint8 _fightBase) onlyOwner public {
        fightFactor = _fightFactor;
        fightBase = _fightBase;
    }

    function setWeightLostPartLimit(uint8 _weightPart) onlyOwner public {
        weightLostPartLimit = _weightPart;
    }

    /// @notice Sets the cost for fishing in the aquarium
    /// @param _fee new fee for fishing in wei
    function setAquariumCost(uint256 _fee) onlyOwner public {
        aquariumCost = _fee;
    }

    /// @notice Sets address that resolves hashes for fishing can only be called by the owner
    /// @param _resolver address of the resolver
    function setResolver(address _resolver) onlyOwner public {
        resolver = _resolver;
    }


    /// @notice Sets the address getting the proceedings from fishing in the aquarium
    /// @param _beneficiary address of the new beneficiary
    function setBeneficiary(address _beneficiary) onlyOwner public {
        beneficiary = _beneficiary;
    }

    function setAuction(address _auction) onlyOwner public {
        auction = _auction;
    }

    function setBoosters(address _boosters) onlyOwner public {
        boosters = FishbankBoosters(_boosters);
    }

    function setMinter(address _minter) onlyOwner public {
        minter = _minter;
    }

    function setUtils(address _utils) onlyOwner public {
        utils = FishbankUtils(_utils);
    }

    /// @notice Call this to fish in the aquarium to get a fish or chests
    /// @param _seed User supllied random input so owner cannot cheat
    function fishAquarium(uint256 _seed) payable public returns (bytes32) {
        require(msg.value >= aquariumCost);
        //must send enough ether to cover costs
        require(randomHashes.length > hashesUsed);
        //there needs to be a hash left

        if (msg.value > aquariumCost) {
            msg.sender.transfer(msg.value - aquariumCost);
            //send to much ether back
        }

        while (true) {//this loop prevents from using the same hash as another fishing attempt if the owner submits the same hash multiple times
            if (pendingFishing[randomHashes[hashesUsed]].fisher == address(0)) {//if hash was not used already
                FishingAttempt storage newAttempt = pendingFishing[randomHashes[hashesUsed]];
                //storage pointer to new fishing attempt
                break;
                //break
            }
            hashesUsed ++;
            //increase hashesUsed and try next one
        }

        newAttempt.fisher = msg.sender;
        newAttempt.feePaid = aquariumCost;
        //set the fee paid so it can be returned if the hash doesn't get resolved fast enough
        newAttempt.seed = _seed;
        //sets the seed that gets combined with the random seed of the owner
        newAttempt.deadline = uint64(now + resolveTime);
        //saves deadline after which the fisher can redeem his fishing fee

        hashesUsed ++;
        //increase hashes used so it cannot be used again

        AquariumFished(randomHashes[hashesUsed - 1], msg.sender, aquariumCost);
        //broadcast event
        return randomHashes[hashesUsed - 1];
        //returns the hash used by this fishingAquarium call
    }

    /// @notice Call this function to fish in aquarium passing an affiliate
    /// @param _seed User supllied random input so owner cannot cheat
    /// @param _affiliate address of affiliate receiving reward
    function fishAquariumAffiliate(uint256 _seed, address _affiliate) payable public returns (bytes32) {
        bytes32 returnHash = fishAquarium(_seed);
        //create pending fishing
        pendingFishing[randomHashes[hashesUsed - 1]].affiliate = _affiliate;
        return returnHash;
    }

    /// @notice If resolver fails to resolve within the set time this can be called to get fee back
    /// @param _hash hash associated with fishing attempt
    function getAquariumFee(bytes32 _hash) public {
        require(pendingFishing[_hash].deadline >= now);
        //only allow refund after deadline

        FishingAttempt storage tempAttempt = pendingFishing[_hash];

        tempAttempt.fisher.transfer(tempAttempt.feePaid);

        delete pendingFishing[_hash];
        //delete attempt so it can not be refunded again
    }

    /// @notice Call this to resolve hashes and generate fish/chests
    /// @param _seed seed that corresponds to the hash
    function resolveAquarium(uint256 _seed) onlyResolver public {
        bytes32 tempHash = keccak256(_seed);
        FishingAttempt storage tempAttempt = pendingFishing[tempHash];

        require(tempAttempt.fisher != address(0));
        //attempt must be set so we look if fisher is set

        uint32[4] memory fishParams = utils.getFishParams(_seed, tempAttempt.seed, fishes.length, block.coinbase);

        _mintFish(tempAttempt.fisher, fishParams[3], uint8(fishParams[0]), uint8(fishParams[1]), uint8(fishParams[2]), bytes16(keccak256(_seed ^ tempAttempt.seed)));

        if (tempAttempt.affiliate != address(0)) {//if affiliate is set
            giveAffiliateChest(tempAttempt.affiliate, tempAttempt.fisher);
        }

        beneficiary.transfer(tempAttempt.feePaid);
        AquariumResolved(tempHash, tempAttempt.fisher);
        //broadcast event

        delete pendingFishing[tempHash];
        //delete fishing attempt
    }

    /// @notice Batch resolve fishing attempts
    /// @param _seeds array of seeds that correspond to hashes that need resolving
    function batchResolveAquarium(uint256[] _seeds) onlyResolver public {
        for (uint256 i = 0; i < _seeds.length; i ++) {
            resolveAquarium(_seeds[i]);
        }
    }

    /// @notice Internal method that gives affiliate chests
    /// @param _affiliate address of affiliate getting the chest
    /// @param _fisher address of the fisher the affiliate referred
    function giveAffiliateChest(address _affiliate, address _fisher) internal {
        if (affiliated[_fisher]) {//do not give free fish if this user is affiliated but do not revert tx
            return;
        }

        chests.mintChest(_affiliate, 1, 0, 0, 0, 0);
        //Chest with one random booster

        affiliated[_fisher] = true;
        //now no one can get a fish for referring this address anymore
    }

    /// @notice Adds an array of hashes to be used for resolving
    /// @param _hashes array of hashes to add
    function addHash(bytes32[] _hashes) onlyResolver public {
        for (uint i = 0; i < _hashes.length; i ++) {
            randomHashes.push(_hashes[i]);
        }
    }

    /// @notice Call this function to attack another fish
    /// @param _attacker ID of fish that is attacking
    /// @param _victim ID of fish to attack
    function attack(uint256 _attacker, uint256 _victim) onlyFishOwner(_attacker) public {

        Fish memory attacker = fishes[_attacker];
        Fish memory victim = fishes[_victim];

        //check if attacker is sleeping
        if (attacker.activeBooster == 2 && attacker.boostedTill <= now) {//if your fish is sleeping auto awake it
            fishes[_attacker].activeBooster = 100;
            //set booster to invalid one so it has no effect
        }

        //check if victim has active sleeping booster
        require(!(victim.activeBooster == 2 && victim.boostedTill >= now));
        //cannot attack a sleeping fish
        require(now >= attacker.canFightAgain);
        //check if attacking fish is cooled down
        require(now >= victim.canBeAttackedAgain);
        //check if victim fish can be attacked again


        if (msg.sender == victim.owner) {
            uint32 weight = attacker.weight < victim.weight ? attacker.weight : victim.weight;
            fishes[_attacker].weight += weight;
            fishes[_victim].weight -= weight;
            fishes[_attacker].canFightAgain = uint64(utils.getCooldown(attacker.speed));

            if (fishes[_victim].weight == 0) {
                _transfer(msg.sender, address(0), _victim);
                //burn token
            } else {
                fishes[_victim].canBeAttackedAgain = uint64(now + 1 hours);
                //set victim cooldown 1 hour
            }

            Attack(_attacker, _victim, _attacker, weight, 0, 0, 0);
            return;
        }

        if (victim.weight < 2 || attacker.weight < 2) {
            revert();
            //revert if one of the fish is below fighting weight
        }

        uint AP = getFightingAmounts(attacker, true);
        // get attacker power
        uint VP = getFightingAmounts(victim, false);
        // get victim power

        bytes32 randomHash = keccak256(block.coinbase, block.blockhash(block.number - 1), fishes.length);

        uint max = AP > VP ? AP : VP;
        uint attackRange = max * 2;
        uint random = uint(randomHash) % attackRange + 1;

        uint32 weightLost;

        if (random <= (max + AP - VP)) {
            weightLost = _handleWin(_victim, _attacker);
            Attack(_attacker, _victim, _attacker, weightLost, AP, VP, random);
        } else {
            weightLost = _handleWin(_attacker, _victim);
            Attack(_attacker, _victim, _victim, weightLost, AP, VP, random);
            //broadcast event
        }

        fishes[_attacker].canFightAgain = uint64(utils.getCooldown(attacker.speed));
        fishes[_victim].canBeAttackedAgain = uint64(now + 1 hours);
        //set victim cooldown 1 hour
    }

    /// @notice Handles lost gained weight after fight
    /// @param _winner the winner of the fight
    /// @param _loser the loser of the fight
    function _handleWin(uint256 _winner, uint256 _loser) internal returns (uint32) {
        Fish storage winner = fishes[_winner];
        Fish storage loser = fishes[_loser];

        uint32 fullWeightLost = loser.weight / sqrt(winner.weight);
        uint32 maxWeightLost = loser.weight / weightLostPartLimit;

        uint32 weightLost = maxWeightLost < fullWeightLost ? maxWeightLost : fullWeightLost;

        winner.weight += weightLost;
        loser.weight -= weightLost;

        return weightLost;
    }

    /// @notice get attack and defence from fish
    /// @param _fish is Fish token
    /// @param _is_attacker true if fish is attacker otherwise false
    function getFightingAmounts(Fish _fish, bool _is_attacker) internal view returns (uint){
        uint16 agilityFactor;
        uint16 powerFactor;

        if (_is_attacker) {//Role is attacker
            powerFactor = fightFactor;
            agilityFactor = fightBase - fightFactor;
        }
        else {//Role victim
            powerFactor = fightBase - fightFactor;
            agilityFactor = fightFactor;
        }

        return (getFishPower(_fish) * powerFactor + getFishAgility(_fish) * agilityFactor) * _fish.weight;

    }


    /// @notice Apply a booster to a fish
    /// @param _tokenId the fish the booster should be applied to
    /// @param _booster the Id of the booster the token should be applied to
    function applyBooster(uint256 _tokenId, uint256 _booster) onlyFishOwner(_tokenId) public {
        require(msg.sender == boosters.ownerOf(_booster));
        //only owner can do this
        require(boosters.getBoosterAmount(_booster) >= 1);
        Fish storage tempFish = fishes[_tokenId];
        uint8 boosterType = uint8(boosters.getBoosterType(_booster));

        if (boosterType == 1 || boosterType == 2 || boosterType == 3) {//if booster is attack or agility or sleep
            tempFish.boosterStrength = boosters.getBoosterStrength(_booster);
            tempFish.activeBooster = boosterType;
            tempFish.boostedTill = boosters.getBoosterDuration(_booster) * boosters.getBoosterAmount(_booster) + uint64(now);
            tempFish.boosterRaiseValue = boosters.getBoosterRaiseValue(_booster);
        }
        else if (boosterType == 4) {//watch booster
            require(tempFish.boostedTill < uint64(now));
            //revert on using watch on booster that has passed;
            tempFish.boosterStrength = boosters.getBoosterStrength(_booster);
            tempFish.boostedTill += boosters.getBoosterDuration(_booster) * boosters.getBoosterAmount(_booster);
            //add time to booster
        }
        else if (boosterType == 5) {//Instant attack
            require(boosters.getBoosterAmount(_booster) == 1);
            //Can apply only one instant attack booster
            tempFish.canFightAgain = 0;
        }

        require(boosters.transferFrom(msg.sender, address(0), _booster));
        //burn booster

        BoosterApplied(_tokenId, _booster);
    }

    /// @notice square root function used for weight gain/loss
    /// @param x uint32 to get square root from
    function sqrt(uint32 x) pure internal returns (uint32 y) {
        uint32 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    //utlitiy function for easy testing can be removed later
    function doKeccak256(uint256 _input) pure public returns (bytes32) {
        return keccak256(_input);
    }

    function getFishPower(Fish _fish) internal view returns (uint24 power) {
        power = _fish.power;
        if (_fish.activeBooster == 1 && _fish.boostedTill > now) {// check if booster active
            uint24 boosterPower = (5 * _fish.boosterStrength + _fish.boosterRaiseValue + 100) * power;
            if (boosterPower < 100) {
                if (_fish.boosterStrength == 1) {
                    power += 1;
                } else if (_fish.boosterStrength == 2) {
                    power += 3;
                } else {
                    power += 5;
                }
            } else {
                power = boosterPower / 100;
                // give 5% per booster strength
            }
        }
    }

    function getFishAgility(Fish _fish) internal view returns (uint24 agility) {
        agility = _fish.agility;
        if (_fish.activeBooster == 3 && _fish.boostedTill > now) {// check if booster active
            uint24 boosterPower = (5 * _fish.boosterStrength + _fish.boosterRaiseValue + 100) * agility;
            if (boosterPower < 100) {
                if (_fish.boosterStrength == 1) {
                    agility += 1;
                } else if (_fish.boosterStrength == 2) {
                    agility += 3;
                } else {
                    agility += 5;
                }
            } else {
                agility = boosterPower / 100;
                // give 5% per booster strength
            }
        }
    }


    //ERC721 functionality
    //could split this to a different contract but doesn't make it easier to read
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function totalSupply() public view returns (uint256 total) {
        total = fishes.length;
    }

    function balanceOf(address _owner) public view returns (uint256 balance){
        balance = balances[_owner];
    }

    function ownerOf(uint256 _tokenId) public view returns (address owner){
        owner = fishes[_tokenId].owner;
    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        require(fishes[_tokenId].owner == _from);
        //can only transfer if previous owner equals from
        fishes[_tokenId].owner = _to;
        approved[_tokenId] = address(0);
        //reset approved of fish on every transfer
        balances[_from] -= 1;
        //underflow can only happen on 0x
        balances[_to] += 1;
        //overflows only with very very large amounts of fish
        Transfer(_from, _to, _tokenId);
    }

    function transfer(address _to, uint256 _tokenId) public
    onlyFishOwner(_tokenId) //check if msg.sender is the owner of this fish
    returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId);
        //after master modifier invoke internal transfer
        return true;
    }

    function approve(address _to, uint256 _tokenId) public
    onlyFishOwner(_tokenId)
    {
        approved[_tokenId] = _to;
        Approval(msg.sender, _to, _tokenId);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public returns (bool) {
        require(approved[_tokenId] == msg.sender || msg.sender == auction);
        //require msg.sender to be approved for this token
        _transfer(_from, _to, _tokenId);
        //handles event, balances and approval reset
        return true;
    }

    function takeOwnership(uint256 _tokenId) public {
        require(approved[_tokenId] == msg.sender);
        _transfer(ownerOf(_tokenId), msg.sender, _tokenId);
    }

}
