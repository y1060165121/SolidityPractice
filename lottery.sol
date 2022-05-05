// SPDX-License-Identifier: GPL-3.0-only
// This is a PoC to use the staking precompile wrapper as a Solidity developer.
pragma solidity >=0.8.0;

contract Lottery{

  address public manager;
  address payable [] public players;

  uint256 public constant ticketPrice = 1 ether;
  uint256 public currentTime;

  constructor() {
        manager = msg.sender;
        //automatically adds admin on deployment

  }

  function enterGame() public payable {
      require(msg.value > ticketPrice);
      players.push(payable(msg.sender));

      if (players.length >= 10 || currentTime + 1 hours < block.timestamp){
          pickWinnerAndTransfer();
      }
      else if (players.length == 1){
        currentTime = block.timestamp;
      }
      else{
        return;
      }
  }

  function enterGameForSomeone(address someAddress) public payable {
      require(msg.value > ticketPrice);
      players.push(payable(someAddress));


      if (players.length >= 10 || currentTime + 1 hours < block.timestamp){
          pickWinnerAndTransfer();
      }
      else if (players.length == 1){
        currentTime = block.timestamp;
      }
      else{
        return;
      }
  }

  function random() private view returns (uint) {
      return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, players.length)));
  }

  function pickWinnerAndTransfer() public payable {
      uint index = random() % players.length;
      players[index].transfer(address(this)
          .balance);

  }

  function resetGame() public payable {
      players = new address payable[](0);
      currentTime = block.timestamp;
  }


}
