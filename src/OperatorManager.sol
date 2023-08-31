// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "./dataLayout/OperatorManagerDataLayout.sol";
import "./interface/ILedger.sol";
import "./interface/IMarketManager.sol";
import "./interface/IOperatorManager.sol";
import "./library/Signature.sol";

/**
 * OperatorManager is responsible for executing cefi tx, only called by operator.
 * This contract should only have one in main-chain
 */
contract OperatorManager is IOperatorManager, OwnableUpgradeable, OperatorManagerDataLayout {
    // only operator
    modifier onlyOperator() {
        if (msg.sender != operatorAddress) revert OnlyOperatorCanCall();
        _;
    }

    // set operator
    function setOperator(address _operatorAddress) public override onlyOwner {
        operatorAddress = _operatorAddress;
    }

    // set cefi sign address
    function setCefiSpotTradeUploadAddress(address _cefiSpotTradeUploadAddress) public override onlyOwner {
        cefiSpotTradeUploadAddress = _cefiSpotTradeUploadAddress;
    }

    function setCefiPerpTradeUploadAddress(address _cefiPerpTradeUploadAddress) public override onlyOwner {
        cefiPerpTradeUploadAddress = _cefiPerpTradeUploadAddress;
    }

    function setCefiEventUploadAddress(address _cefiEventUploadAddress) public override onlyOwner {
        cefiEventUploadAddress = _cefiEventUploadAddress;
    }

    function setCefiMarketUploadAddress(address _cefiMarketUploadAddress) public override onlyOwner {
        cefiMarketUploadAddress = _cefiMarketUploadAddress;
    }

    // set ledger
    function setLedger(address _ledger) public override onlyOwner {
        ledger = ILedger(_ledger);
    }

    function setMarketManager(address _marketManagerAddress) public override onlyOwner {
        marketManager = IMarketManager(_marketManagerAddress);
    }

    constructor() {
        _disableInitializers();
    }

    function initialize() public override initializer {
        __Ownable_init();
        futuresUploadBatchId = 1;
        eventUploadBatchId = 1;
        lastOperatorInteraction = block.timestamp;
        // init all cefi sign address
        // https://wootraders.atlassian.net/wiki/spaces/ORDER/pages/315785217/Orderly+V2+Keys+Smart+Contract
        cefiSpotTradeUploadAddress = 0x54c8D36aBE8dd1B32a70fCe6c9afFE470b208601;
        cefiPerpTradeUploadAddress = 0x4d26aE249503716b6e7540f04434D9F0e54F87A7;
        cefiEventUploadAddress = 0x475a5dA10eb6dE8A18Bd4c1131Ab90a78b19b915;
        cefiMarketUploadAddress = 0x5E045a8bE39572Ce02cF076B35750034Cd9a431D;
        operatorAddress = 0x2d4e9C592b9f42557DAE7B103F3fCA47448DC0BD;
    }

    // operator ping
    function operatorPing() public onlyOperator {
        _innerPing();
    }

    // futuresTradeUpload
    function futuresTradeUpload(PerpTypes.FuturesTradeUploadData calldata data) public override onlyOperator {
        if (data.batchId != futuresUploadBatchId) revert BatchIdNotMatch(data.batchId, futuresUploadBatchId);
        _innerPing();
        _futuresTradeUploadData(data);
        // emit event
        emit FuturesTradeUpload(data.batchId, block.timestamp);
        // next wanted futuresUploadBatchId
        futuresUploadBatchId += 1;
    }

    // eventUpload
    function eventUpload(EventTypes.EventUpload calldata data) public override onlyOperator {
        if (data.batchId != eventUploadBatchId) revert BatchIdNotMatch(data.batchId, eventUploadBatchId);
        _innerPing();
        _eventUploadData(data);
        // emit event
        emit EventUpload(data.batchId, block.timestamp);
        // next wanted eventUploadBatchId
        eventUploadBatchId += 1;
    }

    // PerpMarketInfo
    function perpPriceUpload(MarketTypes.UploadPerpPrice calldata data) public override onlyOperator {
        _innerPing();
        _perpMarketInfo(data);
    }

    function sumUnitaryFundingsUpload(MarketTypes.UploadSumUnitaryFundings calldata data)
        public
        override
        onlyOperator
    {
        _innerPing();
        _perpMarketInfo(data);
    }

    // futures trade upload data
    function _futuresTradeUploadData(PerpTypes.FuturesTradeUploadData calldata data) internal {
        PerpTypes.FuturesTradeUpload[] calldata trades = data.trades;
        if (trades.length != data.count) revert CountNotMatch(trades.length, data.count);

        // check cefi signature
        bool succ = Signature.perpUploadEncodeHashVerify(data, cefiPerpTradeUploadAddress);
        if (!succ) revert SignatureNotMatch();

        // process each validated perp trades
        for (uint256 i = 0; i < data.count; i++) {
            _processValidatedFutures(trades[i]);
        }
    }

    // process each validated perp trades
    function _processValidatedFutures(PerpTypes.FuturesTradeUpload calldata trade) internal {
        ledger.executeProcessValidatedFutures(trade);
    }

    // event upload data
    function _eventUploadData(EventTypes.EventUpload calldata data) internal {
        EventTypes.EventUploadData[] calldata events = data.events; // gas saving
        if (events.length != data.count) revert CountNotMatch(events.length, data.count);

        // check cefi signature
        bool succ = Signature.eventsUploadEncodeHashVerify(data, cefiEventUploadAddress);
        if (!succ) revert SignatureNotMatch();

        // process each event upload
        for (uint256 i = 0; i < data.count; i++) {
            _processEventUpload(events[i]);
        }
    }

    // process each event upload
    function _processEventUpload(EventTypes.EventUploadData calldata data) internal {
        uint8 bizType = data.bizType;
        if (bizType == 1) {
            // withdraw
            ledger.executeWithdrawAction(abi.decode(data.data, (EventTypes.WithdrawData)), data.eventId);
        } else if (bizType == 2) {
            // settlement
            ledger.executeSettlement(abi.decode(data.data, (EventTypes.Settlement)), data.eventId);
        } else if (bizType == 3) {
            // adl
            ledger.executeAdl(abi.decode(data.data, (EventTypes.Adl)), data.eventId);
        } else if (bizType == 4) {
            // liquidation
            ledger.executeLiquidation(abi.decode(data.data, (EventTypes.Liquidation)), data.eventId);
        } else {
            revert InvalidBizType(bizType);
        }
    }

    // perp market info
    function _perpMarketInfo(MarketTypes.UploadPerpPrice calldata data) internal {
        // check cefi signature
        bool succ = Signature.marketUploadEncodeHashVerify(data, cefiMarketUploadAddress);
        if (!succ) revert SignatureNotMatch();
        // process perp market info
        marketManager.updateMarketUpload(data);
    }

    function _perpMarketInfo(MarketTypes.UploadSumUnitaryFundings calldata data) internal {
        // check cefi signature
        bool succ = Signature.marketUploadEncodeHashVerify(data, cefiMarketUploadAddress);
        if (!succ) revert SignatureNotMatch();
        // process perp market info
        marketManager.updateMarketUpload(data);
    }

    function _innerPing() internal {
        lastOperatorInteraction = block.timestamp;
    }

    function checkCefiDown() public view override returns (bool) {
        return (lastOperatorInteraction + 3 days < block.timestamp);
    }
}
