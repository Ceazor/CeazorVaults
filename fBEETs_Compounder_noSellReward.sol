// SPDX-License-Identifier: MIT



import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// @dev because of above
// dont forget to flatten after deploying to verify on ftmscan 
// see https://forum.openzeppelin.com/t/verify-erc20-token-on-etherscan-that-was-deployed-through-remix-step-by-step-guide/9051

pragma solidity ^0.8.0;

interface IAuthorizer {
    /**
     * @dev Returns true if `account` can perform the action described by `actionId` in the contract `where`.
     */
    function canPerform(
        bytes32 actionId,
        address account,
        address where
    ) external view returns (bool);
}

interface IPoolToken {
    function getPoolTokens(bytes32 poolId)
        external
        returns (
            IERC20[] memory,
            uint256[] memory,
            uint256
        );
}



interface IPoolSwapStructs {
    // This is not really an interface - it just defines common structs used by other interfaces: IGeneralPool and
    // IMinimalSwapInfoPool.
    //
    // This data structure represents a request for a token swap, where `kind` indicates the swap type ('given in' or
    // 'given out') which indicates whether or not the amount sent by the pool is known.
    //
    // The pool receives `tokenIn` and sends `tokenOut`. `amount` is the number of `tokenIn` tokens the pool will take
    // in, or the number of `tokenOut` tokens the Pool will send out, depending on the given swap `kind`.
    //
    // All other fields are not strictly necessary for most swaps, but are provided to support advanced scenarios in
    // some Pools.
    //
    // `poolId` is the ID of the Pool involved in the swap - this is useful for Pool contracts that implement more than
    // one Pool.
    //
    // The meaning of `lastChangeBlock` depends on the Pool specialization:
    //  - Two Token or Minimal Swap Info: the last block in which either `tokenIn` or `tokenOut` changed its total
    //    balance.
    //  - General: the last block in which *any* of the Pool's registered tokens changed its total balance.
    //
    // `from` is the origin address for the funds the Pool receives, and `to` is the destination address
    // where the Pool sends the outgoing tokens.
    //
    // `userData` is extra data provided by the caller - typically a signature from a trusted party.
    struct SwapRequest {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amount;
        // Misc data
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }
}

interface IBasePool is IPoolSwapStructs {
    /**
     * @dev Called by the Vault when a user calls `IVault.joinPool` to add liquidity to this Pool. Returns how many of
     * each registered token the user should provide, as well as the amount of protocol fees the Pool owes to the Vault.
     * The Vault will then take tokens from `sender` and add them to the Pool's balances, as well as collect
     * the reported amount in protocol fees, which the pool should calculate based on `protocolSwapFeePercentage`.
     *
     * Protocol fees are reported and charged on join events so that the Pool is free of debt whenever new users join.
     *
     * `sender` is the account performing the join (from which tokens will be withdrawn), and `recipient` is the account
     * designated to receive any benefits (typically pool shares). `balances` contains the total balances
     * for each token the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
     *
     * `lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
     * balance.
     *
     * `userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
     * join (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
     *
     * Contracts implementing this function should check that the caller is indeed the Vault before performing any
     * state-changing operations, such as minting pool shares.
     */
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts);

    /**
     * @dev Called by the Vault when a user calls `IVault.exitPool` to remove liquidity from this Pool. Returns how many
     * tokens the Vault should deduct from the Pool's balances, as well as the amount of protocol fees the Pool owes
     * to the Vault. The Vault will then take tokens from the Pool's balances and send them to `recipient`,
     * as well as collect the reported amount in protocol fees, which the Pool should calculate based on
     * `protocolSwapFeePercentage`.
     *
     * Protocol fees are charged on exit events to guarantee that users exiting the Pool have paid their share.
     *
     * `sender` is the account performing the exit (typically the pool shareholder), and `recipient` is the account
     * to which the Vault will send the proceeds. `balances` contains the total token balances for each token
     * the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
     *
     * `lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
     * balance.
     *
     * `userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
     * exit (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
     *
     * Contracts implementing this function should check that the caller is indeed the Vault before performing any
     * state-changing operations, such as burning pool shares.
     */
    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts);

    function getPoolId() external view returns (bytes32);
}

/**
 * @dev Pool contracts with the MinimalSwapInfo or TwoToken specialization settings should implement this interface.
 *
 * This is called by the Vault when a user calls `IVault.swap` or `IVault.batchSwap` to swap with this Pool.
 * Returns the number of tokens the Pool will grant to the user in a 'given in' swap, or that the user will grant
 * to the pool in a 'given out' swap.
 *
 * This can often be implemented by a `view` function, since many pricing algorithms don't need to track state
 * changes in swaps. However, contracts implementing this in non-view functions should check that the caller is
 * indeed the Vault.
 */
interface IMinimalSwapInfoPool is IBasePool {
    function onSwap(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external returns (uint256 amount);
}

interface IGeneralPool is IBasePool {
    function onSwap(
        SwapRequest memory swapRequest,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) external returns (uint256 amount);
}

pragma solidity ^0.8.0;

interface IMasterChef {
    function poolLength() external view returns (uint256);
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
    function pendingSpirit(uint256 _pid, address _user) external view returns (uint256);
    function massUpdatePools() external;
    function updatePool(uint256 _pid) external;
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid, address _to) external;
}

interface IMasterChefv2 {
    function harvest(uint256 pid, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function deposit(uint256 pid, uint256 amount, address to) external;
    function beets() external view returns (uint256);
}

/**
 * @dev This is an empty interface used to represent either ERC20-conforming token contracts or ETH (using the zero
 * address sentinel value). We're just relying on the fact that `interface` can be used to declare new address-like
 * types.
 *
 * This concept is unrelated to a Pool's Asset Managers.
 */
interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}


/**
 * @dev Interface for the SignatureValidator helper, used to support meta-transactions.
 */
interface ISignaturesValidator {
    /**
     * @dev Returns the EIP712 domain separator.
     */
    function getDomainSeparator() external view returns (bytes32);

    /**
     * @dev Returns the next nonce used by an address to sign messages.
     */
    function getNextNonce(address user) external view returns (uint256);
}

interface ITemporarilyPausable {
    /**
     * @dev Emitted every time the pause state changes by `_setPaused`.
     */
    event PausedStateChanged(bool paused);

    /**
     * @dev Returns the current paused state.
     */
    function getPausedState()
        external
        view
        returns (
            bool paused,
            uint256 pauseWindowEndTime,
            uint256 bufferPeriodEndTime
        );
}

pragma solidity ^0.8.0;


interface IVault is ISignaturesValidator, ITemporarilyPausable {
    // Generalities about the Vault:
    //
    // - Whenever documentation refers to 'tokens', it strictly refers to ERC20-compliant token contracts. Tokens are
    // transferred out of the Vault by calling the `IERC20.transfer` function, and transferred in by calling
    // `IERC20.transferFrom`. In these cases, the sender must have previously allowed the Vault to use their tokens by
    // calling `IERC20.approve`. The only deviation from the ERC20 standard that is supported is functions not returning
    // a boolean value: in these scenarios, a non-reverting call is assumed to be successful.
    //
    // - All non-view functions in the Vault are non-reentrant: calling them while another one is mid-execution (e.g.
    // while execution control is transferred to a token contract during a swap) will result in a revert. View
    // functions can be called in a re-reentrant way, but doing so might cause them to return inconsistent results.
    // Contracts calling view functions in the Vault must make sure the Vault has not already been entered.
    //
    // - View functions revert if referring to either unregistered Pools, or unregistered tokens for registered Pools.

    // Authorizer
    //
    // Some system actions are permissioned, like setting and collecting protocol fees. This permissioning system exists
    // outside of the Vault in the Authorizer contract: the Vault simply calls the Authorizer to check if the caller
    // can perform a given action.

    /**
     * @dev Returns the Vault's Authorizer.
     */
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @dev Sets a new Authorizer for the Vault. The caller must be allowed by the current Authorizer to do this.
     *
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;

    /**
     * @dev Emitted when a new authorizer is set by `setAuthorizer`.
     */
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);

    // Relayers
    //
    // Additionally, it is possible for an account to perform certain actions on behalf of another one, using their
    // Vault ERC20 allowance and Internal Balance. These accounts are said to be 'relayers' for these Vault functions,
    // and are expected to be smart contracts with sound authentication mechanisms. For an account to be able to wield
    // this power, two things must occur:
    //  - The Authorizer must grant the account the permission to be a relayer for the relevant Vault function. This
    //    means that Balancer governance must approve each individual contract to act as a relayer for the intended
    //    functions.
    //  - Each user must approve the relayer to act on their behalf.
    // This double protection means users cannot be tricked into approving malicious relayers (because they will not
    // have been allowed by the Authorizer via governance), nor can malicious relayers approved by a compromised
    // Authorizer or governance drain user funds, since they would also need to be approved by each individual user.

    /**
     * @dev Returns true if `user` has approved `relayer` to act as a relayer for them.
     */
    function hasApprovedRelayer(address user, address relayer) external view returns (bool);

    /**
     * @dev Allows `relayer` to act as a relayer for `sender` if `approved` is true, and disallows it otherwise.
     *
     * Emits a `RelayerApprovalChanged` event.
     */
    function setRelayerApproval(
        address sender,
        address relayer,
        bool approved
    ) external;

    /**
     * @dev Emitted every time a relayer is approved or disapproved by `setRelayerApproval`.
     */
    event RelayerApprovalChanged(address indexed relayer, address indexed sender, bool approved);

    // Internal Balance
    //
    // Users can deposit tokens into the Vault, where they are allocated to their Internal Balance, and later
    // transferred or withdrawn. It can also be used as a source of tokens when joining Pools, as a destination
    // when exiting them, and as either when performing swaps. This usage of Internal Balance results in greatly reduced
    // gas costs when compared to relying on plain ERC20 transfers, leading to large savings for frequent users.
    //
    // Internal Balance management features batching, which means a single contract call can be used to perform multiple
    // operations of different kinds, with different senders and recipients, at once.

    /**
     * @dev Returns `user`'s Internal Balance for a set of tokens.
     */
    function getInternalBalance(address user, IERC20[] memory tokens) external view returns (uint256[] memory);

    /**
     * @dev Performs a set of user balance operations, which involve Internal Balance (deposit, withdraw or transfer)
     * and plain ERC20 transfers using the Vault's allowance. This last feature is particularly useful for relayers, as
     * it lets integrators reuse a user's Vault allowance.
     *
     * For each operation, if the caller is not `sender`, it must be an authorized relayer for them.
     */
    function manageUserBalance(UserBalanceOp[] memory ops) external payable;

    /**
     * @dev Data for `manageUserBalance` operations, which include the possibility for ETH to be sent and received
     without manual WETH wrapping or unwrapping.
     */
    struct UserBalanceOp {
        UserBalanceOpKind kind;
        IAsset asset;
        uint256 amount;
        address sender;
        address payable recipient;
    }

    // There are four possible operations in `manageUserBalance`:
    //
    // - DEPOSIT_INTERNAL
    // Increases the Internal Balance of the `recipient` account by transferring tokens from the corresponding
    // `sender`. The sender must have allowed the Vault to use their tokens via `IERC20.approve()`.
    //
    // ETH can be used by passing the ETH sentinel value as the asset and forwarding ETH in the call: it will be wrapped
    // and deposited as WETH. Any ETH amount remaining will be sent back to the caller (not the sender, which is
    // relevant for relayers).
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - WITHDRAW_INTERNAL
    // Decreases the Internal Balance of the `sender` account by transferring tokens to the `recipient`.
    //
    // ETH can be used by passing the ETH sentinel value as the asset. This will deduct WETH instead, unwrap it and send
    // it to the recipient as ETH.
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - TRANSFER_INTERNAL
    // Transfers tokens from the Internal Balance of the `sender` account to the Internal Balance of `recipient`.
    //
    // Reverts if the ETH sentinel value is passed.
    //
    // Emits an `InternalBalanceChanged` event.
    //
    //
    // - TRANSFER_EXTERNAL
    // Transfers tokens from `sender` to `recipient`, using the Vault's ERC20 allowance. This is typically used by
    // relayers, as it lets them reuse a user's Vault allowance.
    //
    // Reverts if the ETH sentinel value is passed.
    //
    // Emits an `ExternalBalanceTransfer` event.

    enum UserBalanceOpKind { DEPOSIT_INTERNAL, WITHDRAW_INTERNAL, TRANSFER_INTERNAL, TRANSFER_EXTERNAL }

    /**
     * @dev Emitted when a user's Internal Balance changes, either from calls to `manageUserBalance`, or through
     * interacting with Pools using Internal Balance.
     *
     * Because Internal Balance works exclusively with ERC20 tokens, ETH deposits and withdrawals will use the WETH
     * address.
     */
    event InternalBalanceChanged(address indexed user, IERC20 indexed token, int256 delta);

    /**
     * @dev Emitted when a user's Vault ERC20 allowance is used by the Vault to transfer tokens to an external account.
     */
    event ExternalBalanceTransfer(IERC20 indexed token, address indexed sender, address recipient, uint256 amount);

    // Pools
    //
    // There are three specialization settings for Pools, which allow for cheaper swaps at the cost of reduced
    // functionality:
    //
    //  - General: no specialization, suited for all Pools. IGeneralPool is used for swap request callbacks, passing the
    // balance of all tokens in the Pool. These Pools have the largest swap costs (because of the extra storage reads),
    // which increase with the number of registered tokens.
    //
    //  - Minimal Swap Info: IMinimalSwapInfoPool is used instead of IGeneralPool, which saves gas by only passing the
    // balance of the two tokens involved in the swap. This is suitable for some pricing algorithms, like the weighted
    // constant product one popularized by Balancer V1. Swap costs are smaller compared to general Pools, and are
    // independent of the number of registered tokens.
    //
    //  - Two Token: only allows two tokens to be registered. This achieves the lowest possible swap gas cost. Like
    // minimal swap info Pools, these are called via IMinimalSwapInfoPool.

    enum PoolSpecialization { GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN }

    /**
     * @dev Registers the caller account as a Pool with a given specialization setting. Returns the Pool's ID, which
     * is used in all Pool-related functions. Pools cannot be deregistered, nor can the Pool's specialization be
     * changed.
     *
     * The caller is expected to be a smart contract that implements either `IGeneralPool` or `IMinimalSwapInfoPool`,
     * depending on the chosen specialization setting. This contract is known as the Pool's contract.
     *
     * Note that the same contract may register itself as multiple Pools with unique Pool IDs, or in other words,
     * multiple Pools may share the same contract.
     *
     * Emits a `PoolRegistered` event.
     */
    function registerPool(PoolSpecialization specialization) external returns (bytes32);

    /**
     * @dev Emitted when a Pool is registered by calling `registerPool`.
     */
    event PoolRegistered(bytes32 indexed poolId, address indexed poolAddress, PoolSpecialization specialization);

    /**
     * @dev Returns a Pool's contract address and specialization setting.
     */
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);

    /**
     * @dev Registers `tokens` for the `poolId` Pool. Must be called by the Pool's contract.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Each token can only be registered once. For Pools with the Two Token specialization, `tokens` must have a length
     * of two, that is, both tokens must be registered in the same `registerTokens` call, and they must be sorted in
     * ascending order.
     *
     * The `tokens` and `assetManagers` arrays must have the same length, and each entry in these indicates the Asset
     * Manager for the corresponding token. Asset Managers can manage a Pool's tokens via `managePoolBalance`,
     * depositing and withdrawing them directly, and can even set their balance to arbitrary amounts. They are therefore
     * expected to be highly secured smart contracts with sound design principles, and the decision to register an
     * Asset Manager should not be made lightly.
     *
     * Pools can choose not to assign an Asset Manager to a given token by passing in the zero address. Once an Asset
     * Manager is set, it cannot be changed except by deregistering the associated token and registering again with a
     * different Asset Manager.
     *
     * Emits a `TokensRegistered` event.
     */
    function registerTokens(
        bytes32 poolId,
        IERC20[] memory tokens,
        address[] memory assetManagers
    ) external;

    /**
     * @dev Emitted when a Pool registers tokens by calling `registerTokens`.
     */
    event TokensRegistered(bytes32 indexed poolId, IERC20[] tokens, address[] assetManagers);

    /**
     * @dev Deregisters `tokens` for the `poolId` Pool. Must be called by the Pool's contract.
     *
     * Only registered tokens (via `registerTokens`) can be deregistered. Additionally, they must have zero total
     * balance. For Pools with the Two Token specialization, `tokens` must have a length of two, that is, both tokens
     * must be deregistered in the same `deregisterTokens` call.
     *
     * A deregistered token can be re-registered later on, possibly with a different Asset Manager.
     *
     * Emits a `TokensDeregistered` event.
     */
    function deregisterTokens(bytes32 poolId, IERC20[] memory tokens) external;

    /**
     * @dev Emitted when a Pool deregisters tokens by calling `deregisterTokens`.
     */
    event TokensDeregistered(bytes32 indexed poolId, IERC20[] tokens);

    /**
     * @dev Returns detailed information for a Pool's registered token.
     *
     * `cash` is the number of tokens the Vault currently holds for the Pool. `managed` is the number of tokens
     * withdrawn and held outside the Vault by the Pool's token Asset Manager. The Pool's total balance for `token`
     * equals the sum of `cash` and `managed`.
     *
     * Internally, `cash` and `managed` are stored using 112 bits. No action can ever cause a Pool's token `cash`,
     * `managed` or `total` balance to be greater than 2^112 - 1.
     *
     * `lastChangeBlock` is the number of the block in which `token`'s total balance was last modified (via either a
     * join, exit, swap, or Asset Manager update). This value is useful to avoid so-called 'sandwich attacks', for
     * example when developing price oracles. A change of zero (e.g. caused by a swap with amount zero) is considered a
     * change for this purpose, and will update `lastChangeBlock`.
     *
     * `assetManager` is the Pool's token Asset Manager.
     */
    function getPoolTokenInfo(bytes32 poolId, IERC20 token)
        external
        view
        returns (
            uint256 cash,
            uint256 managed,
            uint256 lastChangeBlock,
            address assetManager
        );

    /**
     * @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when *any* of
     * the tokens' `balances` changed.
     *
     * The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
     * Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
     *
     * If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
     * order as passed to `registerTokens`.
     *
     * Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
     * the amounts used by joins, exits and swaps. For a detailed breakdown of token balances, use `getPoolTokenInfo`
     * instead.
     */
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );

    /**
     * @dev Called by users to join a Pool, which transfers tokens from `sender` into the Pool's balance. This will
     * trigger custom Pool behavior, which will typically grant something in return to `recipient` - often tokenized
     * Pool shares.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `assets` and `maxAmountsIn` arrays must have the same length, and each entry indicates the maximum amount
     * to send for each asset. The amounts to send are decided by the Pool and not the Vault: it just enforces
     * these maximums.
     *
     * If joining a Pool that holds WETH, it is possible to send ETH directly: the Vault will do the wrapping. To enable
     * this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead of the
     * WETH address. Note that it is not possible to combine ETH and WETH in the same join. Any excess ETH will be sent
     * back to the caller (not the sender, which is important for relayers).
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If sending ETH however, the array must be
     * sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the final
     * `assets` array might not be sorted. Pools with no registered tokens cannot be joined.
     *
     * If `fromInternalBalance` is true, the caller's Internal Balance will be preferred: ERC20 transfers will only
     * be made for the difference between the requested amount and Internal Balance (if any). Note that ETH cannot be
     * withdrawn from Internal Balance: attempting to do so will trigger a revert.
     *
     * This causes the Vault to call the `IBasePool.onJoinPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares). This can be encoded in the `userData` argument, which is ignored by the Vault and passed
     * directly to the Pool's contract, as is `recipient`.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    /**
     * @dev Called by users to exit a Pool, which transfers tokens from the Pool's balance to `recipient`. This will
     * trigger custom Pool behavior, which will typically ask for something in return from `sender` - often tokenized
     * Pool shares. The amount of tokens that can be withdrawn is limited by the Pool's `cash` balance (see
     * `getPoolTokenInfo`).
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `tokens` and `minAmountsOut` arrays must have the same length, and each entry in these indicates the minimum
     * token amount to receive for each token contract. The amounts to send are decided by the Pool and not the Vault:
     * it just enforces these minimums.
     *
     * If exiting a Pool that holds WETH, it is possible to receive ETH directly: the Vault will do the unwrapping. To
     * enable this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead
     * of the WETH address. Note that it is not possible to combine ETH and WETH in the same exit.
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If receiving ETH however, the array must
     * be sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the
     * final `assets` array might not be sorted. Pools with no registered tokens cannot be exited.
     *
     * If `toInternalBalance` is true, the tokens will be deposited to `recipient`'s Internal Balance. Otherwise,
     * an ERC20 transfer will be performed. Note that ETH cannot be deposited to Internal Balance: attempting to
     * do so will trigger a revert.
     *
     * `minAmountsOut` is the minimum amount of tokens the user expects to get out of the Pool, for each token in the
     * `tokens` array. This array must match the Pool's registered tokens.
     *
     * This causes the Vault to call the `IBasePool.onExitPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares to return). This can be encoded in the `userData` argument, which is ignored by the Vault and
     * passed directly to the Pool's contract.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    /**
     * @dev Emitted when a user joins or exits a Pool by calling `joinPool` or `exitPool`, respectively.
     */
    event PoolBalanceChanged(
        bytes32 indexed poolId,
        address indexed liquidityProvider,
        IERC20[] tokens,
        int256[] deltas,
        uint256[] protocolFeeAmounts
    );

    enum PoolBalanceChangeKind { JOIN, EXIT }

    // Swaps
    //
    // Users can swap tokens with Pools by calling the `swap` and `batchSwap` functions. To do this,
    // they need not trust Pool contracts in any way: all security checks are made by the Vault. They must however be
    // aware of the Pools' pricing algorithms in order to estimate the prices Pools will quote.
    //
    // The `swap` function executes a single swap, while `batchSwap` can perform multiple swaps in sequence.
    // In each individual swap, tokens of one kind are sent from the sender to the Pool (this is the 'token in'),
    // and tokens of another kind are sent from the Pool to the recipient in exchange (this is the 'token out').
    // More complex swaps, such as one token in to multiple tokens out can be achieved by batching together
    // individual swaps.
    //
    // There are two swap kinds:
    //  - 'given in' swaps, where the amount of tokens in (sent to the Pool) is known, and the Pool determines (via the
    // `onSwap` hook) the amount of tokens out (to send to the recipient).
    //  - 'given out' swaps, where the amount of tokens out (received from the Pool) is known, and the Pool determines
    // (via the `onSwap` hook) the amount of tokens in (to receive from the sender).
    //
    // Additionally, it is possible to chain swaps using a placeholder input amount, which the Vault replaces with
    // the calculated output of the previous swap. If the previous swap was 'given in', this will be the calculated
    // tokenOut amount. If the previous swap was 'given out', it will use the calculated tokenIn amount. These extended
    // swaps are known as 'multihop' swaps, since they 'hop' through a number of intermediate tokens before arriving at
    // the final intended token.
    //
    // In all cases, tokens are only transferred in and out of the Vault (or withdrawn from and deposited into Internal
    // Balance) after all individual swaps have been completed, and the net token balance change computed. This makes
    // certain swap patterns, such as multihops, or swaps that interact with the same token pair in multiple Pools, cost
    // much less gas than they would otherwise.
    //
    // It also means that under certain conditions it is possible to perform arbitrage by swapping with multiple
    // Pools in a way that results in net token movement out of the Vault (profit), with no tokens being sent in (only
    // updating the Pool's internal accounting).
    //
    // To protect users from front-running or the market changing rapidly, they supply a list of 'limits' for each token
    // involved in the swap, where either the maximum number of tokens to send (by passing a positive value) or the
    // minimum amount of tokens to receive (by passing a negative value) is specified.
    //
    // Additionally, a 'deadline' timestamp can also be provided, forcing the swap to fail if it occurs after
    // this point in time (e.g. if the transaction failed to be included in a block promptly).
    //
    // If interacting with Pools that hold WETH, it is possible to both send and receive ETH directly: the Vault will do
    // the wrapping and unwrapping. To enable this mechanism, the IAsset sentinel value (the zero address) must be
    // passed in the `assets` array instead of the WETH address. Note that it is possible to combine ETH and WETH in the
    // same swap. Any excess ETH will be sent back to the caller (not the sender, which is relevant for relayers).
    //
    // Finally, Internal Balance can be used when either sending or receiving tokens.

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    /**
     * @dev Performs a swap with a single Pool.
     *
     * If the swap is 'given in' (the number of tokens to send to the Pool is known), it returns the amount of tokens
     * taken from the Pool, which must be greater than or equal to `limit`.
     *
     * If the swap is 'given out' (the number of tokens to take from the Pool is known), it returns the amount of tokens
     * sent to the Pool, which must be less than or equal to `limit`.
     *
     * Internal Balance usage and the recipient are determined by the `funds` struct.
     *
     * Emits a `Swap` event.
     */
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    /**
     * @dev Data for a single swap executed by `swap`. `amount` is either `amountIn` or `amountOut` depending on
     * the `kind` value.
     *
     * `assetIn` and `assetOut` are either token addresses, or the IAsset sentinel value for ETH (the zero address).
     * Note that Pools never interact with ETH directly: it will be wrapped to or unwrapped from WETH by the Vault.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    /**
     * @dev Performs a series of swaps with one or multiple Pools. In each individual swap, the caller determines either
     * the amount of tokens sent to or received from the Pool, depending on the `kind` value.
     *
     * Returns an array with the net Vault asset balance deltas. Positive amounts represent tokens (or ETH) sent to the
     * Vault, and negative amounts represent tokens (or ETH) sent by the Vault. Each delta corresponds to the asset at
     * the same index in the `assets` array.
     *
     * Swaps are executed sequentially, in the order specified by the `swaps` array. Each array element describes a
     * Pool, the token to be sent to this Pool, the token to receive from it, and an amount that is either `amountIn` or
     * `amountOut` depending on the swap kind.
     *
     * Multihop swaps can be executed by passing an `amount` value of zero for a swap. This will cause the amount in/out
     * of the previous swap to be used as the amount in for the current one. In a 'given in' swap, 'tokenIn' must equal
     * the previous swap's `tokenOut`. For a 'given out' swap, `tokenOut` must equal the previous swap's `tokenIn`.
     *
     * The `assets` array contains the addresses of all assets involved in the swaps. These are either token addresses,
     * or the IAsset sentinel value for ETH (the zero address). Each entry in the `swaps` array specifies tokens in and
     * out by referencing an index in `assets`. Note that Pools never interact with ETH directly: it will be wrapped to
     * or unwrapped from WETH by the Vault.
     *
     * Internal Balance usage, sender, and recipient are determined by the `funds` struct. The `limits` array specifies
     * the minimum or maximum amount of each token the vault is allowed to transfer.
     *
     * `batchSwap` can be used to make a single swap, like `swap` does, but doing so requires more gas than the
     * equivalent `swap` call.
     *
     * Emits `Swap` events.
     */
    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

    /**
     * @dev Data for each individual swap executed by `batchSwap`. The asset in and out fields are indexes into the
     * `assets` array passed to that function, and ETH assets are converted to WETH.
     *
     * If `amount` is zero, the multihop mechanism is used to determine the actual amount based on the amount in/out
     * from the previous swap, depending on the swap kind.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    /**
     * @dev Emitted for each individual swap performed by `swap` or `batchSwap`.
     */
    event Swap(
        bytes32 indexed poolId,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @dev All tokens in a swap are either sent from the `sender` account to the Vault, or from the Vault to the
     * `recipient` account.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * If `fromInternalBalance` is true, the `sender`'s Internal Balance will be preferred, performing an ERC20
     * transfer for the difference between the requested amount and the User's Internal Balance (if any). The `sender`
     * must have allowed the Vault to use their tokens via `IERC20.approve()`. This matches the behavior of
     * `joinPool`.
     *
     * If `toInternalBalance` is true, tokens will be deposited to `recipient`'s internal balance instead of
     * transferred. This matches the behavior of `exitPool`.
     *
     * Note that ETH cannot be deposited to or withdrawn from Internal Balance: attempting to do so will trigger a
     * revert.
     */
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /**
     * @dev Simulates a call to `batchSwap`, returning an array of Vault asset deltas. Calls to `swap` cannot be
     * simulated directly, but an equivalent `batchSwap` call can and will yield the exact same result.
     *
     * Each element in the array corresponds to the asset at the same index, and indicates the number of tokens (or ETH)
     * the Vault would take from the sender (if positive) or send to the recipient (if negative). The arguments it
     * receives are the same that an equivalent `batchSwap` call would receive.
     *
     * Unlike `batchSwap`, this function performs no checks on the sender or recipient field in the `funds` struct.
     * This makes it suitable to be called by off-chain applications via eth_call without needing to hold tokens,
     * approve them for the Vault, or even know a user's address.
     *
     * Note that this function is not 'view' (due to implementation details): the client code must explicitly execute
     * eth_call instead of eth_sendTransaction.
     */
    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);



    // Asset Management
    //
    // Each token registered for a Pool can be assigned an Asset Manager, which is able to freely withdraw the Pool's
    // tokens from the Vault, deposit them, or assign arbitrary values to its `managed` balance (see
    // `getPoolTokenInfo`). This makes them extremely powerful and dangerous. Even if an Asset Manager only directly
    // controls one of the tokens in a Pool, a malicious manager could set that token's balance to manipulate the
    // prices of the other tokens, and then drain the Pool with swaps. The risk of using Asset Managers is therefore
    // not constrained to the tokens they are managing, but extends to the entire Pool's holdings.
    //
    // However, a properly designed Asset Manager smart contract can be safely used for the Pool's benefit,
    // for example by lending unused tokens out for interest, or using them to participate in voting protocols.
    //
    // This concept is unrelated to the IAsset interface.

    /**
     * @dev Performs a set of Pool balance operations, which may be either withdrawals, deposits or updates.
     *
     * Pool Balance management features batching, which means a single contract call can be used to perform multiple
     * operations of different kinds, with different Pools and tokens, at once.
     *
     * For each operation, the caller must be registered as the Asset Manager for `token` in `poolId`.
     */
    function managePoolBalance(PoolBalanceOp[] memory ops) external;

    struct PoolBalanceOp {
        PoolBalanceOpKind kind;
        bytes32 poolId;
        IERC20 token;
        uint256 amount;
    }

    /**
     * Withdrawals decrease the Pool's cash, but increase its managed balance, leaving the total balance unchanged.
     *
     * Deposits increase the Pool's cash, but decrease its managed balance, leaving the total balance unchanged.
     *
     * Updates don't affect the Pool's cash balance, but because the managed balance changes, it does alter the total.
     * The external amount can be either increased or decreased by this call (i.e., reporting a gain or a loss).
     */
    enum PoolBalanceOpKind { WITHDRAW, DEPOSIT, UPDATE }

    /**
     * @dev Emitted when a Pool's token Asset Manager alters its balance via `managePoolBalance`.
     */
    event PoolBalanceManaged(
        bytes32 indexed poolId,
        address indexed assetManager,
        IERC20 indexed token,
        int256 cashDelta,
        int256 managedDelta
    );

    // Protocol Fees
    //
    // Some operations cause the Vault to collect tokens in the form of protocol fees, which can then be withdrawn by
    // permissioned accounts.
    //
    // There are two kinds of protocol fees:
    //
    //  - flash loan fees: charged on all flash loans, as a percentage of the amounts lent.
    //
    //  - swap fees: a percentage of the fees charged by Pools when performing swaps. For a number of reasons, including
    // swap gas costs and interface simplicity, protocol swap fees are not charged on each individual swap. Rather,
    // Pools are expected to keep track of how much they have charged in swap fees, and pay any outstanding debts to the
    // Vault when they are joined or exited. This prevents users from joining a Pool with unpaid debt, as well as
    // exiting a Pool in debt without first paying their share.

    /**
     * @dev Safety mechanism to pause most Vault operations in the event of an emergency - typically detection of an
     * error in some part of the system.
     *
     * The Vault can only be paused during an initial time period, after which pausing is forever disabled.
     *
     * While the contract is paused, the following features are disabled:
     * - depositing and transferring internal balance
     * - transferring external balance (using the Vault's allowance)
     * - swaps
     * - joining Pools
     * - Asset Manager interactions
     *
     * Internal Balance can still be withdrawn, and Pools exited.
     */
    function setPaused(bool paused) external;

    /**
     * @dev Returns the Vault's WETH instance.
     */
}

interface IBaseWeightedPool {

    enum JoinKind { INIT, EXACT_TOKENS_IN_FOR_BPT_OUT, TOKEN_IN_FOR_EXACT_BPT_OUT, ALL_TOKENS_IN_FOR_EXACT_BPT_OUT }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT,
        MANAGEMENT_FEE_TOKENS_OUT // for InvestmentPool
    }

    function getNormalizedWeights() external view returns (uint256[] memory);


}

interface IBeetsBar{
    function enter(uint256 amount) external;
    function leave(uint256 amount) external;
}

interface IDelegateRegistry {
  function clearDelegate(bytes32 id) external;
  function delegation(address, bytes32) external view returns (address);
  function setDelegate(bytes32 id, address delegate) external;
}

interface IUniRouterMinimal {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWrappedNative is IERC20 {
    function ERR_INVALID_ZERO_VALUE() external view returns (uint256);

    function ERR_NO_ERROR() external view returns (uint256);

    function deposit() external payable returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);
}

interface IRFVault {
    function getPricePerFullShare() external view returns (uint256);
}

pragma solidity ^0.8.0;
/**
 * @dev Implementation of a strategy to get yields from farming LP Pools in SpookySwap.
 * SpookySwap is an automated market maker (“AMM”) that allows two tokens to be exchanged on Fantom's Opera Network.
 *
 * This strategy deposits whatever funds it receives from the vault into the selected masterChef pool.
 * rewards from providing liquidity are farmed every few minutes, sold and split 50/50.
 * The corresponding pair of assets are bought and more liquidity is added to the masterChef pool.
 *
 * Expect the amount of LP tokens you have to grow over time while you have assets deposit
 */
contract CeazorAutoCompoundBeethoven_fBEETS_noFeeSell is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wftm} - Required for liquidity routing when doing swaps.
     * {rewardToken} - Token generated by staking our funds.
     * {lpToken} - LP Token that the strategy maximizes.
     * {lpToken0, lpToken1} - Tokens that the strategy maximizes. IUniswapV2Pair tokens.
     */
    address public constant wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant underlyingLP = address(0xcdE5a11a4ACB4eE4c805352Cec57E236bdBC3837);
    address public constant fBEETS = address(0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1);
    address public constant rewardToken = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);// beets token
    address public constant BeetVault = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    address public lpToken;

    uint8 public totalUnderlyingTokens;

    mapping(uint8 => bool) public isEmitting;
    bool public harvestOn = false;
    bool public depositsPaused = false;
    /**
     * @dev Third Party Contracts:
     * {router} - the router for target DEX
     * {masterChef} - masterChef contract
     * {poolId} - masterChef pool id
     */

    address public masterChef = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);
    uint public poolId;
    bytes32 public poolID_bytes;

    uint8 public beetsPosition = 0;
    uint8 public wftmPosition = 0;
    bool public beetsUnderlying = false;
    bool public wftmUnderlying = false;
    bytes32 public route_ID;
    bytes32 public constant wftmRoute_ID = 0xcde5a11a4acb4ee4c805352cec57e236bdbc3837000200000000000000000019;
    bool public secondReward = false;
    address public secondRewardToken;
    bytes32 public secondRewardRoute;


    struct Harvest {
        uint256 timestamp;
        uint256 vaultSharePrice;
    }

    Harvest[] public harvestLog;
    uint256 public harvestLogCadence = 1 hours;
    uint256 public constant ONE_YEAR = 365 days;

    /**
     * @dev Ceazor Contracts:
     * {treasury} - Address of the Ceazor treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    address public treasury;
    address public vault;
    address public strategistRemitter;

     /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on
     * Current implementation separates 5% for fees. Can be changed through the constructor
     * Inputs in constructor should be ratios between the Fee and Max Fee, divisble into percents by 10000
     *
     * {callFee} - Percent of the totalFee reserved for the harvester (1000 = 10% of total fee: 0.5% by default)
     * {treasuryFee} - Percent of the totalFee taken by maintainers of the software (9000 = 90% of total fee: 4.5% by default)
     * {securityFee} - Fee taxed when a user withdraws funds. Taken to prevent flash deposit/harvest attacks.
     * These funds are redistributed to stakers in the pool.
     *
     * {totalFee} - divided by 10,000 to determine the % fee. Set to 5% by default and
     * lowered as necessary to provide users with the most competitive APY.
     *
     * {MAX_FEE} - Maximum fee allowed by the strategy. Hard-capped at 5%.
     * {PERCENT_DIVISOR} - Constant used to safely calculate the correct percentages.
     */

    uint public callFee = 1000;
    uint public treasuryFee = 9000;
    uint256 public strategistFee = 2500;
    uint public securityFee = 10;
    uint public totalFee = 100;
    uint constant public MAX_FEE = 500;
    uint256 public constant STRATEGIST_MAX_FEE = 5000;
    uint constant  public PERCENT_DIVISOR = 10000;

    /**
     * @dev Routes we take to swap tokens using PanrewardTokenSwap.
     * {rewardTokenToWftmRoute} - Route we take to get from {rewardToken} into {wftm}.
     * {rewardTokenToLp0Route} - Route we take to get from {rewardToken} into {lpToken0}.
     * {rewardTokenToLp1Route} - Route we take to get from {rewardToken} into {lpToken1}.
     */

    mapping (uint8 => address) public LPs;

    /**
     * {StratHarvest} Event that is fired each time someone harvests the strat.
     * {TotalFeeUpdated} Event that is fired each time the total fee is updated.
     * {CallFeeUpdated} Event that is fired each time the call fee is updated.
     */
    event StratHarvest(address indexed harvester);
    event TotalFeeUpdated(uint newFee);
    event CallFeeUpdated(uint newCallFee, uint newTreasuryFee);

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    constructor (
      address _lpToken,
      uint _poolId,
      address _vault,
      address _treasury,
      address _strategistRemitter
    ) {
        lpToken = _lpToken;
        poolId = _poolId;
        poolID_bytes = wftmRoute_ID;
        vault = _vault;
        treasury = _treasury;
        strategistRemitter = _strategistRemitter;

        //gather underlying tokens
        //we're assuming we are dealing with the PoolTokens.sol for the interface
        IERC20[] memory _lps;

        (_lps,,) = IVault(BeetVault).getPoolTokens(poolID_bytes);
        totalUnderlyingTokens = uint8(_lps.length);

        for(uint8 i; i < _lps.length; i++){
            LPs[i] = address(_lps[i]);
            if(LPs[i] == wftm){
                wftmPosition = i;
                wftmUnderlying = true;
            }

            if(LPs[i] == rewardToken){
                beetsPosition = i;
                beetsUnderlying = true;
            }
        }

        _giveAllowances(); //this will also need work
        harvestLog.push(Harvest({timestamp: block.timestamp, vaultSharePrice: IRFVault(_vault).getPricePerFullShare()}));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {lpToken} in the masterChef to farm {rewardToken}
     */
    function deposit() external {
        require(!depositsPaused, "cannot deposit at this time");
        _deposit();
    }

    function _deposit() internal whenNotPaused onActionHarvest{
        uint256 pairBal = IERC20(lpToken).balanceOf(address(this));

        if (pairBal > 0) {
            IMasterChefv2(masterChef).deposit(poolId, pairBal, address(this));
        }
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {lpToken} from the masterChef.
     * The available {lpToken} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external onActionHarvest{
    require(msg.sender == vault, "!vault");

      uint256 pairBal = IERC20(lpToken).balanceOf(address(this));

      if (pairBal < _amount) {
        IMasterChefv2(masterChef).withdrawAndHarvest(poolId, _amount.sub(pairBal), address(this));
        pairBal = IERC20(lpToken).balanceOf(address(this));
      }

      if (pairBal > _amount) {
        pairBal = _amount;
      }
      uint256 withdrawFee = pairBal.mul(securityFee).div(PERCENT_DIVISOR);
      IERC20(lpToken).safeTransfer(vault, pairBal.sub(withdrawFee));
    }

    function harvest() external {
        _harvest(false);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the masterChef.
     * 2. It charges the system fees to simplify the split.
     * 3. It swaps the {rewardToken} token for {lpToken0} & {lpToken1}
     * 4. Adds more liquidity to the pool.
     * 5. It deposits the new LP tokens.
     */
    function _harvest(bool _remitStrategist) internal whenNotPaused {
        IMasterChefv2(masterChef).harvest(poolId, address(this));
        _chargeFees(_remitStrategist);

        if(secondReward){_swapSecondToken(secondRewardToken, secondRewardRoute);}

        _addLiquidity(rewardToken, beetsPosition);

        _enterX();

        _deposit();

        if (block.timestamp >= harvestLog[harvestLog.length - 1].timestamp + harvestLogCadence) {
            harvestLog.push(
                Harvest({timestamp: block.timestamp, vaultSharePrice: IRFVault(vault).getPricePerFullShare()})
            );
        }

        emit StratHarvest(msg.sender);
    }

    function _enterX() internal {
        uint256 amtLP = IERC20(underlyingLP).balanceOf(address(this));
        IBeetsBar(fBEETS).enter(amtLP);
    }

    /**
     * @dev Takes out fees from the rewards. Set by constructor
     * callFeeToUser is set as a percentage of the fee,
     * as is treasuryFeeToVault
     * Ceazor modified the following to stop the selling of reward to wftm from most fees
     */
    function _chargeFees(bool _remitStrategist) internal {
        uint256 rewardBal = IERC20(rewardToken).balanceOf(address(this));
        
        uint256 fees;
        uint256 allFees;

        

        fees = rewardBal.mul(totalFee).div(PERCENT_DIVISOR);
        // _swap(rewardToken, wftm, wftmRoute_ID, fees);
        // allFees = IERC20(rewardToken).balanceOf(address(this)).sub(rewardBal);

        uint256 callFeeToUser = fees.mul(callFee).div(PERCENT_DIVISOR);
        _swap(rewardToken, wftm, wftmRoute_ID, callFeeToUser);       // Ceazor moved swap to here to only swap for callFee, see amount change

        IERC20(wftm).safeTransfer(msg.sender, callFeeToUser);

        uint256 restFees = allFees.sub(callFeeToUser);


        uint256 treasuryFeeToVault = restFees.mul(treasuryFee).div(PERCENT_DIVISOR);
        if (_remitStrategist) {
            uint256 feeToStrategist = treasuryFeeToVault.mul(strategistFee).div(PERCENT_DIVISOR);
            treasuryFeeToVault = treasuryFeeToVault.sub(feeToStrategist);
            IERC20(rewardToken).safeTransfer(strategistRemitter, feeToStrategist);
        }
        IERC20(rewardToken).safeTransfer(treasury, treasuryFeeToVault);

    }


    //function to swap from one token to another given a pool containing them both
    function _swap(address _tokenIN, address _tokenOUT, bytes32 _pool, uint256 amount) internal{

        IVault.SingleSwap memory singleSwap;
        IVault.SwapKind swapKind = IVault.SwapKind.GIVEN_IN;

        singleSwap.poolId = _pool;
        singleSwap.kind = swapKind;
        singleSwap.assetIn = IAsset(_tokenIN);
        singleSwap.assetOut = IAsset(_tokenOUT);
        singleSwap.amount = amount;
        singleSwap.userData = abi.encode(0);

        IVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        IERC20(_tokenIN).safeApprove(BeetVault, 0);
        IERC20(_tokenIN).safeApprove(BeetVault, amount);

        IVault(BeetVault).swap(singleSwap, funds, 1, (block.timestamp + 600));

    }

    /**
     * @dev Swaps {rewardToken} for {lpToken0}, {lpToken1} & {wftm} using SpookySwap.
     */
    function _addLiquidity(address token, uint8 position) internal {
        uint256 depositTokenBalance = IERC20(token).balanceOf(address(this));

        IERC20(token).safeApprove(BeetVault, 0);
        IERC20(token).safeApprove(BeetVault, depositTokenBalance);

        IBaseWeightedPool.JoinKind joinKind = IBaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256[] memory amountsIn = new uint256[](totalUnderlyingTokens);
        amountsIn[position] = depositTokenBalance;
        uint256 minAmountOut = 1;
        IAsset[] memory _assets = new IAsset[](totalUnderlyingTokens);
        for(uint8 i = 0; i < totalUnderlyingTokens; i++){
            _assets[i] = IAsset(LPs[i]);
        }



        bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

        IVault.JoinPoolRequest memory request;
        request.assets = _assets;
        request.maxAmountsIn = amountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        IVault(BeetVault).joinPool(
            poolID_bytes,
            address(this),
            address(this),
            request
        );
    }

    /**
     * @dev Function to calculate the total underlaying {lpToken} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in the masterChef.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfLpPair().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {lpToken} the contract holds.
     */
    function balanceOfLpPair() public view returns (uint256) {
        return IERC20(lpToken).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {lpToken} the strategy has allocated in the masterChef
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = IMasterChef(masterChef).userInfo(poolId, address(this));
        return _amount;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChefv2(masterChef).withdrawAndHarvest(poolId, balanceOfPool(), address(this));

        uint256 pairBal = IERC20(lpToken).balanceOf(address(this));
        IERC20(lpToken).transfer(vault, pairBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the masterChef, leaving rewards behind
     */
    function panic() public onlyOwner {
        pause();
        IMasterChef(masterChef).emergencyWithdraw(poolId, address(this));
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
      _pause();
      _removeAllowances();
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        _giveAllowances();

        _deposit();
    }

    function _giveAllowances() internal {
        IERC20(underlyingLP).safeApprove(fBEETS, 0);
        IERC20(rewardToken).safeApprove(BeetVault, 0);
        IERC20(wftm).safeApprove(BeetVault, 0);
        IERC20(fBEETS).safeApprove(masterChef, 0);
        IERC20(underlyingLP).safeApprove(fBEETS, type(uint256).max);
        IERC20(rewardToken).safeApprove(BeetVault, type(uint256).max);
        IERC20(wftm).safeApprove(BeetVault, type(uint256).max);
        IERC20(fBEETS).safeApprove(masterChef, type(uint256).max);

    }

    function _removeAllowances() internal {
        IERC20(underlyingLP).safeApprove(fBEETS, 0);
        IERC20(rewardToken).safeApprove(BeetVault, 0);
        IERC20(wftm).safeApprove(BeetVault, 0);
        IERC20(fBEETS).safeApprove(masterChef, 0);
    }


    /**
     * @dev updates the total fee, capped at 5%
     */
    function updateTotalFee(uint _totalFee) external onlyOwner returns (bool) {
      require(_totalFee <= MAX_FEE, "Fee Too High");
      totalFee = _totalFee;
      emit TotalFeeUpdated(totalFee);
      return true;
    }

    /**
     * @dev updates the strategist fee, capped at 50% of treasury fee
     */
    function updateStrategistFee(uint256 _strategistFee) external onlyOwner {
      require(_strategistFee <= STRATEGIST_MAX_FEE, "Fee Too High");
      strategistFee = _strategistFee;
    }

    /**
     * @dev updates the call fee and adjusts the treasury fee to cover the difference
     */
    function updateCallFee(uint _callFee) external onlyOwner returns (bool) {
      callFee = _callFee;
      treasuryFee = PERCENT_DIVISOR.sub(callFee);
      emit CallFeeUpdated(callFee, treasuryFee);
      return true;
    }

    function harvestOnAction(bool _setting) external onlyOwner returns (bool){
        harvestOn = _setting;
        return true;
    }


    modifier onActionHarvest {
        if (harvestOn == true){
            _harvest(false);
        }
        _;
    }

    function updateRouteID(bytes32 newID) external onlyOwner {
        route_ID = newID;
    }

    function updateTreasury(address newTreasury) external onlyOwner returns (bool) {
      treasury = newTreasury;
      return true;
    }

    function _swapSecondToken(address token, bytes32 route) internal {

            uint256 wftmBal = IERC20(wftm).balanceOf(address(this));
            uint256 bal = IERC20(token).balanceOf(address(this));
            _swap(token, wftm, route, bal);
            uint256 fees = IERC20(wftm).balanceOf(address(this)).sub(wftmBal).mul(totalFee).div(PERCENT_DIVISOR);

            uint256 callFeeToUser = fees.mul(callFee).div(PERCENT_DIVISOR);
            IERC20(wftm).safeTransfer(msg.sender, callFeeToUser);

            uint256 treasuryFeeToVault = fees.mul(treasuryFee).div(PERCENT_DIVISOR);
            IERC20(wftm).safeTransfer(treasury, treasuryFeeToVault);

            
            wftmBal = IERC20(wftm).balanceOf(address(this));
            _swap(wftm, rewardToken, wftmRoute_ID, wftmBal);
            


    }

    // NOTE: this is a centralized, high trust function used to securely deliver a secondary reward payload to users in the vault
    // Please ensure anyone operating clones of this vault are trustworthy before putting your money in
    function secondRewardInformation(bool status, address token, bytes32 route) external onlyOwner {
        require(token != rewardToken, "rewardToken is already accounted for");
        secondReward = status;
        secondRewardToken = token;
        secondRewardRoute = route;
    }

    function updateSecurityFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "fee too high");
        securityFee = _fee;
    }

    // ####################################################
    // ONLY-OWNER VOTING/BRIBE-RELATED FUNCTIONS
    // ####################################################
    function setDepositsPaused(bool _depositsPaused) external onlyOwner {
        depositsPaused = _depositsPaused;
    }

    function setDelegate(address _registry, bytes32 _id, address _delegate) external onlyOwner {
        IDelegateRegistry(_registry).setDelegate(_id, _delegate);
    }

    // swaps {_tokens[0]} to {rewardToken} using {_routes} (series of Beethoven swaps)
    function swapBribeToken(address[] calldata _tokens, bytes32[] calldata _routes) external onlyOwner {
        require(_tokens.length != 0 && _tokens.length == _routes.length, "bad arrays");
        for(uint256 i = 0; i < _tokens.length; i++) {
            address nextToken;
            if (i == _tokens.length - 1) {
                nextToken = rewardToken;
            } else {
                nextToken = _tokens[i + 1];
            }

            _swap(_tokens[i], nextToken, _routes[i], IERC20(_tokens[i]).balanceOf(address(this)));
        }
        _harvest(true); // charge strategist fee
    }

    // swaps {_path[0]} to {rewardToken} using {_path} (Uni router swap)
    function swapBribeTokenWithUniRouter(address _router, address[] calldata _path) external onlyOwner {
        IERC20 token = IERC20(_path[0]);
        uint256 tokenBal = token.balanceOf(address(this));
        token.safeIncreaseAllowance(_router, tokenBal);

        IUniRouterMinimal(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenBal,
            0,
            _path,
            address(this),
            block.timestamp + 600
        );
        _harvest(true); // charge strategist fee
    }

    function wrapNativeBribe(address _wrappedNative) external onlyOwner {
        IWrappedNative wrapped = IWrappedNative(_wrappedNative);
        uint256 balance = address(this).balance;
        require(wrapped.deposit{value: balance}() == wrapped.ERR_NO_ERROR(), "wrapping error");
    }

    receive() external payable { }

    // ####################################################
    // ON-CHAIN APR CALCULATION FUNCTIONS
    // ####################################################
    function updateHarvestLogCadence(uint256 _newCadenceInSeconds) external onlyOwner {
        harvestLogCadence = _newCadenceInSeconds;
    }

    function harvestLogLength() external view returns (uint256) {
        return harvestLog.length;
    }

    /**
     * @dev Returns a slice of the harvest log containing the _n latest harvests.
     */
    function latestHarvestLogSlice(uint256 _n) external view returns (Harvest[] memory slice) {
        slice = new Harvest[](_n);
        uint256 sliceCounter = 0;

        for (uint256 i = harvestLog.length - _n; i < harvestLog.length; i++) {
            slice[sliceCounter++] = harvestLog[i];
        }
    }

    /**
     * @dev Traverses the harvest log backwards until it hits _timestamp,
     *      and returns the average APR calculated across all the included
     *      log entries. APR is multiplied by PERCENT_DIVISOR to retain precision.
     */
    function averageAPRSince(uint256 _timestamp) external view returns (int256) {
        require(harvestLog.length >= 2, "need at least 2 log entries");

        int256 runningAPRSum;
        int256 numLogsProcessed;

        for (uint256 i = harvestLog.length - 1; i > 0 && harvestLog[i].timestamp >= _timestamp; i--) {
            runningAPRSum += calculateAPRUsingLogs(i - 1, i);
            numLogsProcessed++;
        }

        return runningAPRSum / numLogsProcessed;
    }

    /**
     * @dev Traverses the harvest log backwards _n items,
     *      and returns the average APR calculated across all the included
     *      log entries. APR is multiplied by PERCENT_DIVISOR to retain precision.
     */
    function averageAPRAcrossLastNHarvests(int256 _n) external view returns (int256) {
        require(harvestLog.length >= 2, "need at least 2 log entries");

        int256 runningAPRSum;
        int256 numLogsProcessed;

        for (uint256 i = harvestLog.length - 1; i > 0 && numLogsProcessed < _n; i--) {
            runningAPRSum += calculateAPRUsingLogs(i - 1, i);
            numLogsProcessed++;
        }

        return runningAPRSum / numLogsProcessed;
    }

    function calculateAPRUsingLogs(uint256 _startIndex, uint256 _endIndex) public view returns (int256) {
        Harvest storage start = harvestLog[_startIndex];
        Harvest storage end = harvestLog[_endIndex];
        bool increasing = true;
        if (end.vaultSharePrice < start.vaultSharePrice) {
            increasing = false;
        }

        uint256 unsignedSharePriceChange;
        if (increasing) {
            unsignedSharePriceChange = end.vaultSharePrice - start.vaultSharePrice;
        } else {
            unsignedSharePriceChange = start.vaultSharePrice - end.vaultSharePrice;
        }

        uint256 unsignedPercentageChange = (unsignedSharePriceChange * 1e18) / start.vaultSharePrice;
        uint256 timeDifference = end.timestamp - start.timestamp;

        uint256 yearlyUnsignedPercentageChange = (unsignedPercentageChange * ONE_YEAR) / timeDifference;
        yearlyUnsignedPercentageChange /= 1e14; // restore basis points precision

        if (increasing) {
            return int256(yearlyUnsignedPercentageChange);
        }

        return -int256(yearlyUnsignedPercentageChange);
    }
}
