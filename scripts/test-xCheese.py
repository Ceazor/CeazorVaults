################
##EXTRA CHEESE##
####DEPLOYER####
################

# Gather the params
cre8r = Contract("0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0")
ceazfBEETs = Contract("0x58E0ac1973F9d182058E6b63e7F4979bc333f493")

#Deploy
xCheese = ExtraCheese.deploy(ceazfBEETs, cre8r, {'from': accounts[0]})

#ADD some rewards then!
xCheese.notifyRewardAmount({'from': owner})

#TESTING
owner = "0x699675204aFD7Ac2BB146d60e4E3Ddc243843519"
hotwallet = "0xA67D2c03c3cfe6177a60cAed0a4cfDA7C7a563e0"
ceazor = "0x3c5Aac016EF2F178e8699D6208796A2D67557fe2"

cre8r.transfer(xCheese, 5*10e18, {'from': hotwallet})
xCheese.notifyRewardAmount({'from': owner})
xCheese.rewardRate()
19023790391311

cre8r.transfer(xCheese, 1*10e18, {'from': hotwallet})
xCheese.rewardRate()
19023790391311

xCheese.notifyRewardAmount({'from': owner})
xCheese.rewardRate()
22828548469574

xCheese.changeDuration(604800, {'from': owner})
xCheese.rewardRate()
99206349206349