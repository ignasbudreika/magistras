const infuraNodeUrl = 'https://sepolia.infura.io/v3/'; const infuraApiKey = secrets.INFURA_API_KEY; const contractAddress = args[0]; const functionSelector = '0xcbba959b';
let values = []; let weights = []; let maxWeight = parseInt(args[1]);
function encodeUint256Arg(value) { let hex = BigInt(value).toString(16); return hex.padStart(64, '0'); }
let page = 0; const pageSize = 100; const pageSizeEncoded = encodeUint256Arg(pageSize);
while (true) {
    const requestData = functionSelector + encodeUint256Arg(page) + pageSizeEncoded;
    const request = Functions.makeHttpRequest({ url: infuraNodeUrl + infuraApiKey, method: 'POST', headers: { 'Content-Type': 'application/json' }, data: { jsonrpc: '2.0', method: 'eth_call', params: [{ to: contractAddress, data: requestData }, 'latest'], id: 1 } });
    const response = await request;
    if (response.error) { console.error(response.error); throw Error('Elements fetch failed') }
    let resultData = response.data.result.slice(2);
    let valuesOffset = parseInt(resultData.slice(0, 64), 16); const valuesLen = parseInt(resultData.slice(valuesOffset * 2, valuesOffset * 2 + 64), 16); let valuesDataOffset = valuesOffset * 2 + 64;
    for (let i = 0; i < valuesLen; i++) { const value = parseInt(resultData.slice(valuesDataOffset + i * 64, valuesDataOffset + (i + 1) * 64), 16); values.push(value); }
    let weightsOffset = parseInt(resultData.slice(64, 128), 16); const weightsLen = parseInt(resultData.slice(weightsOffset * 2, weightsOffset * 2 + 64), 16); let weightsDataOffset = weightsOffset * 2 + 64;
    for (let i = 0; i < weightsLen; i++) { const value = parseInt(resultData.slice(weightsDataOffset + i * 64, weightsDataOffset + (i + 1) * 64), 16); weights.push(value); }
    if (valuesLen < pageSize) { break; } else { page++; }
}
let maxValues = []; for (var i = 0; i < maxWeight + 1; ++i) { maxValues[i] = 0; }
for (let i = 0; i < values.length; i++) {
    for (let weight = maxWeight; weight >= 0; weight--) {
        if (weights[i] <= weight) {
            if (maxValues[weight - weights[i]] + values[i] > maxValues[weight]) {
                maxValues[weight] = maxValues[weight - weights[i]] + values[i];
            }
        }
    }
}
return Functions.encodeUint256(maxValues[maxWeight]);
