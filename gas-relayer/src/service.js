const EventEmitter = require('events');
const Web3 = require('web3');
const config = require('../config/config.js');
const ContractSettings = require('./contract-settings');
const MessageProcessor = require('./message-processor');

// IDEA: A node should call an API (probably from a status node) to register itself as a 
//      token gas relayer.

console.info("Starting...");
const events = new EventEmitter();

// Web3 Connection
let connectionURL = `${config.node.local.protocol}://${config.node.local.host}:${config.node.local.port}`;
const web3 = new Web3(connectionURL);

web3.eth.net.isListening()
.then(() => events.emit('web3:connected', connectionURL))
.catch(error => {
  console.error(error);
  process.exit();
});


events.on('web3:connected', connURL => {
  console.info("Connected to '%s'", connURL);
  let settings = new ContractSettings(config, web3, events);
  settings.process();
});

// Setting up Whisper options
const shhOptions = {
  ttl: config.node.whisper.ttl,
  minPow: config.node.whisper.minPow
};

const verifyBalance = async (exitSubs) => {
  const nodeBalance = await web3.eth.getBalance(config.node.blockchain.account);
  if(web3.utils.toBN(nodeBalance).lte(web3.utils.toBN(100000))){ // TODO: tune minimum amount required for transactions
    console.log("Not enough balance available for processing transactions");
    console.log("> Account: %s", config.node.blockchain.account);
    console.log("> Balance: %s", nodeBalance);

    if(exitSubs){
      web3.shh.clearSubscriptions();
    }

    process.exit(0);
  }
};

events.on('exit', () => {
  web3.shh.clearSubscriptions();
  console.log("Closing service...");
  process.exit(0);
});

events.on('setup:complete', async (settings) => {
  // Verifying relayer balance
  await verifyBalance();

  shhOptions.kId = await web3.shh.newKeyPair();

  const symKeyID = await web3.shh.addSymKey(config.node.whisper.symKey);
  const pubKey = await web3.shh.getPublicKey(shhOptions.kId);

  // Listening to whisper
  // Individual subscriptions due to https://github.com/ethereum/web3.js/issues/1361
  // once this is fixed, we'll be able to use an array of topics and a single subs for symkey and a single subs for privKey
  console.info(`Sym Key: ${config.node.whisper.symKey}`);
  console.info(`Relayer Public Key: ${pubKey}`);
  console.info("Topics Available:");
  for(let contract in settings.contracts) {
    console.info("- %s: %s [%s]", settings.getContractByTopic(contract).name, contract,  Object.keys(settings.getContractByTopic(contract).allowedFunctions).join(', '));
    shhOptions.topics = [contract];

    // Listen to public channel - Used for reporting availability
    events.emit('server:listen', Object.assign({symKeyID}, shhOptions), settings);

    // Listen to private channel - Individual transactions
    events.emit('server:listen', Object.assign({privateKeyID: shhOptions.kId}, shhOptions), settings);
  }
});

const replyFunction = (message) => (text, receipt) => {
  if(message.sig !== undefined){
      console.log(text);
      web3.shh.post({ 
          pubKey: message.sig, 
          sig: shhOptions.kId,
          ttl: config.node.whisper.ttl, 
          powTarget:config.node.whisper.minPow, 
          powTime: config.node.whisper.powTime, 
          topic: message.topic, 
          payload: web3.utils.fromAscii(JSON.stringify({message:text, receipt}, null, " "))
      }).catch(console.error);
  }
};

const extractInput = (message) => {
    let obj = {
        contract: null,
        address: null,
        action: null
    };

    try {
        const msg = web3.utils.toAscii(message.payload);
        let parsedObj = JSON.parse(msg);
        obj.contract = parsedObj.contract;
        obj.address = parsedObj.address;
        obj.action = parsedObj.action;
        if(obj.action == 'transaction'){
          obj.functionName = parsedObj.encodedFunctionCall.slice(0, 10);
          obj.functionParameters = "0x" + parsedObj.encodedFunctionCall.slice(10);
          obj.payload = parsedObj.encodedFunctionCall;
        } else if(obj.action == 'availability') {
          obj.token = parsedObj.token;
          obj.gasPrice = parsedObj.gasPrice;
        }
    } catch(err){
        console.error("Couldn't parse " + message);
    }
    
    return obj;
};


events.on('server:listen', (shhOptions, settings) => {
  let processor = new MessageProcessor(config, settings, web3, events);
  web3.shh.subscribe('messages', shhOptions, (error, message) => {
    if(error){
      console.error(error);
      return;
    }

    verifyBalance(true);

    const input = extractInput(message);
    const reply = replyFunction(message);
    
    switch(input.action){
      case 'transaction':
        processor.process(settings.getContractByTopic(message.topic), 
                      input, 
                      reply);
        break;
      case 'availability':
        reply("available");
        break;
      default: 
        reply("unknown-action");        
    }

    
  });
});

// Daemon helper functions

process.on("uncaughtException", function(err) {
  // TODO
  console.error(err);  
});

process.once("SIGTERM", function() {
  console.log("Stopping...");
});
