import pytest

## order of operations
## Deploy the vault
## Deploy strat and initialize
## Deploy xCheese
## Set xCheeseContract in strat to xCheese
## addFren

ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
owner =  ("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")
want = Contract("0x785f08fb77ec934c01736e30546f87b4daccbe50") #ibBPT galactic dragon
WETH = Contract("0x4200000000000000000000000000000000000006")
rETH = Contract("0x9Bcef72be871e61ED4fBbc7630889beE758eb81D")
BAL = Contract("0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921")
OP = Contract("0x4200000000000000000000000000000000000042")
gauge = Contract("0x38f79beFfC211c6c439b0A3d10A0A673EE63AFb4")

vault = CeazorVaultR.deploy(want, 'GalacticDragonCompounder', 'ceazIBBPT', {'from': owner})
strat = ibBPTComp.deploy(vault, {'from': owner})
vault.initialize(strat, {'from': owner})

xcheese = xCheese.deploy(vault, _rewardToken, strat)







gauge.withdraw(172753063351450355, {'from': ceazor})
vault.addFren(ceazor, {'from': owner})
BPTamt = want.balanceOf(ceazor)
want.approve(vault, 2**256-1, {'from': ceazor})
vault.depositAll({'from': ceazor})

######OP Main Deployed######
vault = CeazorVaultR.deploy(want, 'CeazorRocketFuelCompounder', 'ceazrETHBPT', {'from': accounts[0]}, publish_source=True)
strat = rETHBPTComp.deploy(vault, {'from': accounts[0]}, publish_source=True)
vault.initialize(strat, {'from': owner})

vault = Contract("0x068D9D09DDC1Cf2b66A4C32eD74fFE68Db0b5f1B")
strat = Contract("0x7fF9e32C4D8359b19b7269220E73fb12Afa300C9")

CeazorVaultR.publish_source(vault, True)

addFren( ceazor)