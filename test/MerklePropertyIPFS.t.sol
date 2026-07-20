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

    function test_SetAttributeMerkleRootEmitsEvent() external {
        bytes32 firstRoot = keccak256("FIRST_ROOT");
        bytes32 secondRoot = keccak256("SECOND_ROOT");

        vm.expectEmit(true, true, false, true);
        emit IMerklePropertyIPFS.AttributeMerkleRootUpdated(bytes32(0), firstRoot);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(firstRoot);

        vm.expectEmit(true, true, false, true);
        emit IMerklePropertyIPFS.AttributeMerkleRootUpdated(firstRoot, secondRoot);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(secondRoot);
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
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attributes;
        attributes[0] = 1;
        attributes[1] = 0;

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = helper.generateLeaf(1, attributes);
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

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
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attrs0;
        attrs0[0] = 1;
        attrs0[1] = 0;

        uint16[16] memory attrs1;
        attrs1[0] = 1;
        attrs1[1] = 1;

        uint16[16] memory attrs2;
        attrs2[0] = 1;
        attrs2[1] = 0;

        uint16[16] memory attrs3;
        attrs3[0] = 1;
        attrs3[1] = 1;

        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = helper.generateLeaf(0, attrs0);
        leaves[1] = helper.generateLeaf(1, attrs1);
        leaves[2] = helper.generateLeaf(2, attrs2);
        leaves[3] = helper.generateLeaf(3, attrs3);
        bytes32 merkleRoot = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        // Test Token 0
        {
            bytes32[] memory proof0 = helper.generateProof(leaves, 0);

            IMerklePropertyIPFS.SetAttributeParams memory params0 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });

            metadata.setAttributes(params0);
            uint16[16] memory stored0 = metadata.getRawAttributes(0);
            assertEq(keccak256(abi.encode(stored0)), keccak256(abi.encode(attrs0)), "Token 0 attributes should be set");
        }

        // Test Token 1
        {
            bytes32[] memory proof1 = helper.generateProof(leaves, 1);

            IMerklePropertyIPFS.SetAttributeParams memory params1 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attrs1, proof: proof1 });

            metadata.setAttributes(params1);
            uint16[16] memory stored1 = metadata.getRawAttributes(1);
            assertEq(keccak256(abi.encode(stored1)), keccak256(abi.encode(attrs1)), "Token 1 attributes should be set");
        }

        // Test Token 2
        {
            bytes32[] memory proof2 = helper.generateProof(leaves, 2);

            IMerklePropertyIPFS.SetAttributeParams memory params2 =
                IMerklePropertyIPFS.SetAttributeParams({ tokenId: 2, attributes: attrs2, proof: proof2 });

            metadata.setAttributes(params2);
            uint16[16] memory stored2 = metadata.getRawAttributes(2);
            assertEq(keccak256(abi.encode(stored2)), keccak256(abi.encode(attrs2)), "Token 2 attributes should be set");
        }

        // Test Token 3
        {
            bytes32[] memory proof3 = helper.generateProof(leaves, 3);

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
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        // Prepare batch params for tokens 0 and 1
        IMerklePropertyIPFS.SetAttributeParams[] memory batchParams = new IMerklePropertyIPFS.SetAttributeParams[](2);

        // Token 0
        uint16[16] memory attrs0;
        attrs0[0] = 1;
        attrs0[1] = 0;

        // Token 1
        uint16[16] memory attrs1;
        attrs1[0] = 1;
        attrs1[1] = 1;

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = helper.generateLeaf(0, attrs0);
        leaves[1] = helper.generateLeaf(1, attrs1);
        bytes32 merkleRoot = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        bytes32[] memory proof0 = helper.generateProof(leaves, 0);
        bytes32[] memory proof1 = helper.generateProof(leaves, 1);

        batchParams[0] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });
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
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        IMerklePropertyIPFS.SetAttributeParams[] memory batchParams = new IMerklePropertyIPFS.SetAttributeParams[](2);

        // Token 0 with valid proof
        uint16[16] memory attrs0;
        attrs0[0] = 1;
        attrs0[1] = 0;

        // Token 1 with INVALID proof (last byte changed)
        uint16[16] memory attrs1;
        attrs1[0] = 1;
        attrs1[1] = 1;

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = helper.generateLeaf(0, attrs0);
        leaves[1] = helper.generateLeaf(1, attrs1);
        bytes32 merkleRoot = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(merkleRoot);

        bytes32[] memory proof0 = helper.generateProof(leaves, 0);
        bytes32[] memory proof1 = helper.generateProof(leaves, 1);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(proof1[0]) ^ 1);

        batchParams[0] = IMerklePropertyIPFS.SetAttributeParams({ tokenId: 0, attributes: attrs0, proof: proof0 });
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
    ///          ATTRIBUTE VALIDATION TESTS                     ///
    ///                                                          ///

    /// @notice Test that zero property count is rejected
    function testRevert_SetAttributes_ZeroPropertyCount() external {
        // Don't add any properties, so actualPropertyCount = 0

        uint16[16] memory attributes;
        attributes[0] = 0; // Zero property count - INVALID

        // Generate valid Merkle proof for this invalid attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSelector(IMerklePropertyIPFS.INVALID_ATTRIBUTE_PROPERTY_COUNT.selector, 1, 0, 0));
        metadata.setAttributes(params);
    }

    /// @notice Test that property count mismatch is rejected
    function testRevert_SetAttributes_PropertyCountMismatch() external {
        // Add 1 property
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attributes;
        attributes[0] = 10; // Claim 10 properties, but only 1 exists - INVALID
        attributes[1] = 0;

        // Generate valid Merkle proof for this invalid attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSelector(IMerklePropertyIPFS.INVALID_ATTRIBUTE_PROPERTY_COUNT.selector, 1, 10, 1));
        metadata.setAttributes(params);
    }

    /// @notice Test that out of bounds item index is rejected
    function testRevert_SetAttributes_InvalidItemIndex() external {
        // Add 1 property with 2 items (indices 0, 1)
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attributes;
        attributes[0] = 1; // 1 property
        attributes[1] = 99; // Item index 99 - but only 0,1 are valid - INVALID

        // Generate valid Merkle proof for this invalid attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSelector(IMerklePropertyIPFS.INVALID_ATTRIBUTE_ITEM_INDEX.selector, 1, 0, 99, 1));
        metadata.setAttributes(params);
    }

    /// @notice Test that too many properties (>15) is rejected
    function testRevert_SetAttributes_TooManyProperties() external {
        uint16[16] memory attributes;
        attributes[0] = 16; // 16 properties - exceeds max of 15 - INVALID

        // Generate valid Merkle proof for this invalid attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSelector(IMerklePropertyIPFS.INVALID_ATTRIBUTE_PROPERTY_COUNT.selector, 1, 16, 15));
        metadata.setAttributes(params);
    }

    /// @notice Test that valid attributes work and can render tokenURI
    function test_SetAttributes_ValidAttributesRender() external {
        // Add properties
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mockMetadata();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attributes;
        attributes[0] = 1; // 1 property (matches actual count)
        attributes[1] = 0; // Valid item index (property has 2 items, so 0 and 1 are valid)

        // Generate valid Merkle proof for this VALID attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        // Should succeed
        metadata.setAttributes(params);

        // Should be able to render tokenURI without reverting
        string memory uri = metadata.tokenURI(1);
        assertGt(bytes(uri).length, 0, "Should generate non-empty tokenURI");
    }

    /// @notice Test that attributes with multiple properties validate correctly
    function testRevert_SetAttributes_MultiProperty_OneInvalidIndex() external {
        // Add 3 properties
        (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup) = _mock3Properties();

        vm.prank(owner);
        metadata.addProperties(names, items, ipfsGroup);

        uint16[16] memory attributes;
        attributes[0] = 3; // 3 properties
        attributes[1] = 0; // Valid for property 0 (has 2 items)
        attributes[2] = 0; // Valid for property 1 (has 2 items)
        attributes[3] = 5; // INVALID for property 2 (only has 2 items: 0 and 1)

        // Generate valid Merkle proof for this invalid attribute
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(uint256(1), attributes));
        bytes32 root = helper.buildMerkleRoot(leaves);

        vm.prank(owner);
        metadata.setAttributeMerkleRoot(root);

        bytes32[] memory proof = helper.generateProof(leaves, 0);

        IMerklePropertyIPFS.SetAttributeParams memory params =
            IMerklePropertyIPFS.SetAttributeParams({ tokenId: 1, attributes: attributes, proof: proof });

        vm.expectRevert(abi.encodeWithSelector(IMerklePropertyIPFS.INVALID_ATTRIBUTE_ITEM_INDEX.selector, 1, 2, 5, 1));
        metadata.setAttributes(params);
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
        items[1] = IPropertyIPFS.ItemParam({ propertyId: 0, name: "item2", isNewProperty: false });

        ipfsGroup = IPropertyIPFS.IPFSGroup({ baseUri: "BASE_URI", extension: "EXTENSION" });
    }

    function _mock3Properties()
        private
        pure
        returns (string[] memory names, IPropertyIPFS.ItemParam[] memory items, IPropertyIPFS.IPFSGroup memory ipfsGroup)
    {
        names = new string[](3);
        names[0] = "Background";
        names[1] = "Body";
        names[2] = "Head";

        items = new IPropertyIPFS.ItemParam[](6);
        items[0] = IPropertyIPFS.ItemParam({ propertyId: 0, name: "Blue", isNewProperty: true });
        items[1] = IPropertyIPFS.ItemParam({ propertyId: 0, name: "Red", isNewProperty: false });
        items[2] = IPropertyIPFS.ItemParam({ propertyId: 1, name: "Robot", isNewProperty: true });
        items[3] = IPropertyIPFS.ItemParam({ propertyId: 1, name: "Human", isNewProperty: false });
        items[4] = IPropertyIPFS.ItemParam({ propertyId: 2, name: "Hat", isNewProperty: true });
        items[5] = IPropertyIPFS.ItemParam({ propertyId: 2, name: "Crown", isNewProperty: false });

        ipfsGroup = IPropertyIPFS.IPFSGroup({ baseUri: "ipfs://base/", extension: ".png" });
    }
}
