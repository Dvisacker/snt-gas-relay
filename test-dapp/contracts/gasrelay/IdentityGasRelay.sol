pragma solidity ^0.5.0;

import "./GasRelay.sol";
import "../identity/Identity.sol";
import "../token/ERC20Token.sol";

/**
 * @title IdentityGasRelay
 * @author Ricardo Guilherme Schmidt (Status Research & Development GmbH) 
 * @notice enables economic abstraction for Identity
 */
contract IdentityGasRelay is Identity, GasRelay {
    
    constructor(   
        bytes32[] _keys,
        uint256[] _purposes,
        uint256[] _types,           
        uint256 _managerThreshold,
        uint256 _actorThreshold,
        address _recoveryContract
    ) 
        Identity(
            _keys,
            _purposes,
            _types,
            _managerThreshold,
            _actorThreshold,
            _recoveryContract
        ) 
        public
    {

    }

    /**
     * @notice include ethereum signed callHash in return of gas proportional amount multiplied by `_gasPrice` of `_gasToken`
     *         allows identity of being controlled without requiring ether in key balace
     * @param _to destination of call
     * @param _value call value (ether)
     * @param _data call data
     * @param _nonce current identity nonce
     * @param _gasPrice price in SNT paid back to msg.sender for each gas unit used
     * @param _gasLimit maximum gas of this transacton
     * @param _gasToken token being used for paying `msg.sender`
     * @param _messageSignatures rsv concatenated ethereum signed message signatures required
     */
    function callGasRelayed(
        address _to,
        uint256 _value,
        bytes _data,
        uint _nonce,
        uint _gasPrice,
        uint _gasLimit,
        address _gasToken, 
        bytes _messageSignatures
    ) 
        external 
        returns (bool success)
    {
        
        //query current gas available
        uint startGas = gasleft(); 
        
        //verify transaction parameters
        require(startGas >= _gasLimit, ERR_BAD_START_GAS); 
        require(_nonce == nonce, ERR_BAD_NONCE);
        
        //verify if signatures are valid and came from correct actors;
        verifySignatures(
            _to == address(this) ? MANAGEMENT_KEY : ACTION_KEY,
            callGasRelayHash(
                _to,
                _value,
                keccak256(_data),
                _nonce,
                _gasPrice,
                _gasLimit,
                _gasToken                
            ), 
            _messageSignatures
        );
        
        //increase nonce
        nonce++;
        
        //executes transaction
        success = _commitCall(_nonce, _to, _value, _data);

        //refund gas used using contract held ERC20 tokens or ETH
        if (_gasPrice > 0) {
            uint256 _amount = 21000 + (startGas - gasleft());
            require(_amount <= _gasLimit, ERR_GAS_LIMIT_EXCEEDED);
            _amount = _amount * _gasPrice;
            if (_gasToken == address(0)) {
                address(msg.sender).transfer(_amount);
            } else {
                ERC20Token(_gasToken).transfer(msg.sender, _amount);
            }
        }
        
    }

    /**
     * @notice deploys contract in return of gas proportional amount multiplied by `_gasPrice` of `_gasToken`
     *         allows identity of being controlled without requiring ether in key balace
     * @param _value call value (ether) to be sent to newly created contract
     * @param _data contract code data
     * @param _nonce current identity nonce
     * @param _gasPrice price in SNT paid back to msg.sender for each gas unit used
     * @param _gasLimit maximum gas of this transacton
     * @param _gasToken token being used for paying `msg.sender`
     * @param _messageSignatures rsv concatenated ethereum signed message signatures required
     */
    function deployGasRelayed(
        uint256 _value, 
        bytes _data,
        uint _nonce,
        uint _gasPrice,
        uint _gasLimit,
        address _gasToken, 
        bytes _messageSignatures
    ) 
        external 
        returns(address deployedAddress)
    {
        //query current gas available
        uint startGas = gasleft(); 
        
        //verify transaction parameters
        require(startGas >= _gasLimit, ERR_BAD_START_GAS); 
        require(_nonce == nonce, ERR_BAD_NONCE);
        
        //verify if signatures are valid and came from correct actors;
        verifySignatures(
            ACTION_KEY,
            deployGasRelayHash(
                _value,
                keccak256(_data),
                _nonce,
                _gasPrice,
                _gasLimit,
                _gasToken                
            ), 
            _messageSignatures
        );
        
        //increase nonce
        nonce++;

        deployedAddress = doCreate(_value, _data);
        emit ContractDeployed(deployedAddress); 

        //refund gas used using contract held ERC20 tokens or ETH
        if (_gasPrice > 0) {
            uint256 _amount = 21000 + (startGas - gasleft());
            require(_amount <= _gasLimit, ERR_GAS_LIMIT_EXCEEDED);
            _amount = _amount * _gasPrice;
            if (_gasToken == address(0)) {
                address(msg.sender).transfer(_amount);
            } else {
                ERC20Token(_gasToken).transfer(msg.sender, _amount);
            }
        }       
    }


    /**
     * @notice include ethereum signed approve ERC20 and call hash 
     *         (`ERC20Token(baseToken).approve(_to, _value)` + `_to.call(_data)`).
     *         in return of gas proportional amount multiplied by `_gasPrice` of `_gasToken`
     *         fixes race condition in double transaction for ERC20.
     * @param _baseToken token approved for `_to` and token being used for paying `msg.sender`
     * @param _to destination of call
     * @param _value call value (in `_baseToken`)
     * @param _data call data
     * @param _nonce current identity nonce
     * @param _gasPrice price in SNT paid back to msg.sender for each gas unit used
     * @param _gasLimit maximum gas of this transacton
     * @param _messageSignatures rsv concatenated ethereum signed message signatures required
     */
    function approveAndCallGasRelayed(
        address _baseToken, 
        address _to,
        uint256 _value,
        bytes _data,
        uint _nonce,
        uint _gasPrice,
        uint _gasLimit,
        bytes _messageSignatures
    ) 
        external 
        returns(bool success)
    {
                        
        //query current gas available
        uint startGas = gasleft(); 
        
        //verify transaction parameters
        require(startGas >= _gasLimit, ERR_BAD_START_GAS); 
        require(_nonce == nonce, ERR_BAD_NONCE);
        
        //verify if signatures are valid and came from correct actors;
        verifySignatures(
            ACTION_KEY,
            approveAndCallGasRelayHash(
                _baseToken,
                _to,
                _value,
                keccak256(_data),
                _nonce,
                _gasPrice,
                _gasLimit
            ), 
            _messageSignatures
        );
        
        //increase nonce
        nonce++;
        
        require(_baseToken != address(0), ERR_BAD_TOKEN_ADDRESS); //_baseToken should be something!
        require(_to != address(0) && _to != address(this), ERR_BAD_DESTINATION); //need valid destination
        ERC20Token(_baseToken).approve(_to, _value);
        success = _commitCall(_nonce, _to, 0, _data); 

        //refund gas used using contract held _baseToken
        if (_gasPrice > 0) {
            uint256 _amount = 21000 + (startGas - gasleft());
            require(_amount <= _gasLimit, ERR_GAS_LIMIT_EXCEEDED); 
            ERC20Token(_baseToken).transfer(msg.sender, _amount * _gasPrice);
        }
    }

    /**
     * @notice reverts if signatures are not valid for the signed hash and required key type. 
     * @param _requiredKey key required to call, if _to from payload is the identity itself, is `MANAGEMENT_KEY`, else `ACTION_KEY`
     * @param _messageHash message hash provided for the payload
     * @param _messageSignatures ethereum signed `getSignHash(_messageHash)` message
     * @return true case valid
     */    
    function verifySignatures(
        uint256 _requiredKey,
        bytes32 _messageHash,
        bytes _messageSignatures
    ) 
        public
        view
        returns(bool)
    {
        // calculates signHash
        bytes32 signHash = getSignHash(_messageHash);
        uint _amountSignatures = _messageSignatures.length / 65;
        require(_amountSignatures == purposeThreshold[_requiredKey], "Too few signatures");
        bytes32 _lastKey = 0;
        for (uint256 i = 0; i < _amountSignatures; i++) {
            bytes32 _currentKey = recoverKey(
                signHash,
                _messageSignatures,
                i
                );
            require(_currentKey > _lastKey, "Bad signatures order"); //assert keys are different
            require(keyHasPurpose(_currentKey, _requiredKey), ERR_BAD_SIGNER);
            _lastKey = _currentKey;
        }
        return true;
    }

    /**
     * @notice recovers key who signed the message 
     * @param _signHash operation ethereum signed message hash
     * @param _messageSignature message `_signHash` signature
     * @param _pos which signature to read
     */
    function recoverKey(
        bytes32 _signHash, 
        bytes _messageSignature,
        uint256 _pos
    )
        public
        pure
        returns(bytes32) 
    {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v,r,s) = signatureSplit(_messageSignature, _pos);
        return keccak256(
            abi.encodePacked(
                ecrecover(
                    _signHash,
                    v,
                    r,
                    s
                )
            )
        );
    }

    /**
     * @dev divides bytes signature into `uint8 v, bytes32 r, bytes32 s`
     * @param _pos which signature to read
     * @param _signatures concatenated vrs signatures
     */
    function signatureSplit(bytes _signatures, uint256 _pos)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint pos = _pos + 1;
        // The signature format is a compact form of:
        //   {bytes32 r}{bytes32 s}{uint8 v}
        // Compact means, uint8 is not padded to 32 bytes.
        assembly {
            r := mload(add(_signatures, mul(32,pos)))
            s := mload(add(_signatures, mul(64,pos)))
            // Here we are loading the last 32 bytes, including 31 bytes
            // of 's'. There is no 'mload8' to do this.
            //
            // 'byte' is not working due to the Solidity parser, so lets
            // use the second best option, 'and'
            v := and(mload(add(_signatures, mul(65,pos))), 0xff)
        }

        require(v == 27 || v == 28, "Bad signature");
    }

    /**
     * @notice creates new contract based on input `_code` and transfer `_value` ETH to this instance
     * @param _value amount ether in wei to sent to deployed address at its initialization
     * @param _code contract code
     */
    function doCreate(
        uint _value,
        bytes _code
    ) 
        internal 
        returns (address createdContract) 
    {
        assembly {
            createdContract := create(_value, add(_code, 0x20), mload(_code))
        }
        /* 
        //enabling this would prevent gas relayers from executing failed calls
        //however would insert this identity to gas relayer blocklist when this happens
        bool failed;
        assembly {
            failed := iszero(extcodesize(createdContract))
        }
        require(!failed); 
        */
    }

}