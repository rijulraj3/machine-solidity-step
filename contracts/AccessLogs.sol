// Copyright 2023 Cartesi Pte. Ltd.

// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/// @dev This file is generated from helper_scripts/generate_AccessLogs.sh, one should not modify the content directly

pragma solidity ^0.8.0;

import "./Memory.sol";
import "./UArchConstants.sol";

library AccessLogs {
    using AccessLogs for bytes;
    using Memory for Memory.AlignedSize;

    struct Context {
        bytes32 currentRootHash;
        bytes buffer;
        uint128 pointer;
    }

    /// @notice Swap byte order of unsigned ints with 64 bytes
    /// @param num number to have bytes swapped
    function uint64SwapEndian(uint64 num) internal pure returns (uint64) {
        uint64 output = ((num & 0x00000000000000ff) << 56)
            | ((num & 0x000000000000ff00) << 40)
            | ((num & 0x0000000000ff0000) << 24) | ((num & 0x00000000ff000000) << 8)
            | ((num & 0x000000ff00000000) >> 8) | ((num & 0x0000ff0000000000) >> 24)
            | ((num & 0x00ff000000000000) >> 40)
            | ((num & 0xff00000000000000) >> 56);

        return output;
    }

    function writeBytes32(bytes memory data, uint128 offset, bytes32 val)
        internal
        pure
    {
        assembly {
            mstore(add(data, add(offset, 32)), val)
        }
    }

    function toBytes32(bytes memory data, uint128 offset)
        internal
        pure
        returns (bytes32)
    {
        bytes32 temp;
        // Get 32 bytes from data
        assembly {
            temp := mload(add(data, add(offset, 32)))
        }
        return temp;
    }

    ///@dev bytes buffer layouts differently for `readWord` and `writeWord`,
    ///`readWord` [8 bytes as uint64 value, 32 bytes as drive hash, 61 * 32 bytes as sibling proofs]
    ///`writeWord` [32 bytes as old drive hash, 32 * 61 bytes as sibling proofs]

    //
    // Read methods
    //
    function readRegion(
        AccessLogs.Context memory a,
        Memory.Region memory region
    ) internal pure returns (bytes32) {
        bytes32 drive = a.buffer.toBytes32(a.pointer);
        a.pointer += 32;
        (bytes32 rootHash, uint8 siblingCount) =
            getRoot(region, drive, a.buffer, a.pointer);
        a.pointer += uint128(siblingCount) * 32;

        require(a.currentRootHash == rootHash, "Read region root doesn't match");

        return drive;
    }

    function readLeaf(AccessLogs.Context memory a, Memory.Stride readStride)
        internal
        pure
        returns (bytes32)
    {
        Memory.Region memory r =
            Memory.regionFromStride(readStride, Memory.alignedSizeFromLog2(0));
        return readRegion(a, r);
    }

    function readWord(
        AccessLogs.Context memory a,
        Memory.PhysicalAddress readAddress
    ) internal pure returns (uint64) {
        uint64 val =
            uint64SwapEndian(uint64(bytes8(a.buffer.toBytes32(a.pointer))));
        a.pointer += 8;
        bytes32 valHash = keccak256(abi.encodePacked(uint64SwapEndian(val)));
        bytes32 expectedValHash =
            readLeaf(a, Memory.strideFromWordAddress(readAddress));

        require(valHash == expectedValHash, "Read value doesn't match");
        return val;
    }

    //
    // Write methods
    //
    function writeRegion(
        AccessLogs.Context memory a,
        Memory.Region memory region,
        bytes32 newHash
    ) internal pure {
        bytes32 oldDrive = a.buffer.toBytes32(a.pointer);
        a.pointer += 32;
        (bytes32 rootHash, uint8 siblingCount) =
            getRoot(region, oldDrive, a.buffer, a.pointer);

        require(
            a.currentRootHash == rootHash, "Write region root doesn't match"
        );

        (bytes32 newRootHash,) = getRoot(region, newHash, a.buffer, a.pointer);
        a.pointer += uint128(siblingCount) * 32;

        a.currentRootHash = newRootHash;
    }

    function writeLeaf(
        AccessLogs.Context memory a,
        Memory.Stride writeStride,
        bytes32 newHash
    ) internal pure {
        Memory.Region memory r =
            Memory.regionFromStride(writeStride, Memory.alignedSizeFromLog2(0));
        writeRegion(a, r, newHash);
    }

    function writeWord(
        AccessLogs.Context memory a,
        Memory.PhysicalAddress writeAddress,
        uint64 newValue
    ) internal pure {
        writeLeaf(
            a,
            Memory.strideFromWordAddress(writeAddress),
            keccak256(abi.encodePacked(uint64SwapEndian(newValue)))
        );
    }

    uint8 constant LOG2RANGE = 61;

    function isEven(uint64 x) private pure returns (bool) {
        return x % 2 == 0;
    }

    function getRoot(
        Memory.Region memory region,
        bytes32 drive,
        bytes memory siblings,
        uint128 offset
    ) internal pure returns (bytes32, uint8) {
        // require that multiplier makes sense!
        uint8 logOfSize = region.alignedSize.log2();
        require(logOfSize <= LOG2RANGE, "Cannot be bigger than the tree itself");

        uint64 stride = Memory.Stride.unwrap(region.stride);
        uint8 nodesCount = LOG2RANGE - logOfSize;

        for (uint64 i = 0; i < nodesCount; i++) {
            if (isEven(stride >> i)) {
                drive = keccak256(
                    abi.encodePacked(drive, siblings.toBytes32(i * 32 + offset))
                );
            } else {
                drive = keccak256(
                    abi.encodePacked(siblings.toBytes32(i * 32 + offset), drive)
                );
            }
        }

        return (drive, nodesCount);
    }
}
