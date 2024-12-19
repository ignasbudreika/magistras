const {
  SecretsManager,
  createGist,
} = require("@chainlink/functions-toolkit");

const ethers = require("ethers");
require("@chainlink/env-enc").config();

const makeRequestSepolia = async () => {
  const routerAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0"; // for Sepolia
  const donId = "fun-ethereum-sepolia-1"; // for Sepolia

  const secrets = { 'INFURA_API_KEY': '' }; // set secrets to encrypt

  const privateKey = ''; // set private key

  const rpcUrl = ''; // set RPC URL for selected network

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const wallet = new ethers.Wallet(privateKey);
  const signer = wallet.connect(provider);

  console.log("Starting secrets encryption");

  const secretsManager = new SecretsManager({
    signer: signer,
    functionsRouterAddress: routerAddress,
    donId: donId,
  });
  await secretsManager.initialize();

  const encryptedSecretsObj = await secretsManager.encryptSecrets(secrets);

  console.log(`Creating Gist`);
  const githubApiToken = ''; // set Github API token

  const gistURL = await createGist(
    githubApiToken,
    JSON.stringify(encryptedSecretsObj)
  );

  console.log(`Gist created ${gistURL}`);
  const encryptedSecretsUrls = await secretsManager.encryptSecretsUrls([
    gistURL,
  ]);

  console.log(`Encrypted URL: ${encryptedSecretsUrls}`);

  const verified = await secretsManager.verifyOffchainSecrets([
    gistURL,
  ]);

  console.log(`Verified encrypted URL: ${verified}`);
};

makeRequestSepolia().catch((e) => {
  console.error(e);
  process.exit(1);
});
