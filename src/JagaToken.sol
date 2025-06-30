// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract JagaToken is ERC20, Ownable {
    constructor() ERC20("JagaToken", "JAGA") {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address _to, uint256 _amount) external onlyOwner {
        _burn(to, amount);
    }
}
