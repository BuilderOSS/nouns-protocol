// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "../src/lib/proxy/ERC1967Proxy.sol";
import { MerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/MerklePropertyIPFS.sol";
import { IMerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/IMerklePropertyIPFS.sol";
import { IPropertyIPFS } from "../src/token/metadata/renderers/PropertyIPFS/IPropertyIPFS.sol";

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

    address owner = address(0xB0B);
    address manager = address(0x4A4A6E6);

    function setUp() external {
        address metadataImpl = address(new MerklePropertyIPFS(manager));
        metadata = MerklePropertyIPFS(address(new ERC1967Proxy(metadataImpl, "")));
        token = new MockMetadataToken(owner);

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
