# @version 0.2.8
"""
@title Curve Registry
@license MIT
@author Curve.Fi
"""

MAX_COINS: constant(int128) = 8


struct PoolArray:
    base_pool: address
    coins: address[2]
    decimals: uint256

struct BasePoolArray:
    implementation: address
    lp_token: address
    coins: address[MAX_COINS]
    decimals: uint256
    n_coins: uint256


interface AddressProvider:
    def admin() -> address: view
    def get_registry() -> address: view

interface Registry:
    def get_lp_token(pool: address) -> address: view
    def get_n_coins(pool: address) -> uint256: view
    def get_coins(pool: address) -> address[MAX_COINS]: view

interface ERC20:
    def balanceOf(_addr: address) -> uint256: view
    def decimals() -> uint256: view
    def totalSupply() -> uint256: view

interface CurvePool:
    def A() -> uint256: view
    def future_A() -> uint256: view
    def fee() -> uint256: view
    def admin_fee() -> uint256: view
    def future_fee() -> uint256: view
    def future_admin_fee() -> uint256: view
    def future_owner() -> address: view
    def initial_A() -> uint256: view
    def initial_A_time() -> uint256: view
    def future_A_time() -> uint256: view
    def coins(i: uint256) -> address: view
    def underlying_coins(i: uint256) -> address: view
    def balances(i: uint256) -> uint256: view
    def admin_balances(i: uint256) -> uint256: view
    def get_virtual_price() -> uint256: view
    def initialize(
        _name: String[32],
        _symbol: String[10],
        _coin: address,
        _decimals: uint256,
        _A: uint256,
        _fee: uint256,
        _owner: address,
    ): nonpayable


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383

admin: public(address)
future_admin: public(address)

pool_list: public(address[4294967296])   # master list of pools
pool_count: public(uint256)              # actual length of pool_list
pool_data: HashMap[address, PoolArray]

base_pool_list: public(address[4294967296])   # master list of pools
base_pool_count: public(uint256)         # actual length of pool_list
base_pool_data: HashMap[address, BasePoolArray]

# mapping of coins -> pools for trading
# a mapping key is generated for each pair of addresses via
# `bitwise_xor(convert(a, uint256), convert(b, uint256))`
markets: HashMap[uint256, address[4294967296]]
market_counts: HashMap[uint256, uint256]


@external
def __init__():
    self.admin = msg.sender


@view
@external
def find_pool_for_coins(_from: address, _to: address, i: uint256 = 0) -> address:
    """
    @notice Find an available pool for exchanging two coins
    @param _from Address of coin to be sent
    @param _to Address of coin to be received
    @param i Index value. When multiple pools are available
            this value is used to return the n'th address.
    @return Pool address
    """
    key: uint256 = bitwise_xor(convert(_from, uint256), convert(_to, uint256))
    return self.markets[key][i]


@view
@external
def get_n_coins(_pool: address) -> (uint256, uint256):
    """
    @notice Get the number of coins in a pool
    @param _pool Pool address
    @return Number of wrapped coins, number of underlying coins
    """
    base_pool: address = self.pool_data[_pool].base_pool
    return 2, self.base_pool_data[base_pool].n_coins + 1


@view
@external
def get_coins(_pool: address) -> address[2]:
    """
    @notice Get the coins within a pool
    @dev For pools using lending, these are the wrapped coin addresses
    @param _pool Pool address
    @return List of coin addresses
    """
    return self.pool_data[_pool].coins


@view
@external
def get_underlying_coins(_pool: address) -> address[MAX_COINS]:
    """
    @notice Get the underlying coins within a pool
    @dev For pools that do not lend, returns the same value as `get_coins`
    @param _pool Pool address
    @return List of coin addresses
    """
    coins: address[MAX_COINS] = empty(address[MAX_COINS])
    coins[0] = self.pool_data[_pool].coins[0]
    base_pool: address = self.pool_data[_pool].base_pool
    for i in range(1, MAX_COINS):
        coins[i] = self.base_pool_data[base_pool].coins[i - 1]
        if coins[i] == ZERO_ADDRESS:
            break

    return coins


@view
@external
def get_decimals(_pool: address) -> uint256[2]:
    """
    @notice Get decimal places for each coin within a pool
    @dev For pools using lending, these are the wrapped coin decimal places
    @param _pool Pool address
    @return uint256 list of decimals
    """
    decimals: uint256[2] = [0, 18]
    decimals[0] = self.pool_data[_pool].decimals
    return decimals


@view
@external
def get_underlying_decimals(_pool: address) -> uint256[MAX_COINS]:
    """
    @notice Get decimal places for each underlying coin within a pool
    @dev For pools that do not lend, returns the same value as `get_decimals`
    @param _pool Pool address
    @return uint256 list of decimals
    """
    # decimals are tightly packed as a series of uint8 within a little-endian bytes32
    # the packed value is stored as uint256 to simplify unpacking via shift and modulo
    decimals: uint256[MAX_COINS] = empty(uint256[MAX_COINS])
    decimals[0] = self.pool_data[_pool].decimals
    base_pool: address = self.pool_data[_pool].base_pool
    packed_decimals: uint256 = self.base_pool_data[base_pool].decimals
    for i in range(MAX_COINS):
        unpacked: uint256 = shift(packed_decimals, -8 * i) % 256
        if unpacked == 0:
            break
        decimals[i+1] = unpacked

    return decimals


@view
@external
def get_rates(_pool: address) -> uint256[2]:
    """
    @notice Get rates between coins and underlying coins
    @dev For coins where there is no underlying coin, or where
         the underlying coin cannot be swapped, the rate is
         given as 1e18
    @param _pool Pool address
    @return Rates between coins and underlying coins
    """
    rates: uint256[2] = [10**18, 0]
    rates[1] = CurvePool(self.pool_data[_pool].base_pool).get_virtual_price()
    return rates


@view
@external
def get_balances(_pool: address) -> uint256[2]:
    """
    @notice Get balances for each coin within a pool
    @dev For pools using lending, these are the wrapped coin balances
    @param _pool Pool address
    @return uint256 list of balances
    """
    return [CurvePool(_pool).balances(0), CurvePool(_pool).balances(1)]


@view
@external
def get_underlying_balances(_pool: address) -> uint256[MAX_COINS]:
    """
    @notice Get balances for each underlying coin within a pool
    @dev  For pools that do not lend, returns the same value as `get_balances`
    @param _pool Pool address
    @return uint256 list of underlyingbalances
    """

    underlying_balances: uint256[MAX_COINS] = empty(uint256[MAX_COINS])
    underlying_balances[0] = CurvePool(_pool).balances(0)

    base_total_supply: uint256 = ERC20(self.pool_data[_pool].coins[1]).totalSupply()
    if base_total_supply > 0:
        underlying_pct: uint256 = CurvePool(_pool).balances(1) * 10**36 / base_total_supply
        base_pool: address = self.pool_data[_pool].base_pool
        n_coins: uint256 = self.base_pool_data[base_pool].n_coins
        for i in range(MAX_COINS):
            if i == n_coins:
                break
            underlying_balances[i + 1] = CurvePool(base_pool).balances(i) * underlying_pct / 10**36

    return underlying_balances


@view
@external
def get_A(_pool: address) -> uint256:
    return CurvePool(_pool).A()


@view
@external
def get_fees(_pool: address) -> (uint256, uint256):
    """
    @notice Get the fees for a pool
    @dev Fees are expressed as integers
    @return Pool fee as uint256 with 1e10 precision
    """
    return CurvePool(_pool).fee(), CurvePool(_pool).admin_fee()


@view
@external
def get_admin_balances(_pool: address) -> uint256[2]:
    """
    @notice Get the current admin balances (uncollected fees) for a pool
    @param _pool Pool address
    @return List of uint256 admin balances
    """
    return [CurvePool(_pool).admin_balances(0), CurvePool(_pool).admin_balances(1)]


@view
@external
def get_coin_indices(
    _pool: address,
    _from: address,
    _to: address
) -> (int128, int128, bool):
    """
    @notice Convert coin addresses to indices for use with pool methods
    @param _from Coin address to be used as `i` within a pool
    @param _to Coin address to be used as `j` within a pool
    @return int128 `i`, int128 `j`, boolean indicating if `i` and `j` are underlying coins
    """
    coin: address = self.pool_data[_pool].coins[0]
    if coin in [_from, _to]:
        base_lp_token: address = self.pool_data[_pool].coins[1]
        if base_lp_token in [_from, _to]:
            # True and False convert to 1 and 0 - a bit of voodoo that
            # works because we only ever have 2 non-underlying coins
            return convert(_to == coin, int128), convert(_from == coin, int128), False

    base_pool: address = self.pool_data[_pool].base_pool
    found_market: bool = False
    i: int128 = 0
    j: int128 = 0
    for x in range(MAX_COINS):
        if x != 0:
            coin = self.base_pool_data[base_pool].coins[x-1]
        if coin == ZERO_ADDRESS:
            raise "No available market"
        if coin == _from:
            i = x
        elif coin == _to:
            j = x
        else:
            continue
        if found_market:
            # the second time we find a match, break out of the loop
            break
        # the first time we find a match, set `found_market` to True
        found_market = True

    return i, j, True


@external
def add_base_pool(
    _base_pool: address,
    _metapool_implementation: address,
):
    """
    @notice Add a pool to the registry
    @dev Only callable by admin
    @param _base_pool Pool address to add
    """
    assert msg.sender == self.admin  # dev: admin-only function
    assert self.base_pool_data[_base_pool].coins[0] == ZERO_ADDRESS  # dev: pool exists

    registry: address = AddressProvider(ADDRESS_PROVIDER).get_registry()
    n_coins: uint256 = Registry(registry).get_n_coins(_base_pool)

    # add pool to pool_list
    length: uint256 = self.base_pool_count
    self.base_pool_list[length] = _base_pool
    self.base_pool_count = length + 1
    self.base_pool_data[_base_pool].implementation = _metapool_implementation
    self.base_pool_data[_base_pool].lp_token = Registry(registry).get_lp_token(_base_pool)
    self.base_pool_data[_base_pool].n_coins = n_coins

    decimals: uint256 = 0
    coins: address[MAX_COINS] = Registry(registry).get_coins(_base_pool)
    for i in range(MAX_COINS):
        if i == n_coins:
            break
        coin: address = coins[i]
        self.base_pool_data[_base_pool].coins[i] = coin
        decimals += shift(ERC20(coin).decimals(), convert(i*8, int128))

    self.base_pool_data[_base_pool].decimals = decimals


@external
def deploy_metapool(
    _base_pool: address,
    _name: String[32],
    _symbol: String[10],
    _coin: address,
    _A: uint256,
    _fee: uint256,
) -> address:
    """
    @notice Add a pool to the registry
    @dev Only callable by admin
    @param _base_pool Pool address to add
    """
    implementation: address = self.base_pool_data[_base_pool].implementation
    assert implementation != ZERO_ADDRESS

    decimals: uint256 = ERC20(_coin).decimals()
    pool: address = create_forwarder_to(implementation)
    CurvePool(pool).initialize(_name, _symbol, _coin, decimals, _A, _fee, self.admin)

    # add pool to pool_list
    length: uint256 = self.pool_count
    self.pool_list[length] = pool
    self.pool_count = length + 1

    base_lp_token: address = self.base_pool_data[_base_pool].lp_token

    self.pool_data[pool].decimals = decimals
    self.pool_data[pool].base_pool = _base_pool
    self.pool_data[pool].coins = [_coin, self.base_pool_data[_base_pool].lp_token]

    is_finished: bool = False
    for i in range(MAX_COINS):
        swappable_coin: address = self.base_pool_data[_base_pool].coins[i]
        if swappable_coin == ZERO_ADDRESS:
            is_finished = True
            swappable_coin = base_lp_token

        key: uint256 = bitwise_xor(convert(_coin, uint256), convert(swappable_coin, uint256))
        length = self.market_counts[key]
        self.markets[key][length] = pool
        self.market_counts[key] = length + 1
        if is_finished:
            break

    return pool


@external
def commit_transfer_ownership(addr: address):
    """
    @notice Transfer ownership of GaugeController to `addr`
    @param addr Address to have ownership transferred to
    """
    assert msg.sender == self.admin  # dev: admin only

    self.future_admin = addr


@external
def accept_transfer_ownership():
    """
    @notice Accept a pending ownership transfer
    """
    _admin: address = self.future_admin
    assert msg.sender == _admin  # dev: future admin only

    self.admin = _admin
    self.future_admin = ZERO_ADDRESS
