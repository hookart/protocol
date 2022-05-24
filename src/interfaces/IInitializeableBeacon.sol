pragma solidity ^0.8.10;

/// @title Interface for a beacon with an initializer function
/// @author Jake Nyquist -- j@hook.xyz
/// @dev the Hook Beacons conform to this iterface, and can be called
/// with this initializer in order to start a beacon
interface IInitializeableBeacon {
  function initializeBeacon(address beacon, bytes memory data) external;
}
