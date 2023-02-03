// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

/* preEVCToken Presale
 After Presale you'll be able to swap this token for EVC. Ratio 1:1
*/
contract preEVCToken is ERC20("preEVCToken", "PREEVC"), ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    address constant presaleAddress = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4; // 0x8471431268bf0359E2D13f5e0C9bb3d9931B4AAF

    IERC20 public USDC = IERC20(0xd9145CCE52D386f254917e481eB44e9943F39138); // 0xdeeabaE764D3D029123BDEd7d320EBDa7e2EA664
    IERC20 preevcToken = IERC20(address(this));

    uint256 public salePrice = 1;
    uint256 public constant preevcMaximumSupply = 50000000 * (10 ** 18); //20k
    uint256 public preevcRemaining = preevcMaximumSupply;
    uint256 public maxHardCap = 50000000 * (10 ** 18); // 20k usdc
    uint256 public constant maxpreEVCPurchase = 5000 * (10 ** 18); // 500 USDC
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public constant presaleDuration = 179800; // 5 days aprox

    mapping(address => uint256) public userpreEVCTotally;

    event StartBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event preevcPurchased(address sender, uint256 usdcSpent, uint256 preevcReceived);

    constructor(uint256 _startBlock) {
        startBlock = _startBlock;
        endBlock = _startBlock + presaleDuration;
        _mint(address(this), preevcMaximumSupply);
    }

    function buypreEVC(uint256 _usdcSpent) external nonReentrant {
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(preevcRemaining > 0, "No more preEVC remains!");
        require(preevcToken.balanceOf(address(this)) > 0, "No more preEVC left!");
        require(_usdcSpent > 0, "not enough usdc provided");
        require(_usdcSpent <= maxHardCap, "preEVC Presale hardcap reached");
        require(userpreEVCTotally[msg.sender] < maxpreEVCPurchase, "user has already purchased too much preevc");
        uint256 preevcPurchaseAmount = (_usdcSpent * 1000000000000) / salePrice;
        // if we dont have enough left, give them the rest.
        if (preevcRemaining < preevcPurchaseAmount)
            preevcPurchaseAmount = preevcRemaining;
        require(preevcPurchaseAmount > 0, "user cannot purchase 0 preevc");
        // shouldn't be possible to fail these asserts.
        assert(preevcPurchaseAmount <= preevcRemaining);
        assert(preevcPurchaseAmount <= preevcToken.balanceOf(address(this)));
        //send preevc to user
        preevcToken.safeTransfer(msg.sender, preevcPurchaseAmount);
        // send usdc to presale address
        USDC.safeTransferFrom(msg.sender, address(presaleAddress), _usdcSpent);
        preevcRemaining = preevcRemaining - preevcPurchaseAmount;
        userpreEVCTotally[msg.sender] = userpreEVCTotally[msg.sender] + preevcPurchaseAmount;
        emit preevcPurchased(msg.sender, _usdcSpent, preevcPurchaseAmount);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already started");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock = _newStartBlock + presaleDuration;
        emit StartBlockChanged(_newStartBlock, endBlock);
    }

}
