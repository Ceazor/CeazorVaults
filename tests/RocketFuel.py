import pytest

ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
want = Contract("0x4Fd63966879300caFafBB35D157dC5229278Ed23") #rETHBPT
WETH = Contract("0x4200000000000000000000000000000000000006")
rETH = Contract("0x9Bcef72be871e61ED4fBbc7630889beE758eb81D")
BAL = Contract("0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921")
OP = Contract("0x4200000000000000000000000000000000000042")
owner =  ("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")
gauge = Contract("0x38f79beFfC211c6c439b0A3d10A0A673EE63AFb4")

vault = CeazorVaultR.deploy(want, 'CeazorRocketFuelCompounder', 'ceazrETHBPT', {'from': owner})
strat = rETHBPTComp.deploy(vault, {'from': owner})
vault.initialize(strat, {'from': owner})


gauge.withdraw(172753063351450355, {'from': ceazor})
vault.addFren(ceazor, {'from': owner})
BPTamt = want.balanceOf(ceazor)
want.approve(vault, 2**256-1, {'from': ceazor})
vault.depositAll({'from': ceazor})



 