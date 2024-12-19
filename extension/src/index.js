import { ethers } from "ethers";
import { SubscriptionManager } from "@chainlink/functions-toolkit";

const abiCoder = ethers.utils.defaultAbiCoder;

const NETWORK_CONFIGS = new Map([
  ["Ethereum Mainnet", {
    "ETHUSD": "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
    "LINKUSD": "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c",
    "LINK": "0x514910771AF9Ca656af840dff83E8264EcF986CA",
    "FUNCTIONS_ROUTER": "0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6",
    "DON_ID": "fun-ethereum-mainnet-1"
  }],
  ["Sepolia", {
    "ETHUSD": "0x694AA1769357215DE4FAC081bf1f309aDC325306",
    "LINKUSD": "0xc59E3633BAAC79493d908e63626716e204A45EdF",
    "LINK": "0x779877a7b0d9e8603169ddbd7836e478b4624789",
    "FUNCTIONS_ROUTER": "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0",
    "DON_ID": "fun-ethereum-sepolia-1"
  }],
]);

async function getCurrentGasPriceInGwei(provider) {
  try {
    let gasPrice = (await provider.getFeeData()).gasPrice;
    gasPrice = ethers.utils.formatUnits(gasPrice, "gwei");

    console.log("Current gas price in ETH:", gasPrice * 0.000000001);
    console.log("Current gas price in gwei:", gasPrice);
    console.log("Current gas price in wei:", gasPrice * 1000000000);

    return gasPrice;
  } catch (ex) {
    console.error("Unable to fetch current gas price", ex);
    return -1;
  }
}

async function getCurrencyRates(network, provider) {
  try {
    const functionSelector = "0xfeaf968c";

    const ethUsdContractAddress = NETWORK_CONFIGS.get(network).ETHUSD;

    const ethUsdData = await provider.call({
      to: ethUsdContractAddress,
      data: functionSelector
    });
    const decodedEthUsdData = abiCoder.decode(
      ["uint80", "int256", "uint256", "uint256", "uint80"],
      ethUsdData
    );
    const ethUsdPrice = decodedEthUsdData[1];
    const ethUsd = ethers.utils.formatUnits(ethUsdPrice, 8);
    console.log("ETH currency rate:", ethUsd);

    const linkUsdContractAddress = NETWORK_CONFIGS.get(network).LINKUSD;
    const linkUsdData = await provider.call({
      to: linkUsdContractAddress,
      data: functionSelector
    });
    const decodedLinkUsdData = abiCoder.decode(
      ["uint80", "int256", "uint256", "uint256", "uint80"],
      linkUsdData
    );
    const linkUsdPrice = decodedLinkUsdData[1];
    const linkUsd = ethers.utils.formatUnits(linkUsdPrice, 8);
    console.log("LINK currency rate:", linkUsd);

    return new Map([
      ["ETH", ethUsd],
      ["LINK", linkUsd],
    ]);
  } catch (ex) {
    console.log('Unable to retrieve ETH/USD or LINK/USD rate', ex);
    return new Map();
  }
}

async function estimateFunctionCallGasFeesInWei(provider, contractAddress, callerAddress, functionSignature, inputData) {
  try {
    const functionName = functionSignature.substring(0, functionSignature.indexOf("("));

    const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
    const data = iface.encodeFunctionData(functionName, [inputData]);

    const gasEstimate = await provider.estimateGas({
      to: contractAddress,
      from: callerAddress,
      data: data,
    });

    console.log(`Estimated Gas: ${gasEstimate.toString()}`);

    return gasEstimate;
  } catch (ex) {
    console.error("Error estimating function call gas fees", ex);
    return -1;
  }
}

async function estimateChainlinkFunctionRequestFulfilmentCostInLINK(network, provider, gasPriceGwei, subscriptionId, callbackGasLimit) {
  try {
    const gasPriceWei = gasPriceGwei * 1000000000;

    const wallet = ethers.Wallet.createRandom();
    const signer = wallet.connect(provider);

    const subscriptionManager = new SubscriptionManager({
      signer: signer,
      linkTokenAddress: NETWORK_CONFIGS.get(network).LINK,
      functionsRouterAddress: NETWORK_CONFIGS.get(network).FUNCTIONS_ROUTER,
    });
    await subscriptionManager.initialize();

    const estimatedCostInJuels =
      await subscriptionManager.estimateFunctionsRequestCost({
        donId: NETWORK_CONFIGS.get(network).DON_ID,
        subscriptionId: subscriptionId,
        callbackGasLimit: callbackGasLimit,
        gasPriceWei: BigInt(gasPriceWei),
      });

    console.log(
      `Fulfilment cost estimated to ${ethers.utils.formatEther(
        estimatedCostInJuels
      )} LINK`
    );

    return ethers.utils.formatEther(estimatedCostInJuels);
  } catch (ex) {
    console.log('Unable to estimate Chainlink Functions request fulfilment cost', ex);
    return -1;
  }
}

async function estimateFunctionCallCostInUSD(provider, gasPriceGwei, currencyRates, contractAddress, callerAddress, functionSignature, data) {
  const gasPriceinETH = gasPriceGwei * 0.000000001;

  const functionGasEstimateInWei = await estimateFunctionCallGasFeesInWei(provider, contractAddress, callerAddress, functionSignature, data);
  if (functionGasEstimateInWei == -1) {
    return -1;
  }

  const costInUSD =
    functionGasEstimateInWei * gasPriceinETH * currencyRates.get("ETH");

  console.log(`Estimated function call cost in USD: ${costInUSD.toString()}`);

  return costInUSD;
}

async function estimateChainlinkFunctionRequestCostInUSD(network, provider, gasPriceGwei, currencyRates, subscriptionId, callbackGasLimit) {
  const functionRequestCostInLINK =
    await estimateChainlinkFunctionRequestFulfilmentCostInLINK(network, provider, gasPriceGwei, subscriptionId, callbackGasLimit);
  if (functionRequestCostInLINK == -1) {
    return -1;
  }

  const costInUSD = functionRequestCostInLINK * currencyRates.get("LINK");

  console.log(`Estimated Chainlink Functions request cost in USD: ${costInUSD.toString()}`);

  return costInUSD;
}

async function estimateCosts(
  network,
  provider,
  gasPriceGwei,
  onChainContractAddress,
  onChainContractCallerAddress,
  onChainFunctionSignature,
  onChainInputData,
  offChainContractAddress,
  offChainContractCallerAddress,
  offChainFunctionSignature,
  offChainInputData,
  subscriptionId,
  callbackGasLimit
) {
  if (gasPriceGwei == -1) {
    gasPriceGwei = await getCurrentGasPriceInGwei(provider);
  }
  if (gasPriceGwei == -1) {
    return new Map();
  }

  const rates = await getCurrencyRates(network, provider);
  if (rates.size == 0) {
    return new Map();
  }

  const onChainCostInUSD = await estimateFunctionCallCostInUSD(
    provider, gasPriceGwei, rates, onChainContractAddress, onChainContractCallerAddress, onChainFunctionSignature, onChainInputData);
  if (onChainCostInUSD == -1) {
    return new Map();
  }

  const offChainCallCostInUSD = await estimateFunctionCallCostInUSD(
    provider, gasPriceGwei, rates, offChainContractAddress, offChainContractCallerAddress, offChainFunctionSignature, offChainInputData);
  if (offChainCallCostInUSD == -1) {
    return new Map();
  }

  const chainlinkFunctionRequestCostInUSD = await estimateChainlinkFunctionRequestCostInUSD(
    network, provider, gasPriceGwei, rates, subscriptionId, callbackGasLimit);
  if (chainlinkFunctionRequestCostInUSD == -1) {
    return new Map();
  }

  const offChainCostInUSD = offChainCallCostInUSD + chainlinkFunctionRequestCostInUSD;

  console.log(`On-chain solution cost: ${onChainCostInUSD} USD`);
  console.log(`Off-chain solution cost: ${offChainCostInUSD} USD`);

  return new Map([
    ["on", onChainCostInUSD],
    ["off", offChainCostInUSD],
  ]);
}

export async function estimate() {
  document.getElementById('estimateButton').disabled = true;
  displayProgress();

  var errors = [];

  const onChainCostOutput = document.getElementById('onChainCost');
  onChainCostOutput.textContent = '-';
  const offChainCostOutput = document.getElementById('offChainCost');
  offChainCostOutput.textContent = '-';

  const network = document.getElementById('networkDropdown').value;
  if (network.length == 0) {
    console.log('Network not selected');
    pushError(errors, 'networkDot');
  }

  const providerURL = document.getElementById('jsonRPCURL').value;
  var provider = null;
  try {
    new URL(providerURL);
    provider = new ethers.providers.JsonRpcProvider(providerURL);
    await provider.getNetwork();
  } catch (ex) {
    console.log('Could not initiate JSON RPC provider', ex);
    pushError(errors, 'networkDot');
  }

  var gasPriceGwei = document.getElementById('gasPriceGwei').value;
  if (gasPriceGwei.length > 0 && (isNaN(gasPriceGwei) || parseFloat(gasPriceGwei) <= 0)) {
    console.log('Gas price in gwei is not a number or is less than 0');
    pushError(errors, 'networkDot');
  } else {
    if (gasPriceGwei.length > 0) {
      gasPriceGwei = parseFloat(gasPriceGwei);
    } else {
      gasPriceGwei = -1;
    }
  }

  const onChainContractAddress = document.getElementById('onChainContractAddress').value;
  if (onChainContractAddress.length == 0) {
    console.log('Missing on chain contract address');
    pushError(errors, 'onChainContractDot');
  }

  const onChainContractCallerAddress = document.getElementById('onChainContractCallerAddress').value;
  if (onChainContractCallerAddress.length == 0) {
    console.log('Missing on chain contract function caller address');
    pushError(errors, 'onChainContractDot');
  }

  const onChainFunctionSignature = document.getElementById('onChainContractFunctionSignature').value;
  if (onChainFunctionSignature.length == 0 || onChainFunctionSignature.match(/.*\(.*\)/) == null) {
    console.log('Missing or invalid on chain function signature');
    pushError(errors, 'onChainContractDot');
  }

  const onChainInputData = document.getElementById('onChainContractFunctionInputData').value;
  const onChainTypesSignature = onChainFunctionSignature.match(/\(([^)]+)\)/);

  var encodedOnChainInputData = '';
  if (onChainTypesSignature != null) {
    const onChainTypes = onChainTypesSignature[1].split(",");
    try {
      const onChainArguments = JSON.parse(onChainInputData);
      encodedOnChainInputData = abiCoder.encode(onChainTypes, onChainArguments);
    } catch (ex) {
      console.log('Could not encode on chain function arguments', ex);
      if (errors.indexOf('onChainContractDot') === -1) {
        pushError(errors, 'onChainContractDot');
      }
    }
  }

  const offChainContractAddress = document.getElementById('offChainContractAddress').value;
  if (offChainContractAddress.length == 0) {
    console.log('Missing off chain contract address');
    pushError(errors, 'offChainContractDot');
  }

  const offChainContractCallerAddress = document.getElementById('offChainContractCallerAddress').value;
  if (offChainContractCallerAddress.length == 0) {
    console.log('Missing off chain contract function caller address');
    pushError(errors, 'offChainContractDot');
  }

  const offChainFunctionSignature = document.getElementById('offChainContractFunctionSignature').value;
  if (offChainFunctionSignature == 0 || offChainFunctionSignature.match(/.*\(.*\)/) == null) {
    console.log('Missing or invalid off chain function signature');
    pushError(errors, 'offChainContractDot');
  }

  const offChainInputData = document.getElementById('offChainContractFunctionInputData').value;
  const offChainTypesSignature = offChainFunctionSignature.match(/\(([^)]+)\)/);

  var encodedOffChainInputData = '';
  if (offChainTypesSignature != null) {
    const offChainTypes = offChainTypesSignature[1].split(",");
    try {
      const offChainArguments = JSON.parse(offChainInputData);
      encodedOffChainInputData = abiCoder.encode(offChainTypes, offChainArguments);
    } catch (ex) {
      console.log('Could not encode off chain function arguments', ex);
      if (errors.indexOf('offChainContractDot') === -1) {
        pushError(errors, 'offChainContractDot');
      }
    }
  }

  const subscriptionId = document.getElementById('subscriptionId').value;
  if (subscriptionId.length == 0) {
    console.log('Missing subscription ID');
    pushError(errors, 'offChainFunctionsDot');
  }

  const callbackGasLimit = document.getElementById('callbackGasLimit').value;
  if (callbackGasLimit.length == 0 || isNaN(callbackGasLimit) || parseInt(callbackGasLimit) < 1) {
    console.log('Callback gas limit is not a number or is less than 1');
    pushError(errors, 'offChainFunctionsDot');
  }

  if (errors.length > 0) {
    hideProgress();
    document.getElementById('estimateButton').disabled = false;
    displayValidationError(errors);
    return;
  }

  const costs = await estimateCosts(
    network,
    provider,
    gasPriceGwei,
    onChainContractAddress,
    onChainContractCallerAddress,
    onChainFunctionSignature,
    encodedOnChainInputData,
    offChainContractAddress,
    offChainContractCallerAddress,
    offChainFunctionSignature,
    encodedOffChainInputData,
    subscriptionId,
    parseInt(callbackGasLimit)
  );

  if (costs.size == 0) {
    hideProgress();
    document.getElementById('estimateButton').disabled = false;
    displayError('An error occurred! See console for logs');
    return;
  }

  const onChainCost = costs.get('on');
  onChainCostOutput.textContent = `${(Math.round(onChainCost * 100) / 100).toFixed(2)}`;

  const offChainCost = costs.get('off');
  offChainCostOutput.textContent = `${(Math.round(offChainCost * 100) / 100).toFixed(2)}`;

  hideProgress();
  document.getElementById('estimateButton').disabled = false;
  displaySuccess();
}

function saveInput(event) {
  const fieldId = event.target.id;
  const value = event.target.value;
  localStorage.setItem(fieldId, value);
}

function attachInputListeners() {
  const fields = [
    'jsonRPCURL',
    'networkDropdown',
    'onChainContractAddress',
    'onChainContractCallerAddress',
    'onChainContractFunctionSignature',
    'onChainContractFunctionInputData',
    'offChainContractAddress',
    'offChainContractCallerAddress',
    'offChainContractFunctionSignature',
    'offChainContractFunctionInputData',
    'subscriptionId',
    'callbackGasLimit'
  ];

  fields.forEach(field => {
    const element = document.getElementById(field);
    if (element) {
      element.addEventListener('input', saveInput);
    }
  });
}

function setDefaults() {
  const fields = [
    'jsonRPCURL',
    'networkDropdown',
    'onChainContractAddress',
    'onChainContractCallerAddress',
    'onChainContractFunctionSignature',
    'onChainContractFunctionInputData',
    'offChainContractAddress',
    'offChainContractCallerAddress',
    'offChainContractFunctionSignature',
    'offChainContractFunctionInputData',
    'subscriptionId',
    'callbackGasLimit'
  ];

  fields.forEach(field => {
    const savedValue = localStorage.getItem(field);
    if (savedValue) {
      document.getElementById(field).value = savedValue;
    }
  });
}

let slideIndex = 1;
showSlide(slideIndex);

export function currentSlide(n) {
  showSlide(slideIndex = n);
}

function showSlide(n) {
  let i;
  let slides = document.getElementsByClassName("slide");
  let dots = document.getElementsByClassName("dot");
  if (n > slides.length) { slideIndex = 1 }
  if (n < 1) { slideIndex = slides.length }
  for (i = 0; i < slides.length; i++) {
    slides[i].style.display = "none";
  }
  for (i = 0; i < dots.length; i++) {
    dots[i].className = dots[i].className.replace(" active", "");
  }
  slides[slideIndex - 1].style.display = "block";
  dots[slideIndex - 1].className += " active";
}

function displayProgress() {
  const success = document.getElementById('progressAlert');
  success.style.display = "block";
}

function hideProgress() {
  const success = document.getElementById('progressAlert');
  success.style.display = "none";
}

function displayError(message) {
  const error = document.getElementById('errorAlert');
  error.textContent = message;
  error.style.display = "block";
  setTimeout(() => {
    error.style.display = "none";
    error.textContent = '';
  }, 5000);
}

function displaySuccess() {
  const success = document.getElementById('successAlert');
  success.style.display = "block";
  setTimeout(() => {
    success.style.display = "none";
  }, 5000);
}

function displayValidationError(dots) {
  dots.forEach(dot => {
    const errorDot = document.getElementById(dot);
    errorDot.className += " invalid";
    setTimeout(() => {
      errorDot.className = errorDot.className.replace(" invalid", "");
    }, 5000);
  });

  displayError('Invalid inputs, check console for logs');
}

function pushError(errors, slide) {
  if (errors.indexOf(slide) === -1) {
    errors.push(slide);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const dots = document.getElementsByClassName('dot');
  for (let dot of dots) {
    if (dot) {
      dot.addEventListener('click', () => {
        currentSlide(dot.dataset.slide);
      });
    }
  }

  const estimateButton = document.getElementById('estimateButton');
  if (estimateButton) {
    estimateButton.addEventListener('click', () => {
      estimate();
    });
  }
});

window.onload = function () {
  setDefaults();
  attachInputListeners();
}
