// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import '../library/types.sol';


interface IOrderlyDex {
    struct PerpPosition {
        int position_qty;
        int cost_position;
        int last_sum_unitary_fundings;
        uint last_executed_price;
    }

    struct Account {
        // user's balance
        uint balance;
        // last perp trade id
        uint last_perp_trade_id;
        // last cefi event id
        uint last_cefi_event_id;
        // perp position
        PerpPosition perp_position;
    }

    function update_user_ledger_by_trade_upload(Types.FuturesTradeUpLoad calldata trade) external;    
}