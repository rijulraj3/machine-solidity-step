// Copyright 2023 Cartesi Pte. Ltd.

// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

pragma solidity ^0.8.0;

import "./interfaces/IAccessLogs.sol";
import "./Memory.sol";
import "./UArchCompat.sol";

library AccessLogs {
    using Memory for Memory.AlignedSize;

    //
    // Read methods
    //

    function readRegion(
        IAccessLogs.Context memory a,
        Memory.Region memory region
    ) internal pure returns (bytes32) {
        bytes32 drive = a.hashes[a.currentHashIndex++];
        (bytes32 rootHash, uint8 siblingCount) = getRoot(
            region,
            drive,
            a.hashes,
            a.currentHashIndex
        );
        a.currentHashIndex += siblingCount;

        require(
            a.currentRootHash == rootHash,
            "Read region root doesn't match"
        );

        return drive;
    }

    function readLeaf(
        IAccessLogs.Context memory a,
        uint64 readAddress
    ) internal pure returns (bytes32) {
        Memory.Region memory r = Memory.regionFromMemoryAddress(
            Memory.MemoryAddress.wrap(readAddress),
            Memory.AlignedSize.wrap(0)
        );
        return readRegion(a, r);
    }

    function readWord(
        IAccessLogs.Context memory a,
        uint64 readAddress
    ) internal pure returns (uint64) {
        uint64 val = a.words[a.currentWord++];
        bytes32 valHash = keccak256(
            abi.encodePacked(UArchCompat.uint64SwapEndian(val))
        );
        bytes32 expectedValHash = readLeaf(a, readAddress);

        require(valHash == expectedValHash, "Read value doesn't match");
        return val;
    }

    //
    // Write methods
    //

    function writeRegion(
        IAccessLogs.Context memory a,
        Memory.Region memory region,
        bytes32 newHash
    ) internal pure {
        bytes32 oldDrive = a.hashes[a.currentHashIndex++];
        (bytes32 rootHash, uint8 siblingCount) = getRoot(
            region,
            oldDrive,
            a.hashes,
            a.currentHashIndex
        );

        require(
            a.currentRootHash == rootHash,
            "Write region root doesn't match"
        );

        (bytes32 newRootHash, ) = getRoot(
            region,
            newHash,
            a.hashes,
            a.currentHashIndex
        );

        a.currentHashIndex += siblingCount;
        a.currentRootHash = newRootHash;
    }

    function writeLeaf(
        IAccessLogs.Context memory a,
        uint64 writeAddress,
        bytes32 newHash
    ) internal pure {
        Memory.Region memory r = Memory.regionFromMemoryAddress(
            Memory.MemoryAddress.wrap(writeAddress),
            Memory.AlignedSize.wrap(0)
        );
        writeRegion(a, r, newHash);
    }

    function writeWord(
        IAccessLogs.Context memory a,
        uint64 writeAddress,
        uint64 newValue
    ) internal pure {
        writeLeaf(
            a,
            writeAddress,
            keccak256(abi.encodePacked(UArchCompat.uint64SwapEndian(newValue)))
        );
    }

    uint8 constant LOG2RANGE = 61;

    function isEven(uint64 x) private pure returns (bool) {
        return x % 2 == 0;
    }

    function getRoot(
        Memory.Region memory region,
        bytes32 drive,
        bytes32[] memory siblings,
        uint128 offset
    ) internal pure returns (bytes32, uint8) {
        // require that multiplier makes sense!
        uint8 logOfSize = region.alignedSize.log2();
        require(
            logOfSize <= LOG2RANGE,
            "Cannot be bigger than the tree itself"
        );

        uint64 stride = Memory.Stride.unwrap(region.stride);
        uint8 nodesCount = LOG2RANGE - logOfSize;

        for (uint64 i = 0; i < nodesCount; i++) {
            if (isEven(stride >> i)) {
                drive = keccak256(
                    abi.encodePacked(drive, siblings[i + offset])
                );
            } else {
                drive = keccak256(
                    abi.encodePacked(siblings[i + offset], drive)
                );
            }
        }

        return (drive, nodesCount);
    }
}