pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./EggToken.sol";
import "./LoserChickNFT.sol";
import "./OwnableContract.sol";
import "./RandomInterface.sol";

contract SmashEggs is OwnableContract{

    using SafeMath for uint256;

    uint public constant PRECISION = 1e17;

    uint256 public constant LUCKY_CHICK_INDEX = 0;
    uint256 public constant LABOR_CHICK_INDEX = 1;
    uint256 public constant BOSS_CHICK_INDEX = 2;
    uint256 public constant TRUMP_CHICK_INDEX = 3;
    uint256 public constant SHRIEKING_CHICK_INDEX = 4;

    uint256 public aleadyBrokenEggAmount; // Broken eggs amount

    address[] public loserChickAddrArray;

    RandomInterface public randomContract;

    uint256 public winningProbability; // Get NFT Probability

    uint256[] public chickProbability; // Per chick Rate, 0 is luckyChick, 1 is laborChick, 2 is bossChick, 3 is trumpChick.

    EggToken public eggToken;

    uint256 private seed;

    uint256 public activityNFTProbability;

    address public activityNFTAddr;

    bool public smathEggSwitch = false;

    mapping(uint256 => mapping(address => bool)) public isUserSmashEggToday;

    mapping(uint256 => uint256) public smashEggUserCountPerDay;

    uint256 public shriekingStartNumber = 0;
    uint256 public shriekingEndNumber = 0;
    uint256 public shriekingSectionSize = 20000;
    bool public isHasCreatedShriekingChick = false;
    bool public shriekingChickSwitch = false;
    uint256 public shriekingProbability = 99990000000000000; // 1e13

    event SmashEggsEvent(address userAddr, uint256 eggCount, uint256 chickCount, address[] chickAddrArray, uint256[] tokenIdArray);
    event ActivityEvent(address userAddr, uint256 NFTConut, address NFTAddr);

    constructor(address _shriekingChickAddr, address _luckyChickAddr, address _laborChickAddr, address _bossChickAddr, address _trumpChickAddr, address _eggTokenAddr, address _randomAddr) public{
        loserChickAddrArray = new address[](5);
        loserChickAddrArray[LUCKY_CHICK_INDEX] = _luckyChickAddr;
        loserChickAddrArray[LABOR_CHICK_INDEX] = _laborChickAddr;
        loserChickAddrArray[BOSS_CHICK_INDEX] = _bossChickAddr;
        loserChickAddrArray[TRUMP_CHICK_INDEX] = _trumpChickAddr;
        loserChickAddrArray[SHRIEKING_CHICK_INDEX] = _shriekingChickAddr;

        randomContract = RandomInterface(_randomAddr);

        eggToken = EggToken(_eggTokenAddr);

        chickProbability = new uint256[](4);
        chickProbability[LUCKY_CHICK_INDEX] = 99926853587174232; // luckyChick  0.000428428571428571 * 1e17 = 42842857142857      0.0007314641282576833
        chickProbability[LABOR_CHICK_INDEX] = 99512243426578954; // laborChick  0.002428428571428570 * 1e17 = 242842857142857     0.004146101605952781
        chickProbability[BOSS_CHICK_INDEX] = 97561046401020877;  // bossChick   0.011428428571428600 * 1e17 = 1142842857142860    0.019511970255580775
        chickProbability[TRUMP_CHICK_INDEX] = 0;                 // trumpChick  0.571428428571429000 * 1e17 = 57142842857142900   0.9756104640102089

        winningProbability = 58571371428571464; // 0.571428428571429000 + 0.011428428571428600 + 0.002428428571428570 + 0.000428428571428571
    }

    function updateActivityNFT(address _activityNFTAddr, uint256 _activityNFTProbability) public onlyOwner{
        activityNFTAddr = _activityNFTAddr;
        activityNFTProbability = _activityNFTProbability;
    }

    function updateChickProbability(uint index, uint256 probability) public onlyOwner{
        require(index < 4, 'Index is wrong!');
        chickProbability[index] = probability;
    }

    function updateTotalProbability(uint256 probability) public onlyOwner{
        winningProbability = probability;
    }

    function getSmashEggUserCountPerDay(uint256 dayIndex) public view returns(uint256){
        return smashEggUserCountPerDay[dayIndex];
    }

    function getSmashEggUserCountToday() public view returns(uint256){
        uint256 dayIndex = now / 86400;
        return smashEggUserCountPerDay[dayIndex];
    }

    function getSmashEggUserCountYesterday() public view returns(uint256){
        uint256 dayIndex = now / 86400 - 1;
        return smashEggUserCountPerDay[dayIndex];
    }

    function smashEggs(uint256 amount) public{
        require(msg.sender == tx.origin, "invalid msg.sender");
        require(smathEggSwitch, "The smash switch is off!");
        require(0 < amount && amount <= 10, 'amount should be less than or equal to 10');
        uint256 userEggAmount = eggToken.balanceOf(msg.sender);
        require(amount <= userEggAmount.div(1e18), 'user egg shortage in number!');
        eggToken.transferFrom(msg.sender, address(this), amount.mul(1e18));

        uint256 dayIndex = now / 86400;
        if(!isUserSmashEggToday[dayIndex][msg.sender]){
            smashEggUserCountPerDay[dayIndex] = smashEggUserCountPerDay[dayIndex] + 1;
            isUserSmashEggToday[dayIndex][msg.sender] = true;
        }

        address[] memory chickAddrArray = new address[](10);
        uint256[] memory tokenIds = new uint256[](10);
        uint256 count = 0;
        aleadyBrokenEggAmount = aleadyBrokenEggAmount.add(amount);

        for(uint256 i=0; i<amount; i++){
            if(isWon()){
                (uint256 tokenId, address chickAddr) = getOneChickNFT();
                if(tokenId != 0){
                    chickAddrArray[count] = chickAddr;
                    tokenIds[count] = tokenId;

                    count++;
                }
            }
        }

        if(amount == 10 && count < 5){
            uint256 count2 = uint256(5).sub(count);
            for(uint256 i=0; i<count2; i++){
                (uint256 tokenId, address chickAddr) = getOneChickNFT();
                if(tokenId != 0){
                    chickAddrArray[count] = chickAddr;
                    tokenIds[count] = tokenId;

                    count++;
                }
            }
        }
        eggToken.burn(amount);


        processActivity();

        emit SmashEggsEvent(msg.sender, amount, count, chickAddrArray, tokenIds);
    }

    /**
     * @notice Won or not
     */
    function isWon() internal returns(bool){
        uint256 random = updateSeed() % PRECISION;
        if(random < winningProbability){
            return true;
        }
    }

    function getOneChickNFT() internal returns(uint256, address){
        uint256 random = updateSeed() % PRECISION;
        uint256 index = TRUMP_CHICK_INDEX;

        if(shouldGenerateShriekingChick()){
            index = SHRIEKING_CHICK_INDEX;
            isHasCreatedShriekingChick = true;
        }else{
            for(uint256 i=0; i<chickProbability.length; i++){
                if(random > chickProbability[i]){
                    index = i;
                    break;
                }
            }
        }

        address chickAddr = loserChickAddrArray[index];
        LoserChickNFT loserChickNFT = LoserChickNFT(chickAddr);

        uint256 tokenId = 0;
        if(loserChickNFT.totalSupply() < loserChickNFT.maxSupply()){
            tokenId = loserChickNFT.createNFT(msg.sender);
        }
        return (tokenId, chickAddr);
    }

    function shouldGenerateShriekingChick() internal returns(bool){
        if(shriekingChickSwitch && shriekingStartNumber < aleadyBrokenEggAmount 
          && aleadyBrokenEggAmount <= shriekingEndNumber && !isHasCreatedShriekingChick){
            uint256 random = updateSeed() % PRECISION;
            return random > shriekingProbability;
        }
        return false;
    }

    function updateShriekingProbability(uint256 _shriekingProbability) public onlyOwner{
        shriekingProbability = _shriekingProbability;
    }

    function updateShriekingStartNumberAndSectionSize(uint256 _startNumber, uint256 _sectionSize) public onlyOwner{
        shriekingStartNumber = _startNumber;
        shriekingSectionSize = _sectionSize;
        shriekingEndNumber = shriekingStartNumber + shriekingSectionSize;

        isHasCreatedShriekingChick = false;
    }

    function updateShriekingChickSwitch(bool _shriekingChickSwitch) public onlyOwner{
        shriekingChickSwitch = _shriekingChickSwitch;
    }

    function updateRandomAddr(address _randomAddr) public onlyOwner{
        randomContract = RandomInterface(_randomAddr);
    }

    function updateAleadyBrokenEggAmount(uint256 _aleadyBrokenEggAmount) public onlyOwner{
        aleadyBrokenEggAmount = _aleadyBrokenEggAmount;
    }

    function updateSeed() internal returns(uint256 random){
        seed += randomContract.getRandomNumber();        
        random = uint256(keccak256(abi.encodePacked(seed)));
    }


    function processActivity() internal{
        if(activityNFTProbability == 0){
            return;
        }
        uint256 NFTCount = 0;
        uint256 random = updateSeed() % PRECISION;
        if(activityNFTProbability > random){
            ERC721 erc721 = ERC721(activityNFTAddr);
            uint256 amount = erc721.balanceOf(address(this));
            if(amount > 0){
                uint256 tokenId = erc721.tokenOfOwnerByIndex(address(this), 0);
                erc721.transferFrom(address(this), address(msg.sender), tokenId);
                NFTCount = 1;
                emit ActivityEvent(msg.sender, NFTCount, activityNFTAddr);
            }
        }        
    }

    function transferActivityNFT(address receiver, uint256 count) external onlyOwner{
        ERC721 erc721 = ERC721(activityNFTAddr);
        uint256 amount = erc721.balanceOf(address(this));
        require(count <= amount, 'Count input error!');
        for(uint256 i=0; i<count; i++){
            uint256 tokenId = erc721.tokenOfOwnerByIndex(address(this), 0);
            erc721.transferFrom(address(this), receiver, tokenId);
        }
    }

    function updateLoserChickAddr(uint256 index, address loserChickAddr) public onlyOwner{
        loserChickAddrArray[index] = loserChickAddr;
    }

    function updateEggToken(address eggTokenAddr) public onlyOwner{
        eggToken = EggToken(eggTokenAddr);
    }

    function updateSmathEggSwitch(bool _smathEggSwitch) public onlyAdmin{
        smathEggSwitch = _smathEggSwitch;
    }
}