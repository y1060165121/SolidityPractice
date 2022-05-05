// SPDX-License-Identifier: GPL-3.0-only
// This is a PoC to use the staking precompile wrapper as a Solidity developer.
pragma solidity >=0.8.0;

contract Lottery{

  address public manager;
  address payable [] public players;

  uint256 public constant ticketPrice = 1 ether;
  uint256 public currentTime;

  constructor() {
        admin = msg.sender;
        //automatically adds admin on deployment

  }

  function enterGame() public payable {
      require(msg.value > ticketPrice);
      players.push(msg.sender);

      if (players.length >= 10 || current + 1 hours < now){
          pickWinnerAndDeposit();
      }
      else if (players.length == 1){
        currentTime = now;
      }
      else{
        return
      }
  }

  function enterGameForSomeone(address someAddress) public payable {
      require(msg.value > ticketPrice);
      players.push(someAddress);

      if (players.length >= 10 || current + 1 hours < now){
          pickWinnerAndDeposit();
      }
      else if (players.length == 1){
        currentTime = now
      }
      else{
        return
      }
  }

  function random() private view returns (uint) {
      return uint(keccak256(block.difficulty, block.timestamp, players));
  }

  function pickWinnerAndTransfer() public payable {
      uint index = random() % players.length;
      players[index].transfer(address(this)
          .balance);

  }

  function getPlayers() public view returns (address[]) {
      return players;
  }

  function resetGame() public payable {
      players = new address[](0);
      currentTime = now;
  }


}
