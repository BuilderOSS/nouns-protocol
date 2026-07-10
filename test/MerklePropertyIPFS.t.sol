// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { ERC1967Proxy } from "../src/lib/proxy/ERC1967Proxy.sol";
import { MerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/MerklePropertyIPFS.sol";
import { IMerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/IMerklePropertyIPFS.sol";
import { IPropertyIPFS } from "../src/token/metadata/renderers/PropertyIPFS/IPropertyIPFS.sol";
import { MerkleTreeHelper } from "./utils/MerkleTreeHelper.sol";

contract MockMetadataToken {
    address public owner;
    string public name = "Mock Token";

    constructor(address _owner) {
        owner = _owner;
    }
}

contract MerklePropertyIPFSTest is Test {
    MerklePropertyIPFS metadata;
    MockMetadataToken token;
    MerkleTreeHelper helper;

    address owner = address(0xB0B);
    address manager = address(0x4A4A6E6);

    function setUp() external {
        address metadataImpl = address(new MerklePropertyIPFS(manager));
        metadata = MerklePropertyIPFS(address(new ERC1967Proxy(metadataImpl, "")));
        token = new MockMetadataToken(owner);
        helper = new MerkleTreeHelper();

        bytes memory initStrings = abi.encode(
            "Mock Token",
            "MOCK",
            "This is a mock token",
            "ipfs://Qmew7TdyGnj6YRUjQR68sUJN3239MYXRD8uxowxF6rGK8j",
            "https://nouns.build",
            "http://localhost:5000/render"
        );

        vm.prank(manager);
        metadata.initialize(initStrings, address(token));
    }

    function test_AddPropertiesAndGenerateAttributes() external {
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        vm.prank(address(token));
        assertTrue(metadata.onMinted(1));

        uint16[16] memory attributes = metadata.getRawAttributes(1);
        assertEq(attributes[0], 1);
        assertLt(attributes[1], 2);
    }

    function test_SetAttributesWithProof() external {
        bytes32 root = 0x5e0f333d56d9716c0e2ae5f990981023f2bc6cb23eba6c7d60ba8146af726a8b;

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;
        attributes[5] = 0;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x040ebb2969ff59488f98dc7cd9014aa8b112ba4bf78c2f8bcf03be0fad0d2e0e;

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        metadata.setAttributes(params);

        uint16[16] memory newAttributes = metadata.getRawAttributes(1);
        assertEq(keccak256(abi.encode(newAttributes)), keccak256(abi.encode(attributes)));
    }

    function testRevert_SetAttributesInvalidProof() external {
        bytes32 root = 0x5e0f333d56d9716c0e2ae5f990981023f2bc6cb23eba6c7d60ba8146af726a8b;

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;
        attributes[5] = 0;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x040ebb2969ff59488f98dc7cd9014aa8b112ba4bf78c2f8bcf03be0fad0d2e0f;

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSignature("INVALID_MERKLE_PROOF(uint256,bytes32[],bytes32)", 1, proof, root));
        metadata.setAttributes(params);
    }

    ///                                                          ///
    ///              ENCODING VERIFICATION TESTS                ///
    ///                                                          ///

    /// @notice Verify that Solidity's abi.encodePacked produces expected byte length
    /// @dev Confirms that abi.encodePacked(uint256, uint16[16]) = 544 bytes
    ///      Array elements are padded to 32 bytes each
    function test_EncodingLength() external {
        uint256 tokenId = 1;
        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;

        uint256 length = helper.getEncodedLength(tokenId, attributes);

        // Expected: 32 bytes (uint256) + 512 bytes (16 * 32 bytes per padded uint16) = 544 bytes
        assertEq(length, 544, "Encoded length should be 544 bytes (padded array elements)");
    }

    /// @notice Verify that the helper contract generates the same leaf as the contract would
    function test_LeafGeneration() external {
        uint256 tokenId = 1;
        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;

        bytes32 leafFromHelper = helper.generateLeaf(tokenId, attributes);
        bytes32 leafDirect = keccak256(abi.encodePacked(tokenId, attributes));

        assertEq(leafFromHelper, leafDirect, "Helper should generate same leaf as direct encoding");
    }

    /// @notice Verify encoding produces correct hash
    function test_EncodingHash() external {
        uint256 tokenId = 1;
        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;

        (uint256 encodedLength, bytes32 encodedHash) = helper.compareEncodingMethods(tokenId, attributes);

        // Verify encoding length
        assertEq(encodedLength, 544, "Encoding should produce 544 bytes");

        // Verify hash matches direct encoding
        bytes32 directHash = keccak256(abi.encodePacked(tokenId, attributes));
        assertEq(encodedHash, directHash, "Hash should match direct encoding");

        console.log("Solidity abi.encodePacked(uint256, uint16[16]):");
        console.log("  Length: %d bytes", encodedLength);
        console.logBytes32(encodedHash);
    }

    ///                                                          ///
    ///          MULTI-TOKEN MERKLE TREE TESTS                  ///
    ///                                                          ///

    /// @notice Test merkle tree with 4 tokens
    /// @dev Uses data generated by script/generateMerkleTree.mjs
    ///
    /// Tree Structure:
    ///                      ROOT
    ///                   /        \
    ///             hash(0,1)    hash(2,3)
    ///              /    \        /    \
    ///          leaf0  leaf1  leaf2  leaf3
    ///
    /// Token 0: [1, 2, 3, 4, 5, 0, ...]
    /// Token 1: [5, 8, 4, 2, 1, 0, ...]
    /// Token 2: [10, 15, 20, 25, 30, 35, 40, 45, 0, ...]
    /// Token 3: [100, 200, 300, ..., 1600]
    function test_MultiTokenMerkleTree() external {
        bytes32 merkleRoot = 0xf3515c60c1b8186c52ea0ffa1a12c54b46e96726d570e9eb437187bcf6da11bb;

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        // Test Token 0
        {
            uint16[16] memory attrs0;
            attrs0[0] = 1;
            attrs0[1] = 2;
            attrs0[2] = 3;
            attrs0[3] = 4;
            attrs0[4] = 5;

            bytes32[] memory proof0 = new bytes32[](2);
            proof0[0] = 0xe99b1b662c4f9694206cd147c908667145a5f669a398cfcc903b407138d3e3d8;
            proof0[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab96e;

            IMerklePropertyIPFS.SetAttributeParams memory params0 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });

            metadata.setAttributes(params0);
            uint16[16] memory stored0 = metadata.getRawAttributes(0);
            assertEq(keccak256(abi.encode(stored0)), keccak256(abi.encode(attrs0)), "Token 0 attributes should be set");
        }

        // Test Token 1
        {
            uint16[16] memory attrs1;
            attrs1[0] = 5;
            attrs1[1] = 8;
            attrs1[2] = 4;
            attrs1[3] = 2;
            attrs1[4] = 1;

            bytes32[] memory proof1 = new bytes32[](2);
            proof1[0] = 0xa134d4d2b9a6b32f98acc89e974649b49c952fcc4164f0a179ea79a4144d5c04;
            proof1[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab96e;

            IMerklePropertyIPFS.SetAttributeParams memory params1 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attrs1, proof: proof1 });

            metadata.setAttributes(params1);
            uint16[16] memory stored1 = metadata.getRawAttributes(1);
            assertEq(keccak256(abi.encode(stored1)), keccak256(abi.encode(attrs1)), "Token 1 attributes should be set");
        }

        // Test Token 2
        {
            uint16[16] memory attrs2;
            attrs2[0] = 10;
            attrs2[1] = 15;
            attrs2[2] = 20;
            attrs2[3] = 25;
            attrs2[4] = 30;
            attrs2[5] = 35;
            attrs2[6] = 40;
            attrs2[7] = 45;

            bytes32[] memory proof2 = new bytes32[](2);
            proof2[0] = 0xa8a09b962e785d3a280867a8a9aa93a988397353d786ec2b71c8130539988636;
            proof2[1] = 0x33b837fe3507fca73c766c27d22728cc36ecd27e7368de6bb5e540d57a129887;

            IMerklePropertyIPFS.SetAttributeParams memory params2 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 2, attributes: attrs2, proof: proof2 });

            metadata.setAttributes(params2);
            uint16[16] memory stored2 = metadata.getRawAttributes(2);
            assertEq(keccak256(abi.encode(stored2)), keccak256(abi.encode(attrs2)), "Token 2 attributes should be set");
        }

        // Test Token 3
        {
            uint16[16] memory attrs3;
            attrs3[0] = 100;
            attrs3[1] = 200;
            attrs3[2] = 300;
            attrs3[3] = 400;
            attrs3[4] = 500;
            attrs3[5] = 600;
            attrs3[6] = 700;
            attrs3[7] = 800;
            attrs3[8] = 900;
            attrs3[9] = 1000;
            attrs3[10] = 1100;
            attrs3[11] = 1200;
            attrs3[12] = 1300;
            attrs3[13] = 1400;
            attrs3[14] = 1500;
            attrs3[15] = 1600;

            bytes32[] memory proof3 = new bytes32[](2);
            proof3[0] = 0x7f31627187e9a520ca83af95b7fc9d29e5edab5c08869070f4c07f1fa7ec8d25;
            proof3[1] = 0x33b837fe3507fca73c766c27d22728cc36ecd27e7368de6bb5e540d57a129887;

            IMerklePropertyIPFS.SetAttributeParams memory params3 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 3, attributes: attrs3, proof: proof3 });

            metadata.setAttributes(params3);
            uint16[16] memory stored3 = metadata.getRawAttributes(3);
            assertEq(keccak256(abi.encode(stored3)), keccak256(abi.encode(attrs3)), "Token 3 attributes should be set");
        }
    }

    ///                                                          ///
    ///          BATCH OPERATIONS TESTS                         ///
    ///                                                          ///

    /// @notice Test setting multiple tokens' attributes in a single transaction
    function test_SetManyAttributes() external {
        bytes32 merkleRoot = 0xf3515c60c1b8186c52ea0ffa1a12c54b46e96726d570e9eb437187bcf6da11bb;

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        // Prepare batch params for tokens 0 and 1
        IMerklePropertyIPFS.SetAttributeParams[] memory batchParams = new IMerklePropertyIPFS.SetAttributeParams[](2);

        // Token 0
        uint16[16] memory attrs0;
        attrs0[0] = 1;
        attrs0[1] = 2;
        attrs0[2] = 3;
        attrs0[3] = 4;
        attrs0[4] = 5;

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = 0xe99b1b662c4f9694206cd147c908667145a5f669a398cfcc903b407138d3e3d8;
        proof0[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab96e;

        batchParams[0] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });

        // Token 1
        uint16[16] memory attrs1;
        attrs1[0] = 5;
        attrs1[1] = 8;
        attrs1[2] = 4;
        attrs1[3] = 2;
        attrs1[4] = 1;

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = 0xa134d4d2b9a6b32f98acc89e974649b49c952fcc4164f0a179ea79a4144d5c04;
        proof1[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab96e;

        batchParams[1] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attrs1, proof: proof1 });

        // Set many attributes at once
        metadata.setManyAttributes(batchParams);

        // Verify both were set correctly
        uint16[16] memory stored0 = metadata.getRawAttributes(0);
        assertEq(keccak256(abi.encode(stored0)), keccak256(abi.encode(attrs0)), "Token 0 attributes should be set");

        uint16[16] memory stored1 = metadata.getRawAttributes(1);
        assertEq(keccak256(abi.encode(stored1)), keccak256(abi.encode(attrs1)), "Token 1 attributes should be set");
    }

    /// @notice Test that batch operation fails if one proof is invalid
    function testRevert_SetManyAttributes_OneInvalidProof() external {
        bytes32 merkleRoot = 0xf3515c60c1b8186c52ea0ffa1a12c54b46e96726d570e9eb437187bcf6da11bb;

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        IMerklePropertyIPFS.SetAttributeParams[] memory batchParams = new IMerklePropertyIPFS.SetAttributeParams[](2);

        // Token 0 with valid proof
        uint16[16] memory attrs0;
        attrs0[0] = 1;
        attrs0[1] = 2;
        attrs0[2] = 3;
        attrs0[3] = 4;
        attrs0[4] = 5;

        bytes32[] memory proof0 = new bytes32[](2);
        proof0[0] = 0xe99b1b662c4f9694206cd147c908667145a5f669a398cfcc903b407138d3e3d8;
        proof0[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab96e;

        batchParams[0] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });

        // Token 1 with INVALID proof (last byte changed)
        uint16[16] memory attrs1;
        attrs1[0] = 5;
        attrs1[1] = 8;
        attrs1[2] = 4;
        attrs1[3] = 2;
        attrs1[4] = 1;

        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = 0xa134d4d2b9a6b32f98acc89e974649b49c952fcc4164f0a179ea79a4144d5c04;
        invalidProof[1] = 0x4e5208328ba781525892b1edeb2d4611f6d7d592752e5cb10cad428dd1cab9FF; // Changed last byte

        batchParams[1] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attrs1, proof: invalidProof });

        vm.expectRevert(abi.encodeWithSignature("INVALID_MERKLE_PROOF(uint256,bytes32[],bytes32)", 1, invalidProof, merkleRoot));
        metadata.setManyAttributes(batchParams);
    }

    ///                                                          ///
    ///          CROSS-VERIFICATION TEST                        ///
    ///                                                          ///

    /// @notice Verify that JavaScript encoding matches Solidity encoding
    /// @dev This test proves the TypeScript/JavaScript implementation is correct
    function test_CrossVerification_JavaScriptAndSolidity() external {
        uint256 tokenId = 1;
        uint16[16] memory attributes;
        attributes[0] = 5;
        attributes[1] = 8;
        attributes[2] = 4;
        attributes[3] = 2;
        attributes[4] = 1;

        // Generate leaf using Solidity
        bytes32 solidityLeaf = keccak256(abi.encodePacked(tokenId, attributes));

        // Expected leaf from JavaScript (using viem's encodePacked)
        bytes32 javascriptLeaf = 0xe99b1b662c4f9694206cd147c908667145a5f669a398cfcc903b407138d3e3d8;

        console.log("Cross-Verification:");
        console.log("  Solidity leaf:");
        console.logBytes32(solidityLeaf);
        console.log("  JavaScript leaf:");
        console.logBytes32(javascriptLeaf);

        // Verify they match
        assertEq(solidityLeaf, javascriptLeaf, "Solidity and JavaScript encoding must match");
    }

    ///                                                          ///
    ///          HELPER FUNCTIONS                               ///
    ///                                                          ///

    function _mockMetadata()
        private
        pure
        returns (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup)
    {
        names = new string[](1);
        names[0] = "testing";

        items = new IPropertyIPFS.ItemParam[](2);
        items[0] = IPropertyIPFS.ItemParam({ propertyId: 0, name: "item1", isNewProperty: true });
        items[1] = IPropertyIPFS.ItemParam({ propertyId: 0, name: "item2", isNewProperty: true });

        ipfsGroup = IPropertyIPFS.IPFSGroup({ baseUri: "BASE_URI", extension: "EXTENSION" });
    }
}
