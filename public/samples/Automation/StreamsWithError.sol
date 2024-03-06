// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StreamsLookupCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/StreamsLookupCompatibleInterface.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {IRewardManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IRewardManager.sol";
import {IVerifierFeeManager} from "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/interfaces/IERC20.sol";
import {Common} from "@chainlink/contracts/src/v0.8/libraries/Common.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

//////////////////////////////////
////////////////////////INTERFACES
//////////////////////////////////

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFeeManager {
    function getFeeAndReward(
        address subscriber,
        bytes memory report,
        address quoteAddress
    )
        external
        returns (
            ChainlinkCommon.Asset memory,
            ChainlinkCommon.Asset memory,
            uint256
        );

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

library ChainlinkCommon {
    // @notice The asset struct to hold the address of an asset and amount
    struct Asset {
        address assetAddress;
        uint256 amount;
    }

    // @notice Struct to hold the address and its associated weight
    struct AddressAndWeight {
        address addr;
        uint64 weight;
    }
}

interface IVerifierProxy {
    function verify(
        bytes calldata payload,
        bytes calldata parameterPayload
    ) external payable returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (IVerifierFeeManager);
}

interface IReportHandler {
    function handleReport(bytes calldata report) external;
}

interface IVerifierFeeManager {}

interface IRewardManager {}

//////////////////////////////////
///////////////////END INTERFACES
//////////////////////////////////

contract StreamsLookupChainlinkAutomation is
    ILogAutomation,
    StreamsLookupCompatibleInterface
{
    struct BasicReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 18 decimal places
    }

    struct PremiumReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 18 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    struct Quote {
        address quoteAddress;
    }

    event PriceUpdate(int192 indexed price);

    IVerifierProxy public verifier;

    address public FEE_ADDRESS;
    string public constant STRING_DATASTREAMS_FEEDLABEL = "feedIDs";
    string public constant STRING_DATASTREAMS_QUERYLABEL = "timestamp";
    string[] public feedIds = [
        "0x00027bbaff688c906a3e20a34fe951715d1018d262a5b66e38eda027a674cd1b" // Ex. Basic ETH/USD price report
    ];

    constructor(address _verifier) {
        verifier = IVerifierProxy(_verifier); //Arbitrum Sepolia: 0x2ff010debc1297f19579b4246cad07bd24f2488a
    }

    function checkLog(
        Log calldata log,
        bytes memory
    ) external returns (bool upkeepNeeded, bytes memory performData) {
        revert StreamsLookup(
            STRING_DATASTREAMS_FEEDLABEL,
            feedIds,
            STRING_DATASTREAMS_QUERYLABEL,
            log.timestamp,
            ""
        );
    }

    function checkCallback(
        bytes[] calldata values,
        bytes calldata extraData
    ) external pure returns (bool, bytes memory) {
        bool success = true;
        return (true, abi.encode(values, extraData, success));
    }

    function checkErrorHandler(
        bytes calldata errorCode,
        bytes calldata extraData
    ) public view returns (bool upkeepNeeded, bytes memory performData) {
        bool success = false;
        return (true, abi.encode(errorCode, extraData, success));
    }

    // function will be performed on-chain
    function performUpkeep(bytes calldata performData) external {
        // Decode incoming performData
        (
            bytes[] memory signedReports,
            bytes memory extraData,
            bool reportSuccess
        ) = abi.decode(performData, (bytes[], bytes, bool));

        if (reportSuccess) {
            bytes memory report = signedReports[0];

            (, bytes memory reportData) = abi.decode(
                report,
                (bytes32[3], bytes)
            );

            // Billing

            IFeeManager feeManager = IFeeManager(
                address(verifier.s_feeManager())
            );
            IRewardManager rewardManager = IRewardManager(
                address(feeManager.i_rewardManager())
            );

            address feeTokenAddress = feeManager.i_linkAddress();
            (ChainlinkCommon.Asset memory fee, , ) = feeManager.getFeeAndReward(
                address(this),
                reportData,
                feeTokenAddress
            );

            IERC20(feeTokenAddress).approve(address(rewardManager), fee.amount);

            // Verify the report
            bytes memory verifiedReportData = verifier.verify(
                report,
                abi.encode(feeTokenAddress)
            );

            /*
        Deprecated Interface:
        bytes memory verifiedReportData = verifier.verify(bundledReport);
        */

            // Decode verified report data into BasicReport struct
            BasicReport memory verifiedReport = abi.decode(
                verifiedReportData,
                (BasicReport)
            );

            // Log price from report
            emit PriceUpdate(verifiedReport.price);
        } else {
            // ERROR LOGIC
        }
    }

    fallback() external payable {}
}
