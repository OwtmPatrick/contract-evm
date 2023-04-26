// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import './interface/IOrderlyDex.sol';
import './library/signature.sol';
import './library/types.sol';

/**
 * OperatorManager is responsible for executing cefi tx, only called by operator.
 * This contract should only have one in main-chain (avalanche)
 */
contract OperatorManager {
    // operator address
    address public operator;
    IOrderlyDex public orderly_dex;

    // ids
    // futures_upload_batch_id
    uint public futures_upload_batch_id;
    // event_upload_batch_id
    uint public event_upload_batch_id;

    // only operator
    modifier only_operator() {
        require(msg.sender == operator, "only operator can call");
        _;
    }

    // constructor
    constructor(address _operator) {
        futures_upload_batch_id = 0;
        operator = _operator;
    }

    // entry point for operator to call this contract
    function operator_execute_action(
        Types.OperatorActionData action_data,
        bytes calldata action
    ) public only_operator {
        if (action_data == Types.OperatorActionData.FuturesTradeUpload) {
            // FuturesTradeUpload
            futures_trade_upload_data(abi.decode(action, (Types.FuturesTradeUploadData)));
        } else if (action_data == Types.OperatorActionData.EventUpload) {
            // EventUpload
            // TODO
        } else {
            revert("invalid action_data");
        }
        
    }

    // futures trade upload data
    function futures_trade_upload_data(
        Types.FuturesTradeUploadData calldata data
    ) internal {
        require(data.batch_id == futures_upload_batch_id, "batch_id not match");
        Types.FuturesTradeUpLoad[] memory trades = data.trades; // gas saving
        require(trades.length == data.count, "count not match");
        _validate_perp(trades);
        // process each validated perp trades
        for (uint i = 0; i < data.count; i++) {
            _process_validated_futures(trades[i]);
        }
        // update_futures_upload_batch_id
        // TODO use math safe add
        futures_upload_batch_id += 1;
    }

    // validate futres trade upload data
    function _validate_perp(
        Types.FuturesTradeUpLoad[] calldata trades
    ) internal pure {
        for (uint i = 0; i < trades.length; i++) {
            // first, check signature is valid
            _verify_signature(trades[i]);
            // second, check symbol (and maybe other value) is valid
            // TODO  
        }
    }

    function _verify_signature(
        Types.FuturesTradeUpLoad calldata trade
    ) internal pure {
        // TODO ensure the parameters satisfy the real signature
        bytes32 sig = keccak256(abi.encodePacked(
            trade.trade_id,
            trade.symbol,
            trade.side,
            trade.trade_qty
        ));
    
        require(
            Signature.verify(
                Signature.getEthSignedMessageHash(sig),
                trade.signature,
                trade.account_id
            ),
            "invalid signature"
        );
    }

    // process each validated perp trades
    function _process_validated_futures(
        Types.FuturesTradeUpLoad calldata trade
    ) internal {
        orderly_dex.update_user_ledger_by_trade_upload(trade); 
    }

    // event upload data
    function event_upload_data(
        Types.EventUpload calldata data
    ) internal {
        require(data.batch_id == event_upload_batch_id, "batch_id not match");
        Types.EventUploadData[] memory events = data.events; // gas saving
        require(events.length == data.count, "count not match");
        require(events.sequence.length == data.count, "count not match");
        // process each event upload
        for (uint i = 0; i < data.count; i++) {
            _process_event_upload(events[i]);
        }
        // update_event_upload_batch_id
        // TODO use math safe add
        event_upload_batch_id += 1;
    }

    // process each event upload
    function _process_event_upload(
        Types.EventUploadData calldata data
    ) internal {
        uint index_withdraw = 0;
        uint index_settlement = 0;
        uint index_liquidation = 0;
        // iterate sequence to process each event. The sequence decides the event type.
        for (uint i = 0; i < data.sequence.length; i++) {
            if (data.sequence[i] == 0) {
                // withdraw
                // orderly_dex.execute_withdraw_action(data.withdraws[index_withdraw]);
                index_withdraw += 1;
            } else if (data.sequence[i] == 1) {
                // settlement
                orderly_dex.execute_settlement(data.settlements[index_settlement], data.event_id);
                index_settlement += 1;
            } else if (data.sequence[i] == 2) {
                // liquidation
                orderly_dex.execute_liquidation(data.liquidations[index_liquidation], data.event_id);
                index_liquidation += 1;
            } else {
                revert("invalid sequence");
            }
        }
    }
}