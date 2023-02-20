import pytest

## order of operations
## Deploy the vault
## Deploy strat and initialize
## Deploy xCheese
## Set xCheeseContract in strat to xCheese
## addFren - this strat needs to be fren of ceazrETHBPT 


want = Contract("0x785f08fb77ec934c01736e30546f87b4daccbe50") #ibBPT galactic dragon
WETH = Contract("0x4200000000000000000000000000000000000006")
rETH = Contract("0x9Bcef72be871e61ED4fBbc7630889beE758eb81D")
BAL = Contract("0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921")
OP = Contract("0x4200000000000000000000000000000000000042")

ceazor = ("0x3c5Aac016EF2F178e8699D6208796A2D67557fe2")
owner =  ("0x699675204aFD7Ac2BB146d60e4E3Ddc243843519")
gauge = Contract("0x1C438149E3e210233FCE91eeE1c097d34Fd655c2")
ceazrETHBPT = Contract("0x068D9D09DDC1Cf2b66A4C32eD74fFE68Db0b5f1B")
ceazIBBPT = Contract("0xd94210Cbf1D62Ff6E1C4B28552FEbcBF6aF378CB")
strat = Contract("0x6c0833eDE9937c977aDeA380848C115211c85C4b")

gauge.withdraw(9980088920118431736, {'from': ceazor})

want.approve(ceazIBBPT, 2**256-1, {'from': ceazor})
ceazIBBPT.depositAll({'from': ceazor})
xCheese = ExtraCheese.deploy(ceazIBBPT, ceazrETHBPT, strat, {'from': owner})


strat.setxCheeseRecipient(xCheese, {'from': owner})
ceazIBBPT.approve(xCheese, 2**256-1, {'from': ceazor})
xCheese.stake(1108898768902047970, {'from': ceazor})

