const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const dotenv = require('dotenv');

// Load environment variables
dotenv.config();

// Helper to execute curl command and get bytecode
async function getBytecode(rpc, address) {
    const cmd = `curl -s --location ${rpc} \
        --header 'Content-Type: application/json' \
        --data '{"method":"eth_getCode", "params":["${address}","latest"], "id":1, "jsonrpc":"2.0"}' \
        | jq -r .result`;
    
    return execSync(cmd).toString().trim();
}

// Helper to get bytecode from compiled contract JSON
function getCompiledBytecode() {
    try {
        const contractPath = path.join(__dirname, '../../out/CREATE3Factory.sol/CREATE3Factory.json');
        const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
        return contractJson.deployedBytecode.object;
    } catch (error) {
        console.error('Error reading compiled contract bytecode:', error);
        return null;
    }
}


// Get RPC URL for a specific chain
function getRpcUrl(chainId) {
    const chainMapping = {
        1: process.env.MAINNET_RPC_URL,
        5: process.env.GOERLI_RPC_URL,
        42161: process.env.ARBITRUM_RPC_URL,
        421613: process.env.ARBITRUM_GOERLI_RPC_URL,
        10: process.env.OPTIMISM_RPC_URL,
        137: process.env.POLYGON_RPC_URL,
        43114: process.env.AVALANCHE_RPC_URL,
        250: process.env.FANTOM_RPC_URL,
        56: process.env.BINANCE_RPC_URL,
        100: process.env.GNOSIS_RPC_URL,
        11155111: process.env.SEPOLIA_RPC_URL,
        8453: process.env.BASE_RPC_URL,
        84532: process.env.BASE_SEPOLIA_RPC_URL,
        81457: process.env.BLAST_RPC_URL,
        17000: process.env.HOLESKY_RPC_URL,
        80094: process.env.BERA_RPC_URL,
        252: process.env.FRAXTAL_RPC_URL,
        2522: process.env.FRAXTAL_TESTNET_RPC_URL,
        43111: process.env.HEMI_RPC_URL,
        167000: process.env.TAIKO_RPC_URL,
        57073: process.env.INK_RPC_URL,
        5000: process.env.MANTLE_RPC_URL,
        534352: process.env.SCROLL_RPC_URL,
        // Add other chains as needed
    };
    
    return chainMapping[chainId];
}

// Main function to verify all deployments
async function main() {
    const deploymentsDir = path.join(__dirname, '../../deployments');
    const deploymentFiles = fs.readdirSync(deploymentsDir)
        .filter(file => file.endsWith('.json'));
    
    console.log(`Found ${deploymentFiles.length} deployment files to verify.`);
    
    for (const file of deploymentFiles) {
        try {
            const filePath = path.join(deploymentsDir, file);
            const deployment = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            
            const { chainid, CREATE3Factory } = deployment;
            const rpcUrl = getRpcUrl(chainid);
            
            if (!rpcUrl) {
                console.warn(`No RPC URL found for chain ID ${chainid} in file ${file}. Skipping verification.`);
                continue;
            }
            
            console.log(`Verifying CREATE3Factory at ${CREATE3Factory} on chain ${chainid}...`);
            const bytecode = await getBytecode(rpcUrl, CREATE3Factory);
            const compiledBytecode = await getCompiledBytecode();
            
            if (bytecode === '0x' || bytecode === '') {
                console.error(`❌ Contract not found at ${CREATE3Factory} on chain ${chainid}`);
            } else if (bytecode !== compiledBytecode) {
                console.error(`❌ Bytecode mismatch for ${CREATE3Factory} on chain ${chainid}`);
                console.log(`Compiled bytecode: ${compiledBytecode.toString()}...`);
                console.log(`Deployed bytecode: ${bytecode.substring(0, 100)}...`);
            } else {
                console.log(`✅ Contract verified at ${CREATE3Factory} on chain ${chainid}`);
            }
        } catch (error) {
            console.error(`Error verifying deployment in ${file}:`, error);
        }
    }
    
    console.log('Verification complete.');
}

// Execute main function if script is run directly
if (require.main === module) {
    main().catch(error => {
        console.error('Error in main function:', error);
        process.exit(1);
    });
}

module.exports = { getBytecode, main };
