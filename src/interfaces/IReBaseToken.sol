//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReBaseToken {
    /**
     * @notice Mints new ReBase tokens to a specified address.
     * @param _to The address to mint the tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @notice Burns ReBase tokens from a specified address.
     * @param _from The address to burn the tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external;

    function balanceOf(address account) external view returns (uint256);
}