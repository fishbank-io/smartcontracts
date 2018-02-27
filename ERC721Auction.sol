pragma solidity ^0.4.18;

import "./Beneficiary.sol";

/// @title Auction contract for any type of erc721 token
/// @author Fishbank
contract ERC721 {
    function implementsERC721() public pure returns (bool);

    function totalSupply() public view returns (uint256 total);

    function balanceOf(address _owner) public view returns (uint256 balance);

    function ownerOf(uint256 _tokenId) public view returns (address owner);

    function approve(address _to, uint256 _tokenId) public;

    function transferFrom(address _from, address _to, uint256 _tokenId) public returns (bool);

    function transfer(address _to, uint256 _tokenId) public returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    // Optional
    // function name() public view returns (string name);
    // function symbol() public view returns (string symbol);
    // function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256 tokenId);
    // function tokenMetadata(uint256 _tokenId) public view returns (string infoUrl);
}


contract ERC721Auction is Beneficiary {

    struct Auction {
        address seller;
        uint256 tokenId;
        uint64 auctionBegin;
        uint64 auctionEnd;
        uint256 startPrice;
        uint256 endPrice;
    }

    ERC721 public ERC721Contract;
    uint256 public fee = 37500; //in 1 10000th of a percent so 3.75% at the start
    uint256 constant feeDivider = 1000000;
    mapping(uint256 => Auction) public auctions;

    event AuctionWon(uint256 indexed tokenId, address indexed winner, address indexed seller, uint256 price);
    event AuctionStarted(uint256 indexed tokenId, address indexed seller);
    event AuctionFinalized(uint256 indexed tokenId, address indexed seller);


    function ERC721Auction(address _ERC721Contract) public {
        ERC721Contract = ERC721(_ERC721Contract);
    }


    function setFee(uint256 _fee) onlyOwner public {
        if (_fee > fee) {
            revert();
            //fee can only be lowerred to prevent attacks by owner
        }
        fee = _fee;
        // all is well set fee
    }


    function startAuction(uint256 _tokenId, uint256 _startPrice, uint256 _endPrice) external {
        require(ERC721Contract.transferFrom(msg.sender, address(this), _tokenId));
        require(now > auctions[_tokenId].auctionEnd);
        //can only start new auction if no other is active
        Auction memory auction;

        auction.seller = msg.sender;
        auction.tokenId = _tokenId;
        auction.auctionBegin = uint64(now);
        auction.auctionEnd = uint64(now + 48 hours);
        require(auction.auctionEnd > auction.auctionBegin);
        auction.startPrice = _startPrice;
        auction.endPrice = _endPrice;

        auctions[_tokenId] = auction;

        AuctionStarted(_tokenId, msg.sender);
    }


    function calculateBid(uint256 _tokenId) public view returns (uint256) {
        Auction storage auction = auctions[_tokenId];

        if (now >= auction.auctionEnd) {//if auction ended return auction end price
            return auction.endPrice;
        }

        uint256 hoursPassed = (now - auction.auctionBegin) / 1 hours;
        //get hours passed
        uint256 currentPrice;

        if (auction.endPrice > auction.startPrice) {
            currentPrice = auction.startPrice + (auction.endPrice - auction.startPrice) * hoursPassed / 47;
        }
        else if (auction.startPrice > auction.endPrice) {
            currentPrice = auction.startPrice - (auction.startPrice - auction.endPrice) * hoursPassed / 47;
        }
        else {//start and end are the same
            currentPrice = auction.endPrice;
        }

        return (uint256(currentPrice));
        //return the price at this very moment
    }


    function buyAuction(uint256 _tokenId) payable external {
        Auction storage auction = auctions[_tokenId];
        require(now < auction.auctionEnd);
        // auction must be still going

        uint256 price = calculateBid(_tokenId);
        uint256 totalFee = price * fee / feeDivider;
        //safe math needed?

        require(price <= msg.value);
        //revert if not enough ether send

        if (price != msg.value) {//send back to much eth
            msg.sender.transfer(msg.value - price);
        }

        beneficiary.transfer(totalFee);

        auction.seller.transfer(price - totalFee);

        if (!ERC721Contract.transfer(msg.sender, _tokenId)) {
            revert();
            //can't complete transfer if this fails
        }

        AuctionWon(_tokenId, msg.sender, auction.seller, price);

        delete auctions[_tokenId];
        //deletes auction
    }

    function isAuctionActive(uint256 _tokenId) public view returns (bool) {
        return auctions[_tokenId].auctionEnd > now;
    }


    function saveToken(uint256 _tokenId) external {
        require(auctions[_tokenId].auctionEnd < now);
        //auction must have ended
        require(ERC721Contract.transfer(auctions[_tokenId].seller, _tokenId));
        //transfer fish back to seller

        AuctionFinalized(_tokenId, auctions[_tokenId].seller);

        delete auctions[_tokenId];
        //delete auction
    }

}
