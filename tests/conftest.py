from CeazorVaultR.tests import HundredToLQDR
from CeazorVaultR.tests.conftest import vault
import brownie
from brownie import Contract, IHundred, ILQDR, IBalancerVault, IUniswapV2Router01

import pytest 


@pytest.fixture
def owner(accounts):
    yield accounts.at("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")

@pytest.fixture
def strategist(accounts):
    yield accounts.at("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")

@pytest.fixture
def perFeeRecipient(accounts):
    yield accounts.at("0xA67D2c03c3cfe6177a60cAed0a4cfDA7C7a563e0")

@pytest.fixture
def want():
    token_address = "0x04068da6c83afcfa0e13ba15a6696662335d5b75"  
    yield Contract(token_address)

@pytest.fixture
def hToken():
    token_address = "0x243E33aa7f6787154a8E59d3C27a66db3F8818ee"
    yield Contract(token_address)

@pytest.fixture
def LQDRPid():
    LQDRPid = 0
    yield (LQDRPid) 

@pytest.fixture
def LQDRFarm(): 
    LQDRFarm = "0x9a07fb107b9d8ea8b82ecf453efb7cfb85a66ce9"
    yield (LQDRFarm) 

@pytest.fixture
def vault(want, name, symbol):
    vault = CeazorVaultR.deploy(want, name, symbol)
    yield vault

@pytest.fixture
def strategy(vault, strategist, perFeeRecipient, want, hToken, LQDRPid, LQDRFarm):
    strategy = HundredToLQDR.deploy(vault, strategist, perFeeRecipient, want, hToken, LQDRPid, LQDRFarm)
    vault.initialize(strategy, {"from": owner})
    yield strategy

@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5



# ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
# USDC = Contract("0x04068da6c83afcfa0e13ba15a6696662335d5b75")
# hUSDC = Contract("0x243E33aa7f6787154a8E59d3C27a66db3F8818ee")
# hUSDCtoLQDR = Contract('0x9a07fb107b9d8ea8b82ecf453efb7cfb85a66ce9')

# MIM = Contract('0x82f0B8B456c1A451378467398982d4834b6829c1')
# hMIM = Contract('0xa8cD5D59827514BCF343EC19F531ce1788Ea48f8')
# hMIMtoLQDR = Contract('0xed566b089fc80df0e8d3e0ad3ad06116433bf4a7')

# FRAX = Contract('0xdc301622e621166BD8E82f2cA0A26c13Ad0BE355')
# hFRAX = Contract('0xb4300e088a3AE4e624EE5C71Bc1822F68BB5f2bc')
# hFRAXtoLQDR = Contract('0x669F5f289A5833744E830AD6AB767Ea47A3d6409')

# DAI = Contract('0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E')
# hDAI = Contract('0x8e15a22853A0A60a0FBB0d875055A8E66cff0235')
# hDAItoLQDR = Contract('0x79364e45648db09ee9314e47b2fd31c199eb03b9')





