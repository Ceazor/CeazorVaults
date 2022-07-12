from CeazorVaults.tests import HundredToLQDR
from CeazorVaults.tests.conftest import vault
import brownie
from brownie import Contract
import pytest


# to run input, $ brownie test ./tests/test_operation2.py --network ftm-main-fork

def vault_initialize(vault, strategy, owner):   
    #Initialize them
    vault.initialize(strategy, {'from': owner})


def test_operation(
    chain, USDC, vault, strategy, ceazor, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    ceazor_balance_before = USDC.balanceOf(ceazor)
    amount = ceazor_balance_before
    USDC.approve(vault.address, amount, {"from": ceazor})
    vault.deposit(amount, {"from": ceazor})
    assert USDC.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.balanceOf(), rel=RELATIVE_APPROX) == amount

    # withdrawal
    vault.withdraw({"from": ceazor})
    assert (
        pytest.approx(USDC.balanceOf(ceazor), rel=RELATIVE_APPROX) == ceazor_balance_before
    )


def test_LQDRpanic(
    chain, USDC, vault, strategy, ceazor, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    USDC.approve(vault.address, amount, {"from": ceazor})
    vault.deposit(amount, {"from": ceazor})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # pulls funds out of LQDR
    strategy.LQDRpanic()
    chain.sleep(1)
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < amount

def test_bigPanic(
    chain, USDC, vault, strategy, ceazor, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    USDC.approve(vault.address, amount, {"from": ceazor})
    vault.deposit(amount, {"from": ceazor})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # Pulls funds all the way back to vault
    strategy.bigPanic()
    chain.sleep(1)
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < amount


def test_profitable_harvest(
    chain, USDC, vault, strategy, ceazor, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    USDC.approve(vault.address, amount, {"from": ceazor})
    vault.deposit(amount, {"from": ceazor})
    assert USDC.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # TODO: Add some code before harvest #2 to simulate earning yield

    # Harvest 2: Realize profit
    chain.sleep(1)
    strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = USDC.balanceOf(vault.address)  # Profits go to vault
    # TODO: Uncomment the lines below
    assert USDC.balanceOf(strategy) + profit > amount
    # assert vault.pricePerShare() > before_pps



def test_sweep(gov, vault, strategy, USDC, ceazor, amount, weth, weth_amout):
    # Strategy want USDC doesn't work
    USDC.transfer(strategy, amount, {"from": ceazor})
    assert USDC.address == strategy.want()
    assert USDC.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(USDC, {"from": gov})

    # Vault share USDC doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})

    # TODO: If you add protected USDCs to the strategy.
    # Protected USDC doesn't work
    # with brownie.reverts("!protected"):
    #     strategy.sweep(strategy.protectedUSDC(), {"from": gov})

    before_balance = weth.balanceOf(gov)
    weth.transfer(strategy, weth_amout, {"from": ceazor})
    assert weth.address != strategy.want()
    assert weth.balanceOf(ceazor) == 0
    strategy.sweep(weth, {"from": gov})
    assert weth.balanceOf(gov) == weth_amout + before_balance


def test_triggers(
    chain, gov, vault, strategy, USDC, amount, ceazor, weth, weth_amout, strategist
):
    # Deposit to the vault and harvest
    USDC.approve(vault.address, amount, {"from": ceazor})
    vault.deposit(amount, {"from": ceazor})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()

    strategy.harvestTrigger(0)
    strategy.tendTrigger(0)
